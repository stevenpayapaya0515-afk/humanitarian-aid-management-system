"""Assessment registration and history. No ML predictions are made here."""

from fastapi import APIRouter, Depends, HTTPException, Query
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row

from core.dependencies import get_current_user
from database import get_connection
from schemas.assessments import AssessmentCreate, AssessmentResponse

router = APIRouter(prefix="/assessments", tags=["Household Assessment"])


# Admin and Staff may review assessment history; only Staff may add assessments.
def require_assessment_read(current_user: dict = Depends(get_current_user)):
    if current_user["role"] not in ("Admin", "Staff"):
        raise HTTPException(status_code=403, detail="Assessment access denied.")
    return current_user


def require_assessment_write(current_user: dict = Depends(get_current_user)):
    if current_user["role"] != "Staff":
        raise HTTPException(status_code=403, detail="Only Staff may create assessments.")
    return current_user


ASSESSMENT_SELECT = """
    SELECT a.assessment_id, a.household_id, a.assessment_date,
           a.age_0_5_count, a.age_6_17_count,
           a.age_18_59_count, a.age_60_plus_count,
           a.senior_citizens_count, a.pwd_count,
           a.monthly_income_range, a.employment_status,
           a.livelihood_type, a.previous_humanitarian_assistance,
           a.beneficiary_status, a.disaster_affected,
           a.housing_damage_level, a.displaced, a.data_origin,
           a.roof_material, a.wall_material, a.electricity, a.drinking_water_source, a.toilet_facility, a.working_adult_present, a.apis_single_family,
           a.financial_reference_year, a.financial_single_family, a.average_family_size, a.annual_family_income, a.annual_family_expenditure, a.annual_food_expenditure,
           a.recorded_by, a.created_at,
           h.household_head, h.barangay
    FROM public.household_assessments a
    JOIN public.households h ON h.household_id = a.household_id
"""


@router.get("", response_model=list[AssessmentResponse])
def list_assessments(
    household_id: int | None = Query(default=None, ge=1),
    current_user: dict = Depends(require_assessment_read),
):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            if household_id is None:
                cursor.execute(ASSESSMENT_SELECT + " ORDER BY a.assessment_id DESC;")
            else:
                cursor.execute(
                    ASSESSMENT_SELECT +
                    " WHERE a.household_id = %s ORDER BY a.assessment_id DESC;",
                    (household_id,),
                )
            return cursor.fetchall()


@router.post("", response_model=AssessmentResponse, status_code=201)
def create_assessment(
    data: AssessmentCreate,
    current_user: dict = Depends(require_assessment_write),
):
    # Check the registration record before inserting its related assessment.
    # The row lock avoids racing with an edit to household_size in this transaction.
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    "SELECT household_size FROM public.households "
                    "WHERE household_id = %s FOR SHARE;",
                    (data.household_id,),
                )
                household = cursor.fetchone()
                if household is None:
                    raise HTTPException(status_code=404, detail="Household not found.")

                age_total = (
                    data.age_0_5_count + data.age_6_17_count
                    + data.age_18_59_count + data.age_60_plus_count
                )
                if household["household_size"] != age_total:
                    raise HTTPException(
                        status_code=422,
                        detail="Age group totals must match registered household size.",
                    )

                cursor.execute(
                    """
                    INSERT INTO public.household_assessments (
                        household_id, assessment_date,
                        age_0_5_count, age_6_17_count,
                        age_18_59_count, age_60_plus_count,
                        senior_citizens_count, pwd_count,
                        monthly_income_range, employment_status, livelihood_type,
                        previous_humanitarian_assistance, beneficiary_status,
                        disaster_affected, housing_damage_level, displaced,
                        roof_material, wall_material, electricity, drinking_water_source, toilet_facility, working_adult_present, apis_single_family,
                        financial_reference_year, financial_single_family, average_family_size, annual_family_income, annual_family_expenditure, annual_food_expenditure,
                        data_origin, recorded_by
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s, %s, %s, %s,
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                        , %s, %s, %s, %s, %s, %s
                    ) RETURNING assessment_id;
                    """,
                    (
                        data.household_id, data.assessment_date,
                        data.age_0_5_count, data.age_6_17_count,
                        data.age_18_59_count, data.age_60_plus_count,
                        data.senior_citizens_count, data.pwd_count,
                        data.monthly_income_range, data.employment_status,
                        data.livelihood_type, data.previous_humanitarian_assistance,
                        data.beneficiary_status, data.disaster_affected,
                        data.housing_damage_level, data.displaced,
                        data.roof_material, data.wall_material, data.electricity, data.drinking_water_source, data.toilet_facility, data.working_adult_present, data.apis_single_family,
                        data.financial_reference_year, data.financial_single_family, data.average_family_size, data.annual_family_income, data.annual_family_expenditure, data.annual_food_expenditure,
                        data.data_origin, current_user["user_id"],
                    ),
                )
                assessment_id = cursor.fetchone()["assessment_id"]
                cursor.execute(
                    ASSESSMENT_SELECT + " WHERE a.assessment_id = %s;",
                    (assessment_id,),
                )
                result = cursor.fetchone()
    except UniqueViolation:
        raise HTTPException(
            status_code=409,
            detail="This household already has an assessment on that date.",
        )

    return result
