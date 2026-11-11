"""AidTrack's PostgreSQL storage layer for pending *login* email OTPs.

This service intentionally does NOT issue JWTs or send mail. Route wiring and
mail delivery are separate steps; the existing /auth/login stays unchanged.

Call these functions inside ``with get_connection() as connection:`` so all
updates commit on success and roll back on an exception. Keep the OTP secret
and plaintext OTP out of logs and HTTP responses.
"""

from dataclasses import dataclass
from datetime import datetime, timezone
from ipaddress import ip_address
from math import ceil
from uuid import UUID

from psycopg.rows import dict_row

from core.login_otp import (
    generate_challenge_id,
    generate_login_otp,
    hash_login_otp,
    verify_login_otp,
)

OTP_LIFETIME_MINUTES = 5
OTP_MAX_WRONG_ATTEMPTS = 3
OTP_RESEND_COOLDOWN_SECONDS = 60
OTP_SENDS_PER_15_MINUTES = 4  # Initial send + at most 3 resends.


class OTPRateLimited(Exception):
    """Raised when a request would exceed the per-account send limits."""

    def __init__(self, retry_after: int):
        self.retry_after = max(1, retry_after)
        super().__init__("OTP requests are temporarily limited.")


class OTPAccountUnavailable(Exception):
    """An inactive/missing account, or a mismatched destination email."""


@dataclass(frozen=True)
class NewLoginChallenge:
    challenge_id: UUID
    # Plaintext is returned *only* for sending by a future mail service.
    # Do not persist, print, or return this code in an API response.
    code: str
    expires_at: datetime


@dataclass(frozen=True)
class OTPCheckResult:
    verified: bool
    user_id: int | None = None
    # Used only by the service caller; client-facing failures should be generic.
    status: str = "invalid"


def _trusted_ip(value: str | None) -> str | None:
    if value is None:
        return None
    # Caller MUST supply request.client.host or a proxy-validated address,
    # never an unchecked X-Forwarded-For value.
    return str(ip_address(value))


def create_login_challenge(
    connection,
    *,
    user_id: int,
    email: str,
    client_ip: str | None = None,
) -> NewLoginChallenge:
    """Create a 5-minute challenge, invalidating the old pending one.

    The users row lock serializes concurrent requests for the same account.
    This prevents bypassing resend limits with concurrent requests. No email
    is sent here. Call ``mark_login_otp_sent`` after mail delivery succeeds.
    On email failure, call ``invalidate_login_challenge``.
    """
    normalized_email = email.strip().lower()
    checked_ip = _trusted_ip(client_ip)

    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            """
            SELECT user_id, email, is_active
            FROM public.users
            WHERE user_id = %s
            FOR UPDATE;
            """,
            (user_id,),
        )
        account = cursor.fetchone()
        if (
            account is None
            or not account["is_active"]
            or account["email"].lower() != normalized_email
        ):
            raise OTPAccountUnavailable("The account cannot receive login codes.")

        cursor.execute(
            """
            SELECT COUNT(*) AS send_count,
                   MIN(sent_at) AS earliest_sent,
                   MAX(sent_at) AS latest_sent
            FROM public.login_otps
            WHERE user_id = %s
              AND purpose = 'login'
              AND sent_at >= NOW() - INTERVAL '15 minutes';
            """,
            (user_id,),
        )
        sends = cursor.fetchone()
        now = datetime.now(timezone.utc)
        latest = sends["latest_sent"]
        earliest = sends["earliest_sent"]

        if latest is not None:
            seconds_since = (now - latest).total_seconds()
            if seconds_since < OTP_RESEND_COOLDOWN_SECONDS:
                raise OTPRateLimited(ceil(OTP_RESEND_COOLDOWN_SECONDS - seconds_since))

        if sends["send_count"] >= OTP_SENDS_PER_15_MINUTES:
            # Earliest sent code must age out of the 15-minute window.
            wait = ceil(900 - (now - earliest).total_seconds())
            raise OTPRateLimited(wait)

        # UNIQUE partial index requires old pending challenges to be explicitly
        # invalidated, including expired ones that were never marked invalid.
        cursor.execute(
            """
            UPDATE public.login_otps
               SET invalidated_at = NOW()
             WHERE user_id = %s AND purpose = 'login'
               AND consumed_at IS NULL AND invalidated_at IS NULL;
            """,
            (user_id,),
        )

        challenge_id = generate_challenge_id()
        code = generate_login_otp()
        digest = hash_login_otp(
            code, user_id=user_id, challenge_id=challenge_id
        )
        cursor.execute(
            """
            INSERT INTO public.login_otps
                (challenge_id, user_id, purpose, otp_hmac_sha256,
                 sent_to_email, requested_ip, expires_at)
            VALUES (%s, %s, 'login', %s, %s, %s,
                    NOW() + (%s * INTERVAL '1 minute'))
            RETURNING expires_at;
            """,
            (challenge_id, user_id, digest, normalized_email, checked_ip, OTP_LIFETIME_MINUTES),
        )
        expires_at = cursor.fetchone()["expires_at"]

    return NewLoginChallenge(challenge_id, code, expires_at)


def mark_login_otp_sent(connection, *, challenge_id: UUID) -> bool:
    """Record an OTP sent successfully by the email service.

    A send should be marked only AFTER the provider reports success. A plain
    `SMTP accepted` result alone cannot guarantee inbox delivery.
    """
    with connection.cursor() as cursor:
        cursor.execute(
            """
            UPDATE public.login_otps
               SET sent_at = NOW()
             WHERE challenge_id = %s AND purpose = 'login'
               AND sent_at IS NULL
               AND invalidated_at IS NULL AND consumed_at IS NULL
               AND expires_at > NOW();
            """,
            (challenge_id,),
        )
        return cursor.rowcount == 1


def invalidate_login_challenge(connection, *, challenge_id: UUID) -> None:
    """Invalidate a challenge if mail could not be sent, or if canceled."""
    with connection.cursor() as cursor:
        cursor.execute(
            """
            UPDATE public.login_otps
               SET invalidated_at = NOW()
             WHERE challenge_id = %s AND purpose = 'login'
               AND consumed_at IS NULL AND invalidated_at IS NULL;
            """,
            (challenge_id,),
        )


def check_login_otp(
    connection, *, challenge_id: UUID, entered_code: str
) -> OTPCheckResult:
    """Atomically verify and consume a login OTP, or count one wrong entry.

    Three incorrect attempts invalidate the code, even if the correct code is
    entered afterward. Expired, canceled, unsent and used codes never verify.

    IMPORTANT: the future API route must commit this transaction BEFORE it
    returns the session JWT; JWT issuance is not implemented in this module.
    """
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            """
            SELECT o.user_id, o.otp_hmac_sha256, o.failed_attempts,
                   o.expires_at, o.consumed_at, o.invalidated_at,
                   o.sent_at, u.is_active
            FROM public.login_otps AS o
            JOIN public.users AS u ON u.user_id = o.user_id
            WHERE o.challenge_id = %s AND o.purpose = 'login'
            FOR UPDATE OF o;
            """,
            (challenge_id,),
        )
        challenge = cursor.fetchone()
        if challenge is None:
            return OTPCheckResult(False, status="invalid")

        if not challenge["is_active"]:
            return OTPCheckResult(False, status="invalid")

        if (
            challenge["sent_at"] is None
            or challenge["consumed_at"] is not None
            or challenge["invalidated_at"] is not None
        ):
            return OTPCheckResult(False, status="invalid")

        if challenge["expires_at"] <= datetime.now(timezone.utc):
            cursor.execute(
                """
                UPDATE public.login_otps
                   SET invalidated_at = NOW()
                 WHERE challenge_id = %s AND invalidated_at IS NULL;
                """,
                (challenge_id,),
            )
            return OTPCheckResult(False, status="expired")

        valid = verify_login_otp(
            entered_code,
            user_id=challenge["user_id"],
            challenge_id=challenge_id,
            stored_hash=challenge["otp_hmac_sha256"],
        )
        if valid:
            cursor.execute(
                """
                UPDATE public.login_otps SET consumed_at = NOW()
                WHERE challenge_id = %s;
                """,
                (challenge_id,),
            )
            return OTPCheckResult(
                True, user_id=challenge["user_id"], status="verified"
            )

        next_attempts = challenge["failed_attempts"] + 1
        cursor.execute(
            """
            UPDATE public.login_otps
               SET failed_attempts = %s,
                   invalidated_at = CASE WHEN %s >= %s
                                         THEN NOW() ELSE NULL END
             WHERE challenge_id = %s;
            """,
            (next_attempts, next_attempts, OTP_MAX_WRONG_ATTEMPTS, challenge_id),
        )
        return OTPCheckResult(False, status="invalid")
