"""Single-use image CAPTCHA, persisted across API workers and restarts.

A basic local bot hurdle, not a substitute for deployment-level rate limits.
"""
import base64
import hashlib
import hmac
import io
import secrets
from uuid import uuid4

from fastapi import HTTPException
from PIL import Image, ImageDraw, ImageFont
from psycopg.rows import dict_row

from core.login_otp import _otp_key
from database import get_connection


def _digest(challenge_id, answer):
    return hmac.new(_otp_key(), f"captcha:{challenge_id}:{answer.upper()}".encode(),
                    hashlib.sha256).hexdigest()


def issue_captcha(client_ip):
    challenge_id = uuid4()
    answer = ''.join(secrets.choice('23456789ABCDEFGHJKLMNPQRSTUVWXYZ') for _ in range(6))
    # Serialize per-IP issuance across processes using a PostgreSQL transaction
    # advisory lock. No trust is placed in caller-supplied forwarding headers.
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute("SELECT pg_advisory_xact_lock(hashtext(%s))", ('captcha:' + client_ip,))
            cursor.execute("""SELECT COUNT(*) AS n FROM public.login_captchas
                WHERE requested_ip = %s AND created_at > NOW() - INTERVAL '15 minutes'""",
                           (client_ip,))
            if cursor.fetchone()['n'] >= 30:
                raise HTTPException(429, 'Too many security code requests. Try again later.',
                                    headers={'Retry-After': '900'})
            cursor.execute("""INSERT INTO public.login_captchas
                (challenge_id, answer_hmac, requested_ip, expires_at)
                VALUES (%s, %s, %s, NOW() + INTERVAL '5 minutes')""",
                           (challenge_id, _digest(challenge_id, answer), client_ip))
    image = Image.new('RGB', (240, 72), '#edf5ed')
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=34)
    for _ in range(12):
        draw.line([(secrets.randbelow(240), secrets.randbelow(72)),
                   (secrets.randbelow(240), secrets.randbelow(72))], fill='#a3bbaa', width=1)
    for index, char in enumerate(answer):
        draw.text((12 + index * 36, 12 + secrets.randbelow(15)), char, font=font, fill='#185c37')
    output = io.BytesIO()
    image.save(output, format='PNG')
    return {'captcha_id': str(challenge_id),
            'image_base64': base64.b64encode(output.getvalue()).decode()}


def consume_captcha(challenge_id, answer):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute("""UPDATE public.login_captchas SET consumed_at = NOW()
                WHERE challenge_id = %s AND consumed_at IS NULL AND expires_at > NOW()
                RETURNING answer_hmac""", (challenge_id,))
            row = cursor.fetchone()
    # Every attempt consumes the challenge, including incorrect answers.
    return bool(row and hmac.compare_digest(row['answer_hmac'], _digest(challenge_id, answer.strip())))
