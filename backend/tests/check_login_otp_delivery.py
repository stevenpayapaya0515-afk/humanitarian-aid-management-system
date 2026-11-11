"""Local AidTrack end-to-end login OTP delivery verification (developer only).

Run interactively from backend/:
    .\\.venv\\Scripts\\python.exe tests\\check_login_otp_delivery.py

This checks PostgreSQL challenge creation, Gmail delivery, and OTP consumption.
It does NOT validate passwords, authenticate a session, issue a JWT or change
FastAPI routes. It should NEVER be exposed as an HTTP endpoint.

Only run for an account whose inbox you are authorized to access.
"""

import getpass
import sys
from pathlib import Path

from psycopg.rows import dict_row

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from database import get_connection
from services.login_otp_store import (
    OTPAccountUnavailable,
    OTPRateLimited,
    check_login_otp,
    create_login_challenge,
    invalidate_login_challenge,
    mark_login_otp_sent,
)
from services.gmail_login_email import (
    GmailConfigError,
    GmailDeliveryError,
    send_login_otp_email,
)


def invalidate(challenge_id):
    with get_connection() as connection:
        invalidate_login_challenge(connection, challenge_id=challenge_id)


def main():
    print("AidTrack | Local end-to-end OTP delivery test")
    print("This test does not sign anyone in or issue a JWT.")
    email = input("Existing active AidTrack account email (with inbox access): ").strip().lower()
    if not email:
        print("CANCELLED: Account email is required.")
        return 1
    consent = input("Can you access this account's inbox? Type YES to continue: ").strip()
    if consent != "YES":
        print("CANCELLED: No email was sent.")
        return 1

    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    """SELECT user_id, email FROM public.users
                       WHERE lower(email) = %s AND is_active = TRUE;""",
                    (email,),
                )
                user = cursor.fetchone()
        if user is None:
            print("CANCELLED: No matching active AidTrack account; no email was sent.")
            return 1

        # Create and commit the pending challenge so other transactions see it.
        try:
            with get_connection() as connection:
                challenge = create_login_challenge(
                    connection, user_id=user["user_id"], email=user["email"]
                )
        except OTPRateLimited as exc:
            print(f"RATE LIMITED: Try again in {exc.retry_after} seconds.")
            return 1
        except OTPAccountUnavailable:
            print("CANCELLED: Account is unavailable.")
            return 1

        print("Pending OTP saved to PostgreSQL (HMAC hash, not plaintext).")
        try:
            send_login_otp_email(
                to_email=user["email"],
                code=challenge.code,
                expires_at=challenge.expires_at,
            )
        except (GmailConfigError, GmailDeliveryError, ValueError) as exc:
            invalidate(challenge.challenge_id)
            print(f"FAIL: Gmail did not accept the OTP message: {exc}")
            return 1
        except Exception:
            invalidate(challenge.challenge_id)
            raise

        # Gmail API acceptance is not a guarantee of inbox delivery.
        with get_connection() as connection:
            marked = mark_login_otp_sent(
                connection, challenge_id=challenge.challenge_id
            )
        if not marked:
            invalidate(challenge.challenge_id)
            print("FAIL: OTP could not be marked sent, probably expired/invalidated.")
            return 1

        print("Gmail accepted the login OTP message; check your inbox or Spam.")
        print("The OTP expires in five minutes, and only 3 attempts are allowed.")
        for attempt in range(1, 4):
            entry = getpass.getpass(f"Enter the received 6-digit code ({attempt}/3): ")
            with get_connection() as connection:
                result = check_login_otp(
                    connection,
                    challenge_id=challenge.challenge_id,
                    entered_code=entry,
                )
            if result.verified:
                print("PASS: Gmail delivery + PostgreSQL OTP verification succeeded.")
                print("PASS: OTP consumed once; no JWT or login session created.")
                return 0
            if result.status == "expired":
                print("EXPIRED: This OTP is no longer valid.")
                return 1
            print("Incorrect, invalid or no longer active OTP.")

        print("FAIL: 3 invalid OTP attempts; the challenge is now invalidated.")
        return 1
    except KeyboardInterrupt:
        print("\nInterrupted. If an OTP was sent, it remains pending until expiry.")
        return 1
    except Exception as exc:
        print(f"FAIL: Local OTP integration test encountered {type(exc).__name__}.")
        # Avoid printing secret-containing provider, database or authentication details.
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
