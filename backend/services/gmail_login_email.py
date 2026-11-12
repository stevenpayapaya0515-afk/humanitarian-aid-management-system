"""Gmail API sender for AidTrack *login* verification emails.

Uses a pre-authorized OAuth token with the minimal gmail.send scope.
No JWTs, database writes, or FastAPI routes are implemented here.
Keep the token JSON and all Gmail credentials out of Git.
"""

import logging
logger = logging.getLogger("uvicorn.error")

import base64
import os
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from email.utils import parseaddr
from pathlib import Path

from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parents[1]
load_dotenv(BACKEND_DIR / ".env")
GMAIL_SEND_SCOPE = "https://www.googleapis.com/auth/gmail.send"


class GmailConfigError(RuntimeError):
    """The Gmail OAuth sender is not configured correctly."""


class GmailDeliveryError(RuntimeError):
    """Gmail did not confirm accepting the outgoing message."""


def _email_address(value: str) -> str:
    """Accept a single mailbox, not a header, list of addresses or display name."""
    if not isinstance(value, str):
        raise ValueError("An email address is required.")
    cleaned = value.strip()
    if (not cleaned or any(ord(c) <= 32 or ord(c) == 127 for c in cleaned)
            or cleaned.count("@") != 1):
        raise ValueError("Please supply one valid email address.")
    display_name, parsed = parseaddr(cleaned)
    if display_name or parsed != cleaned or not parsed.split("@", 1)[1]:
        raise ValueError("Please supply one valid email address.")
    return cleaned.lower()


def _sender_email() -> str:
    value = os.getenv("GMAIL_SENDER_EMAIL", "").strip()
    if not value:
        raise GmailConfigError("Set GMAIL_SENDER_EMAIL in backend/.env.")
    try:
        return _email_address(value)
    except ValueError as exc:
        raise GmailConfigError("GMAIL_SENDER_EMAIL must be one valid address.") from exc


def _token_path() -> Path:
    configured = os.getenv("GMAIL_TOKEN_PATH", "secrets/gmail_token.json").strip()
    if not configured:
        raise GmailConfigError("GMAIL_TOKEN_PATH cannot be empty.")
    path = Path(configured).expanduser()
    return path if path.is_absolute() else BACKEND_DIR / path


def _make_message(*, to_email: str, subject: str, body: str) -> EmailMessage:
    msg = EmailMessage()
    msg["From"] = f"AidTrack <{_sender_email()}>"
    msg["To"] = _email_address(to_email)
    msg["Subject"] = subject
    msg.set_content(body)
    return msg


def build_login_otp_message(
    *, to_email: str, code: str, expires_at: datetime
) -> EmailMessage:
    """Build the email only; use send_login_otp_email() to deliver it."""
    if not (isinstance(code, str) and len(code) == 6
            and code.isascii() and code.isdigit()):
        raise ValueError("A login verification code must be exactly six digits.")
    if not isinstance(expires_at, datetime) or expires_at.tzinfo is None:
        raise ValueError("expires_at must be a timezone-aware datetime.")
    if expires_at.astimezone(timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError("Cannot send an expired login verification code.")

    expiry = expires_at.astimezone(timezone(timedelta(hours=8)))
    expiry_text = expiry.strftime("%B %d, %Y at %I:%M %p PHT")
    body = (
        "Your AidTrack login verification code is:\n\n"
        f"    {code}\n\n"
        f"This code expires on {expiry_text}.\n"
        "Enter it in AidTrack to finish signing in.\n\n"
        "Do not share this code with anyone.\n"
        "If you did not request this code, ignore this email and "
        "consider changing your password.\n"
    )
    return _make_message(
        to_email=to_email,
        subject="AidTrack | Your login verification code",
        body=body,
    )


def _load_oauth_credentials():
    """Load (and if necessary refresh) a *server-side* Gmail OAuth token."""
    # Imported only when we actually send mail, so offline template tests run
    # independently from Google client library installation.
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials

    path = _token_path()
    if not path.is_file():
        raise GmailConfigError(
            "Gmail token missing. Copy your existing PeakGym Gmail OAuth "
            "token.json to backend/secrets/gmail_token.json."
        )
    try:
        credentials = Credentials.from_authorized_user_file(
            str(path), scopes=[GMAIL_SEND_SCOPE]
        )
    except (OSError, ValueError) as exc:
        raise GmailConfigError(
            "Gmail OAuth token cannot be read; re-authorize using the "
            "gmail.send scope if required."
        ) from exc

    if not credentials.valid:
        logger.info("LOGIN Gmail OAuth refresh started")
        if not credentials.refresh_token:
            raise GmailConfigError(
                "Gmail OAuth token has no refresh token. Re-authorize the "
                "Gmail sender with offline access and gmail.send scope."
            )
        try:
            credentials.refresh(lambda *args, **kwargs: Request()(*args, **dict(kwargs, timeout=15)))
            # Refreshing can change token data. Keep the renewed credentials
            # in the same ignored local secret file.
            path.write_text(credentials.to_json(), encoding="utf-8")
        except Exception as exc:
            reason = "invalid_grant" if "invalid_grant" in str(exc) else type(exc).__name__
            logger.warning("LOGIN Gmail OAuth refresh failed: %s", reason)
            raise GmailConfigError(
                "Gmail OAuth token refresh failed. Re-authorize the sender "
                "and verify your network/Gmail API access."
            ) from exc

    return credentials


def _send_message(message: EmailMessage) -> str:
    from googleapiclient.discovery import build
    from google_auth_httplib2 import AuthorizedHttp
    import httplib2

    logger.info("LOGIN Gmail loading credentials")
    credentials = _load_oauth_credentials()
    logger.info("LOGIN Gmail credentials ready; sending message")
    encoded = base64.urlsafe_b64encode(message.as_bytes()).decode("ascii")
    try:
        service = build("gmail", "v1",
                        http=AuthorizedHttp(credentials, http=httplib2.Http(timeout=15)),
                        cache_discovery=False, static_discovery=True)
        result = (
            service.users()
            .messages()
            .send(userId="me", body={"raw": encoded})
            .execute(num_retries=0)
        )
    except Exception as exc:
        status = getattr(getattr(exc, "resp", None), "status", None)
        logger.warning("LOGIN Gmail send failed: %s status=%s",
                       type(exc).__name__, status if isinstance(status, int) else "unknown")
        # Never expose Google errors, OAuth tokens, or email content to clients.
        raise GmailDeliveryError(
            "Gmail API could not send the message. Check token scope, "
            "Gmail API access and connectivity."
        ) from exc

    message_id = result.get("id") if isinstance(result, dict) else None
    if not message_id:
        raise GmailDeliveryError("Gmail API did not return a message ID.")
    return message_id


def send_login_otp_email(
    *, to_email: str, code: str, expires_at: datetime
) -> str:
    """Send a real OTP. Return the Gmail message id, never the code."""
    return _send_message(
        build_login_otp_message(
            to_email=to_email, code=code, expires_at=expires_at
        )
    )


def send_test_email(*, to_email: str) -> str:
    """Send one harmless email to verify Gmail API authorization/delivery."""
    return _send_message(
        _make_message(
            to_email=to_email,
            subject="AidTrack | Gmail API connection test",
            body=(
                "Your AidTrack Gmail API connection test was accepted.\n\n"
                "This is only a test. No OTP or login session was created.\n"
            ),
        )
    )
