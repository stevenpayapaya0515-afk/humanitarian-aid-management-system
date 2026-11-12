"""Local configuration checks only. Does not send email or print credentials."""
import sys
import os
import json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from database import get_connection
from core.login_otp import _otp_key
from services.gmail_login_email import _token_path, _sender_email

def main():
    failed = []
    def check(name, function):
        try:
            function()
            print('PASS:', name)
        except Exception as error:
            failed.append(name)
            print('FAIL:', name, '(' + type(error).__name__ + ')')
    def captcha():
        value = os.getenv('RECAPTCHA_SECRET_KEY', '').strip()
        assert value and not any(x in value.upper() for x in ('PASTE_', 'YOUR_', 'HERE'))
        assert 'localhost' in {x.strip().lower() for x in os.getenv('RECAPTCHA_ALLOWED_HOSTNAMES', '').split(',')}
    def gmail():
        _sender_email()
        payload = json.loads(_token_path().read_text())
        assert all(payload.get(k) for k in ('refresh_token', 'client_id', 'client_secret'))
    def database():
        with get_connection() as c:
            c.execute("SET LOCAL statement_timeout = '3s'")
            c.execute("SET LOCAL lock_timeout = '1s'")
            c.execute('SELECT user_id, auth_version, failed_login_attempts, locked_until FROM public.users LIMIT 0')
            c.execute('SELECT challenge_id, sent_at, invalidated_at FROM public.login_otps LIMIT 0')
    check('reCAPTCHA secret present and localhost allowed (not live key validation)', captcha)
    check('OTP HMAC secret format', _otp_key)
    check('Gmail sender and refresh credentials present (not live authorization)', gmail)
    check('Database connection and login schema', database)
    print('No keys, tokens, passwords or email addresses were printed.')
    return 1 if failed else 0

if __name__ == '__main__':
    raise SystemExit(main())
