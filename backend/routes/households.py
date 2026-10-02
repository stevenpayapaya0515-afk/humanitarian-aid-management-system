from fastapi import APIRouter, Depends, HTTPException
from psycopg.errors import ForeignKeyViolation
from psycopg.rows import dict_row

from core.dependencies import get_current_user
from database import get_connection
from schemas.households import HouseholdCreate, HouseholdResponse


router = APIRouter(prefix="/households", tags=["Household Registration"])


# Define this BEFORE the endpoints that use it.
def require_household_access(current_user: dict = Depends(get_current_user)):
    if current_user["role"] not in ("Admin", "Staff"):
        raise HTTPException(status_code=403, detail="Access to households is denied.")
    return current_user


# Only Staff can register, update, or delete household records.
# get_current_user verifies the login token and active account.
def require_household_write(current_user: dict = Depends(get_current_user)):
    if current_user["role"] != "Staff":
        raise HTTPException(
            status_code=403,
            detail="Only Staff can change household records.",
        )
    return current_user

def prepare_household(household: dict) -> dict:
    # Inform Flutter when an older record does not yet have all names.
    names = [
        name.strip()
        for name in household["household_member"].splitlines()
        if name.strip()
    ]
    household["members_complete"] = len(names) + 1 == household["household_size"]
    return household


# Read all records from the households table only.
@router.get("", response_model=list[HouseholdResponse])
def list_households(current_user: dict = Depends(require_household_access)):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT household_id, household_head, barangay, purok,
                       address, household_size, household_member,
                       registered_by, created_at, updated_at
                FROM public.households
                ORDER BY household_id DESC;
                """
            )
            households = cursor.fetchall()
    return [prepare_household(row) for row in households]


# Register the household and member-name text in the same row.
@router.post("", response_model=HouseholdResponse, status_code=201)
def create_household(
    data: HouseholdCreate,
    current_user: dict = Depends(require_household_access),
):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                INSERT INTO public.households (
                    household_head, barangay, purok, address,
                    household_size, household_member, registered_by
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING household_id, household_head, barangay, purok,
                          address, household_size, household_member,
                          registered_by, created_at, updated_at;
                """,
                (
                    data.household_head, data.barangay, data.purok,
                    data.address, data.household_size,
                    data.household_member, current_user["user_id"],
                ),
            )
            household = cursor.fetchone()
    return prepare_household(household)


# Update the selected row without changing its creator or creation date.
@router.patch("/{household_id}", response_model=HouseholdResponse)
def update_household(
    household_id: int,
    data: HouseholdCreate,
    current_user: dict = Depends(require_household_write),
):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                UPDATE public.households
                SET household_head = %s, barangay = %s, purok = %s,
                    address = %s, household_size = %s,
                    household_member = %s, updated_at = NOW()
                WHERE household_id = %s
                RETURNING household_id, household_head, barangay, purok,
                          address, household_size, household_member,
                          registered_by, created_at, updated_at;
                """,
                (
                    data.household_head, data.barangay, data.purok,
                    data.address, data.household_size,
                    data.household_member, household_id,
                ),
            )
            household = cursor.fetchone()
            if household is None:
                raise HTTPException(status_code=404, detail="Household not found.")
    return prepare_household(household)


# Delete a household unless another module references it through a foreign key.
@router.delete("/{household_id}")
def delete_household(
    household_id: int,
    current_user: dict = Depends(require_household_write),
):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    "DELETE FROM public.households WHERE household_id = %s "
                    "RETURNING household_id;",
                    (household_id,),
                )
                if cursor.fetchone() is None:
                    raise HTTPException(status_code=404, detail="Household not found.")
    except ForeignKeyViolation:
        raise HTTPException(
            status_code=409,
            detail="This household has linked records and cannot be deleted.",
        )
    return {"message": "Household deleted successfully."}
