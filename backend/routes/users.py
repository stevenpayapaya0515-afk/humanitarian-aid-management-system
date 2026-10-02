from fastapi import APIRouter, Depends, HTTPException
from psycopg.errors import UniqueViolation, ForeignKeyViolation
from psycopg.rows import dict_row
from core.security import password_error

from core.dependencies import require_admin
from core.security import hash_password
from database import get_connection
from schemas.users import StaffCreate, UserListResponse, UserStatusUpdate



# All routes here require an active Admin account
router = APIRouter(
    prefix="/users",
    tags=["User Management"],
    dependencies=[Depends(require_admin)],
)

# Permanently delete a Staff account.
# The router already requires Admin access.
@router.delete("/{user_id}")
def delete_staff(user_id: int):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                # Lock the account row while checking and deleting it.
                cursor.execute(
                    """
                    SELECT user_id, role
                    FROM public.users
                    WHERE user_id = %s
                    FOR UPDATE;
                    """,
                    (user_id,),
                )
                user = cursor.fetchone()

                if user is None:
                    raise HTTPException(
                        status_code=404,
                        detail="Account not found.",
                    )

                # Protect Admin accounts.
                if user["role"] != "Staff":
                    raise HTTPException(
                        status_code=403,
                        detail="Only Staff accounts can be deleted.",
                    )

                cursor.execute(
                    """
                    DELETE FROM public.users
                    WHERE user_id = %s AND role = 'Staff';
                    """,
                    (user_id,),
                )

    except ForeignKeyViolation:
        # Keep accounts that are referenced by protected records.
        raise HTTPException(
            status_code=409,
            detail=(
                "This account has linked records. "
                "Deactivate it instead."
            ),
        )

    return {"message": "Staff account deleted successfully."}

# Activate or deactivate a Staff account.
# This router already requires Admin access.
@router.patch("/{user_id}/status", response_model=UserListResponse)
def update_staff_status(user_id: int, data: UserStatusUpdate):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            # Find the account first.
            cursor.execute(
                """
                SELECT user_id, role
                FROM public.users
                WHERE user_id = %s;
                """,
                (user_id,),
            )
            user = cursor.fetchone()

            if user is None:
                raise HTTPException(
                    status_code=404,
                    detail="Account not found.",
                )

            # Admin accounts cannot be changed through this feature.
            if user["role"] != "Staff":
                raise HTTPException(
                    status_code=403,
                    detail="Only Staff accounts can be activated or deactivated.",
                )

            # Update the status and return safe account details.
            cursor.execute(
                """
                UPDATE public.users
                SET is_active = %s
                WHERE user_id = %s AND role = 'Staff'
                RETURNING user_id, full_name, email, role,
                          is_active, created_at;
                """,
                (data.is_active, user_id),
            )
            updated_user = cursor.fetchone()

            if updated_user is None:
                raise HTTPException(
                    status_code=409,
                    detail="Account changed. Refresh and try again.",
                )

    return updated_user


# List accounts without exposing password hashes
@router.get("", response_model=list[UserListResponse])
def list_users():
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT user_id, full_name, email, role,
                       is_active, created_at
                FROM public.users
                ORDER BY user_id;
                """
            )
            users = cursor.fetchall()

    return users


# Create a Staff account
@router.post("", response_model=UserListResponse, status_code=201)
def create_staff(data: StaffCreate):
    error = password_error(
        data.password,
        data.full_name,
        data.email,
    )

    if error is not None:
        raise HTTPException(status_code=400, detail=error)

    hashed_password = hash_password(data.password)

    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    """
                    INSERT INTO public.users
                        (full_name, email, password_hash, role)
                    VALUES (%s, %s, %s, %s)
                    RETURNING user_id, full_name, email, role,
                              is_active, created_at;
                    """,
                    (
                        data.full_name,
                        data.email,
                        hashed_password,
                        "Staff",
                    ),
                )
                new_user = cursor.fetchone()

    except UniqueViolation:
        raise HTTPException(
            status_code=409,
            detail="Email already exists.",
        )

    return new_user