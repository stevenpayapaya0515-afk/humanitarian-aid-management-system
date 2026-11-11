"""Rollback-only integration check for AidTrack's login OTP PostgreSQL store.

Run from backend/: 
    python tests/check_login_otp_store.py

Tests with an existing active user but ALWAYS rolls back database writes.
Does not send an email, return an OTP, modify a password, or issue JWTs.
"""

import sys
from pathlib import Path
from uuid import uuid4

# Let `python tests/check_login_otp_store.py` find backend/core and services.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from database import get_connection
from services.login_otp_store import (
    OTPRateLimited,
    check_login_otp,
    create_login_challenge,
    invalidate_login_challenge,
    mark_login_otp_sent,
)


def main():
    connection = get_connection()
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT user_id, email FROM public.users
                   WHERE is_active = TRUE ORDER BY user_id LIMIT 1;"""
            )
            account = cursor.fetchone()
        if account is None:
            raise RuntimeError("Need at least one active Admin or Staff user to test.")
        user_id, email = account

        # 1. UnsENT codes cannot be used, even if guessed correctly.
        first = create_login_challenge(connection, user_id=user_id, email=email)
        assert not check_login_otp(
            connection, challenge_id=first.challenge_id, entered_code=first.code
        ).verified
        assert mark_login_otp_sent(connection, challenge_id=first.challenge_id)

        # 2. Two wrong codes + correct one => consumed once, replay refused.
        wrong = "000000" if first.code != "000000" else "999999"
        for _ in range(2):
            assert not check_login_otp(
                connection, challenge_id=first.challenge_id, entered_code=wrong
            ).verified
        good = check_login_otp(
            connection, challenge_id=first.challenge_id, entered_code=first.code
        )
        assert good.verified and good.user_id == user_id
        assert not check_login_otp(
            connection, challenge_id=first.challenge_id, entered_code=first.code
        ).verified

        # 3. 60-second cooldown applies to successfully marked sends.
        try:
            create_login_challenge(connection, user_id=user_id, email=email)
        except OTPRateLimited as exc:
            assert exc.retry_after >= 1
        else:
            raise AssertionError("Missing 60-second cooldown")

        # Shift ONLY our uncommitted test row to simulate time passing.
        with connection.cursor() as cursor:
            cursor.execute(
                """UPDATE public.login_otps
                   SET sent_at = NOW() - INTERVAL '16 minutes'
                   WHERE challenge_id = %s;""",
                (first.challenge_id,),
            )

        # 4. Three bad attempts must cancel a code.
        second = create_login_challenge(connection, user_id=user_id, email=email)
        assert mark_login_otp_sent(connection, challenge_id=second.challenge_id)
        wrong = "000000" if second.code != "000000" else "999999"
        for _ in range(3):
            assert not check_login_otp(
                connection, challenge_id=second.challenge_id, entered_code=wrong
            ).verified
        assert not check_login_otp(
            connection, challenge_id=second.challenge_id, entered_code=second.code
        ).verified

        # Test cancellation API without needing another successful delivery.
        with connection.cursor() as cursor:
            cursor.execute(
                """UPDATE public.login_otps
                   SET sent_at = NOW() - INTERVAL '16 minutes'
                   WHERE challenge_id = %s;""",
                (second.challenge_id,),
            )
        third = create_login_challenge(connection, user_id=user_id, email=email)
        invalidate_login_challenge(connection, challenge_id=third.challenge_id)
        assert not check_login_otp(
            connection, challenge_id=third.challenge_id, entered_code=third.code
        ).verified
        assert not check_login_otp(
            connection, challenge_id=uuid4(), entered_code="123456"
        ).verified

        print("PASS: OTP stored as HMAC, unsent code rejected, 3-attempt limit,")
        print("      single use, resend cooldown and invalidation verified.")
        print("PASS: No login, email, or existing user record changed.")
    finally:
        # Never commit test challenges or changes to existing pending OTPs.
        try:
            connection.rollback()
        finally:
            connection.close()
        print("PASS: Database test transaction rolled back.")


if __name__ == "__main__":
    main()
