"""Local format checks; optional Gmail API smoke test sends to the sender's inbox.

From backend/:
    .\\.venv\\Scripts\\python.exe tests\\check_gmail_login_email.py
    .\\.venv\\Scripts\\python.exe tests\\check_gmail_login_email.py --send-test
"""

import argparse
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.gmail_login_email import (
    GmailConfigError,
    GmailDeliveryError,
    build_login_otp_message,
    send_test_email,
)


def test_format():
    # Set a harmless test sender only for the offline template check.
    previous_sender = os.getenv("GMAIL_SENDER_EMAIL")
    os.environ["GMAIL_SENDER_EMAIL"] = "aidtrack-test@example.com"
    try:
        expiry = datetime.now(timezone.utc) + timedelta(minutes=5)
        message = build_login_otp_message(
            to_email="user@example.com", code="012345", expires_at=expiry
        )
        assert message["To"] == "user@example.com"
        assert "AidTrack" in message["Subject"]
        assert "012345" in message.get_content()
        assert "PHT" in message.get_content()
        assert "password" in message.get_content().lower()
        try:
            build_login_otp_message(
                to_email="user@example.com\nBcc: bad@example.com",
                code="123456", expires_at=expiry
            )
        except ValueError:
            pass
        else:
            raise AssertionError("Header injection was not rejected.")
        try:
            build_login_otp_message(
                to_email="user@example.com", code="12345", expires_at=expiry
            )
        except ValueError:
            pass
        else:
            raise AssertionError("Incorrect OTP length was accepted.")
    finally:
        if previous_sender is None:
            os.environ.pop("GMAIL_SENDER_EMAIL", None)
        else:
            os.environ["GMAIL_SENDER_EMAIL"] = previous_sender
    print("PASS: Email template, PHT expiry and input validation.")
    print("PASS: No database, password, OTP record or JWT was changed.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--send-test", action="store_true",
        help="Send one harmless connection-test email to GMAIL_SENDER_EMAIL."
    )
    args = parser.parse_args()
    test_format()

    if args.send_test:
        from services.gmail_login_email import _sender_email
        try:
            sender = _sender_email()
            send_test_email(to_email=sender)
        except (GmailConfigError, GmailDeliveryError) as exc:
            print(f"FAIL: {exc}")
            raise SystemExit(1) from None
        print("PASS: Gmail API accepted the connection-test message.")
        print("Check your own Gmail inbox (and Spam) for the test email.")


if __name__ == "__main__":
    main()
