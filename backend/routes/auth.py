import logging
from contextlib import contextmanager
import psycopg
from services.network_deadline import call_with_deadline, ProviderTimeout, ProviderBusy
from services.gmail_login_email import GmailConfigError, GmailDeliveryError
logger = logging.getLogger("uvicorn.error")

from datetime import datetime, timedelta, timezone
from math import ceil

from fastapi import APIRouter, Depends, HTTPException, Request
from schemas.auth import LoginChallengeResponse, VerifyLoginRequest
from services.recaptcha import verify_recaptcha
from services.login_otp_store import (create_login_challenge, mark_login_otp_sent,
    invalidate_login_challenge, check_login_otp, OTPRateLimited, OTPAccountUnavailable)
from services.gmail_login_email import send_login_otp_email
from psycopg.rows import dict_row

from core.dependencies import get_current_user
from core.security import (
    create_access_token,
    hash_password,
    verify_password,
    password_error,
)
from database import get_connection
from schemas.auth import (
    LoginRequest,
    LoginResponse,
    UserResponse,
    ChangePasswordRequest,
)


@contextmanager
def auth_connection():
    try:
        with get_connection() as connection:
            connection.execute("SET LOCAL lock_timeout = '2s'")
            connection.execute("SET LOCAL statement_timeout = '5s'")
            yield connection
    except psycopg.Error as error:
        logger.warning("LOGIN database unavailable: %s", type(error).__name__)
        raise HTTPException(503, "Login database is busy or unavailable. Please try again shortly.") from None


router = APIRouter(prefix="/auth", tags=["Authentication"])

# Login protection settings
MAX_FAILED_ATTEMPTS = 5
# Lock login for 1 minute after 5 failed attempts.
LOCKOUT_MINUTES = 1

# Used when an email does not exist.
DUMMY_HASH = hash_password("unused-dummy-password")


@router.post("/login", response_model=LoginChallengeResponse)
def login(data: LoginRequest, request: Request):
    logger.info("LOGIN started: checking CAPTCHA")
    verify_recaptcha(data.recaptcha_token)
    logger.info("LOGIN checking password/database")
    # Normalize the email, but preserve the password exactly.
    email = data.email.strip().lower()

    authenticated_user = None
    retry_after = None

    with auth_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            # FOR UPDATE prevents simultaneous login requests
            # from overwriting this account's failed-attempt counter.
            cursor.execute(
                """
                SELECT user_id, full_name, email,
                       password_hash, role, is_active,
                       failed_login_attempts, locked_until, auth_version
                FROM public.users
                WHERE email = %s
                FOR UPDATE;
                """,
                (email,),
            )
            user = cursor.fetchone()

            # Read the time after obtaining the account row lock.
            now = datetime.now(timezone.utc)

            if user is None:
                # Still perform password verification for unknown emails.
                verify_password(data.password, DUMMY_HASH)

            elif not user["is_active"]:
                # Deactivated accounts cannot log in.
                verify_password(data.password, user["password_hash"])

            elif (
                user["locked_until"] is not None
                and user["locked_until"] > now
            ):
                # Reject login during the cooldown.
                # Additional requests do not extend the lock.
                retry_after = max(
                    1,
                    ceil(
                        (user["locked_until"] - now).total_seconds()
                    ),
                )

            else:
                # Start a fresh counter after an expired cooldown.
                failed_attempts = user["failed_login_attempts"]

                if user["locked_until"] is not None:
                    failed_attempts = 0

                password_valid = verify_password(
                    data.password,
                    user["password_hash"],
                )

                if password_valid:
                    # Successful login clears previous failures.
                    cursor.execute(
                        """
                        UPDATE public.users
                        SET failed_login_attempts = 0,
                            locked_until = NULL
                        WHERE user_id = %s;
                        """,
                        (user["user_id"],),
                    )
                    authenticated_user = user

                else:
                    # Record the failed password attempt.
                    failed_attempts += 1
                    locked_until = None

                    if failed_attempts >= MAX_FAILED_ATTEMPTS:
                        locked_until = (
                            datetime.now(timezone.utc)
                            + timedelta(minutes=LOCKOUT_MINUTES)
                        )
                        retry_after = LOCKOUT_MINUTES * 60

                    cursor.execute(
                        """
                        UPDATE public.users
                        SET failed_login_attempts = %s,
                            locked_until = %s
                        WHERE user_id = %s;
                        """,
                        (
                            failed_attempts,
                            locked_until,
                            user["user_id"],
                        ),
                    )

    # Raise login errors AFTER leaving the connection block.
    # This allows the counter and lock changes to be committed.
    if retry_after is not None:
        raise HTTPException(
            status_code=429,
            detail=(
                "Too many failed login attempts. "
                f"Try again in {retry_after} seconds."
            ),
            headers={"Retry-After": str(retry_after)},
        )

    if authenticated_user is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid email or password.",
        )

    # Reserve and COMMIT the challenge/cooldown before any Gmail network call.
    try:
        with auth_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute("SELECT * FROM public.users WHERE user_id = %s FOR UPDATE",
                               (authenticated_user["user_id"],))
                account = cursor.fetchone()
                if (not account or not account["is_active"] or
                    account["password_hash"] != authenticated_user["password_hash"] or
                    account["email"] != authenticated_user["email"]):
                    raise HTTPException(401, "Please sign in again.")
            challenge = create_login_challenge(
                connection, user_id=account["user_id"], email=account["email"],
                client_ip=request.client.host if request.client else None)
    except OTPRateLimited as error:
        raise HTTPException(429, "Please wait before requesting another email code.",
                            headers={"Retry-After": str(error.retry_after)}) from None
    except OTPAccountUnavailable:
        raise HTTPException(401, "Please sign in again.") from None

    logger.info("LOGIN password passed; sending OTP email (20-second wait limit)")
    failure = None
    try:
        call_with_deadline("email", 20, lambda: send_login_otp_email(
            to_email=account["email"], code=challenge.code, expires_at=challenge.expires_at))
    except Exception as error:
        logger.warning("LOGIN email failed: %s", type(error).__name__)
        if isinstance(error, (ProviderTimeout, ProviderBusy)):
            failure = "Email service is slow or busy. Wait 60 seconds, then sign in again."
        elif isinstance(error, GmailConfigError):
            failure = "Login email sender is not configured or authorized. Contact your administrator."
        else:
            failure = "Could not send the login email. Please try again later."

    with auth_connection() as connection:
        # Same lock order as verification/password changes; recheck after delivery.
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute("SELECT * FROM public.users WHERE user_id = %s FOR UPDATE",
                           (account["user_id"],))
            current = cursor.fetchone()
        if (not current or not current["is_active"] or
            current["auth_version"] != account["auth_version"] or
            current["password_hash"] != account["password_hash"] or
            current["email"] != account["email"]):
            failure = "Account changed during login. Please sign in again."
        if failure is None and not mark_login_otp_sent(connection, challenge_id=challenge.challenge_id):
            failure = "Login code is no longer valid. Please sign in again."
        if failure is not None:
            invalidate_login_challenge(connection, challenge_id=challenge.challenge_id)
    if failure is not None:
        raise HTTPException(503, failure)
    logger.info("LOGIN email accepted; OTP challenge ready")
    return LoginChallengeResponse(challenge_id=challenge.challenge_id,
                                  expires_at=challenge.expires_at)


@router.post("/verify-otp", response_model=LoginResponse)
def verify_otp(data: VerifyLoginRequest):
    account = None
    with auth_connection() as connection:
        # Always lock user before OTP, matching creation and password changes.
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute("""SELECT u.user_id, u.full_name, u.email, u.role,
                u.is_active, u.auth_version FROM public.users u
                JOIN public.login_otps o ON o.user_id = u.user_id
                WHERE o.challenge_id = %s FOR UPDATE OF u""", (data.challenge_id,))
            account = cursor.fetchone()
        result = check_login_otp(connection, challenge_id=data.challenge_id,
                                 entered_code=data.code)
    # Wrong-attempt counters and single-use consumption commit BEFORE response.
    if not result.verified or not account or not account["is_active"]:
        raise HTTPException(401, "Invalid or expired code. After three wrong attempts, sign in again.")
    return LoginResponse(
        access_token=create_access_token(account["user_id"], auth_version=account["auth_version"]),
        user=UserResponse(**account))


# Only users with a valid token can access this endpoint.
@router.get("/me", response_model=UserResponse)
def get_my_account(
    current_user: dict = Depends(get_current_user),
):
    return current_user


# Change only the password of the currently logged-in account.
@router.post("/change-password")
def change_password(
    data: ChangePasswordRequest,
    current_user: dict = Depends(get_current_user),
):
    retry_after = None
    password_changed = False
    error_message = "Current password is incorrect."

    with auth_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            # Lock the account row while checking and updating it.
            cursor.execute(
                """
                SELECT user_id, full_name, email, password_hash, is_active,
                       failed_login_attempts, locked_until, auth_version
                FROM public.users
                WHERE user_id = %s
                FOR UPDATE;
                """,
                (current_user["user_id"],),
            )
            user = cursor.fetchone()

            if user is None or not user["is_active"]:
                raise HTTPException(
                    status_code=401,
                    detail="Please log in again.",
                )

            now = datetime.now(timezone.utc)

            # Share the existing login cooldown.
            if (
                user["locked_until"] is not None
                and user["locked_until"] > now
            ):
                retry_after = max(
                    1,
                    ceil((user["locked_until"] - now).total_seconds()),
                )

            else:
                # Start fresh after an expired cooldown.
                failed_attempts = user["failed_login_attempts"]

                if user["locked_until"] is not None:
                    failed_attempts = 0

                password_valid = verify_password(
                    data.current_password,
                    user["password_hash"],
                )

                if not password_valid:
                    failed_attempts += 1
                    locked_until = None

                    if failed_attempts >= MAX_FAILED_ATTEMPTS:
                        locked_until = now + timedelta(
                            minutes=LOCKOUT_MINUTES
                        )
                        retry_after = LOCKOUT_MINUTES * 60

                    cursor.execute(
                        """
                        UPDATE public.users
                        SET failed_login_attempts = %s,
                            locked_until = %s
                        WHERE user_id = %s;
                        """,
                        (
                            failed_attempts,
                            locked_until,
                            user["user_id"],
                        ),
                    )

                else:
                    # A valid current password clears previous failures.
                    cursor.execute(
                        """
                        UPDATE public.users
                        SET failed_login_attempts = 0,
                            locked_until = NULL
                        WHERE user_id = %s;
                        """,
                        (user["user_id"],),
                    )
                    
                    new_password_error = password_error(
                        data.new_password,
                        user["full_name"],
                        user["email"],
                    )

                    if data.new_password == data.current_password:
                        error_message = (
                            "Choose a different password from your current one."
                        )

                    elif new_password_error is not None:
                         error_message = new_password_error

                    else:
                        # Store a hash, never the actual password.
                        cursor.execute(
                            """
                            UPDATE public.users
                            SET password_hash = %s, auth_version = auth_version + 1
                            WHERE user_id = %s;
                            """,
                            (
                                hash_password(data.new_password),
                                user["user_id"],
                            ),
                        )
                        cursor.execute("""UPDATE public.login_otps SET invalidated_at = NOW()
                            WHERE user_id = %s AND consumed_at IS NULL
                            AND invalidated_at IS NULL""", (user["user_id"],))
                        password_changed = True

    # Raise errors after the transaction commits the attempt counter.
    if retry_after is not None:
        raise HTTPException(
            status_code=429,
            detail="Too many failed attempts. Please wait before trying again.",
            headers={"Retry-After": str(retry_after)},
        )

    if not password_changed:
        raise HTTPException(
            status_code=400,
            detail=error_message,
        )

    return {
        "message": "Password changed successfully. Please log in again."
    }