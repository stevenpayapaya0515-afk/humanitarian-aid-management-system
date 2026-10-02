from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jwt.exceptions import InvalidTokenError
from psycopg.rows import dict_row

from core.security import decode_access_token
from database import get_connection


bearer = HTTPBearer(auto_error=False)


# Check the token and retrieve the current account
def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
):
    login_error = HTTPException(
        status_code=401,
        detail="Please log in again.",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if credentials is None:
        raise login_error

    try:
        payload = decode_access_token(credentials.credentials)
        user_id = int(payload["sub"])

        if user_id < 1 or user_id > 2147483647:
            raise login_error

    except (InvalidTokenError, ValueError, TypeError, KeyError):
        raise login_error

    # Check that the account still exists and is active
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT user_id, full_name, email, role, is_active
                FROM public.users
                WHERE user_id = %s;
                """,
                (user_id,),
            )
            user = cursor.fetchone()

    if user is None or not user["is_active"]:
        raise login_error

    return user

# Allow only active Admin accounts
def require_admin(current_user: dict = Depends(get_current_user)):
    if current_user["role"] != "Admin":
        raise HTTPException(
            status_code=403,
            detail="Only administrators can access this feature.",
        )

    return current_user