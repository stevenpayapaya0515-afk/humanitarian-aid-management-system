from datetime import datetime, timedelta, timezone
from math import ceil

from fastapi import APIRouter, Depends, HTTPException
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


router = APIRouter(prefix="/auth", tags=["Authentication"])

# Login protection settings
MAX_FAILED_ATTEMPTS = 5
# Lock login for 1 minute after 5 failed attempts.
LOCKOUT_MINUTES = 1

# Used when an email does not exist.
DUMMY_HASH = hash_password("unused-dummy-password")


@router.post("/login", response_model=LoginResponse)
def login(data: LoginRequest):
    # Normalize the email, but preserve the password exactly.
    email = data.email.strip().lower()

    authenticated_user = None
    retry_after = None

    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            # FOR UPDATE prevents simultaneous login requests
            # from overwriting this account's failed-attempt counter.
            cursor.execute(
                """
                SELECT user_id, full_name, email,
                       password_hash, role, is_active,
                       failed_login_attempts, locked_until
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

    # Return a token and safe account details.
    return LoginResponse(
        access_token=create_access_token(
            authenticated_user["user_id"]
        ),
        user=UserResponse(
            user_id=authenticated_user["user_id"],
            full_name=authenticated_user["full_name"],
            email=authenticated_user["email"],
            role=authenticated_user["role"],
        ),
    )


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

    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            # Lock the account row while checking and updating it.
            cursor.execute(
                """
                SELECT user_id, full_name, email, password_hash, is_active,
                       failed_login_attempts, locked_until
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
                            SET password_hash = %s
                            WHERE user_id = %s;
                            """,
                            (
                                hash_password(data.new_password),
                                user["user_id"],
                            ),
                        )
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