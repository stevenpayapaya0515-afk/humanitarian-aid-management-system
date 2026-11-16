from fastapi import APIRouter, Depends, HTTPException
from psycopg.errors import ForeignKeyViolation
from psycopg.rows import dict_row

from core.dependencies import get_current_user
from database import get_connection
from schemas.households import (
    HouseholdCreate,
    HouseholdResponse,
    format_household_address,
    registration_matches_size,
)


router = APIRouter(prefix="/households", tags=["Household Registration"])


def require_household_access(current_user: dict = Depends(get_current_user)):
    if current_user["role"] not in ("Admin", "Staff"):
        raise HTTPException(status_code=403, detail="Access to households is denied.")
    return current_user


def require_household_write(current_user: dict = Depends(get_current_user)):
    if current_user["role"] != "Staff":
        raise HTTPException(
            status_code=403,
            detail="Only Staff can change household records.",
        )
    return current_user


def prepare_household(household: dict) -> dict:
    household["members_complete"] = registration_matches_size(
        household["household_size"], household["household_member"]
    )
    household["full_address"] = format_household_address(
        household["province"],
        household["city_municipality"],
        household["barangay"],
        household["purok"],
    )
    return household


@router.get("", response_model=list[HouseholdResponse])
def list_households(current_user: dict = Depends(require_household_access)):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT household_id, household_head, province, city_municipality,
                       barangay, purok, household_size, household_member,
                       registered_by, created_at, updated_at
                FROM public.households
                ORDER BY household_id DESC;
                """
            )
            households = cursor.fetchall()
    return [prepare_household(row) for row in households]


@router.post("", response_model=HouseholdResponse, status_code=201)
def create_household(
    data: HouseholdCreate,
    current_user: dict = Depends(require_household_write),
):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                INSERT INTO public.households (
                    household_head, province, city_municipality, barangay, purok,
                    household_size, household_member, registered_by
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING household_id, household_head, province, city_municipality,
                          barangay, purok, household_size, household_member,
                          registered_by, created_at, updated_at;
                """,
                (
                    data.household_head, data.province, data.city_municipality,
                    data.barangay, data.purok, data.household_size,
                    data.household_member, current_user["user_id"],
                ),
            )
            household = cursor.fetchone()
    return prepare_household(household)


@router.patch("/{household_id}", response_model=HouseholdResponse)
def update_household(
    household_id: int,
    data: HouseholdCreate,
    current_user: dict = Depends(require_household_write),
):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            # Household-size changes would invalidate saved assessment totals.
            cursor.execute(
                "SELECT household_size FROM public.households "
                "WHERE household_id = %s FOR UPDATE;",
                (household_id,),
            )
            existing = cursor.fetchone()
            if existing is None:
                raise HTTPException(status_code=404, detail="Household not found.")
            if existing["household_size"] != data.household_size:
                cursor.execute(
                    "SELECT EXISTS (SELECT 1 FROM public.household_assessments "
                    "WHERE household_id = %s) AS has_assessment;",
                    (household_id,),
                )
                if cursor.fetchone()["has_assessment"]:
                    raise HTTPException(
                        status_code=409,
                        detail=(
                            "Household size cannot be changed after an assessment "
                            "has been saved. Review the assessment history first."
                        ),
                    )
            cursor.execute(
                """
                UPDATE public.households
                SET household_head = %s, province = %s, city_municipality = %s,
                    barangay = %s, purok = %s, household_size = %s,
                    household_member = %s, updated_at = NOW()
                WHERE household_id = %s
                RETURNING household_id, household_head, province, city_municipality,
                          barangay, purok, household_size, household_member,
                          registered_by, created_at, updated_at;
                """,
                (
                    data.household_head, data.province, data.city_municipality,
                    data.barangay, data.purok, data.household_size,
                    data.household_member, household_id,
                ),
            )
            household = cursor.fetchone()
            if household is None:
                raise HTTPException(status_code=404, detail="Household not found.")
    return prepare_household(household)


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
