
"""Check AidTrack's local login configuration without exposing credentials."""

import sys
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
            print("PASS:", name)
        except Exception as error:
            failed.append(name)
            print("FAIL:", name, "(" + type(error).__name__ + ")")

    def gmail():
        _sender_email()
        payload = json.loads(_token_path().read_text())
        assert all(
            payload.get(key)
            for key in ("refresh_token", "client_id", "client_secret")
        )

    def database():
        with get_connection() as connection:
            connection.execute("SET LOCAL statement_timeout = '3s'")
            connection.execute("SET LOCAL lock_timeout = '1s'")
            connection.execute(
                "SELECT user_id, auth_version, failed_login_attempts, "
                "locked_until FROM public.users LIMIT 0"
            )
            connection.execute(
                "SELECT challenge_id, sent_at, invalidated_at "
                "FROM public.login_otps LIMIT 0"
            )

    check("OTP HMAC secret format", _otp_key)
    check("Gmail sender and refresh credentials present", gmail)
    check("Database connection and login schema", database)

    print("No keys, tokens, passwords or email addresses were printed.")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
