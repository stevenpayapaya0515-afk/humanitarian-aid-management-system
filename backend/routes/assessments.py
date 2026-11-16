"""Assessment registration and history. No ML predictions are made here."""

from fastapi import APIRouter, Depends, HTTPException, Path, Query
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from core.dependencies import get_current_user
from database import get_connection
from schemas.assessments import (AssessmentCreate, AssessmentResponse,
                                 APIS2022_CATALOG, APIS2022_ASSESSMENT_KEYS,
                                 APIS2022_SOCIAL_KEYS)
from schemas.households import registration_matches_size
from schemas.vulnerability import APIS2022SocialInputs

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
           a.beneficiary_status, a.disaster_affected, a.displaced, a.data_origin,
           a.roof_material, a.wall_material, a.electricity, a.drinking_water_source, a.toilet_facility, a.working_adult_present, a.apis_single_family,
           a.apis2022_i2, a.apis2022_i3, a.apis2022_i4, a.apis2022_i8, a.apis2022_ws1, a.apis2022_ws11a, a.apis2022_g15_kit, a.apis2022_g16_nat_disas, a.apis2022_g16a_evac, a.apis2022_g16b_recov, a.apis2022_mem_age_6_11, a.apis2022_mem_age_12_17, a.apis2022_monthly_household_income_php,
           a.apis2022_extended_answers, a.apis2022_social_answers, a.apis2022_program_selections,
           a.recorded_by, a.created_at,
           EXISTS (SELECT 1 FROM public.vulnerability_classifications vc
                   WHERE vc.assessment_id = a.assessment_id) AS has_classification,
           h.household_head, h.barangay
    FROM public.household_assessments a
    JOIN public.households h ON h.household_id = a.household_id
"""


@router.get("/apis2022/feature-catalog")
def apis2022_feature_catalog(current_user: dict = Depends(require_assessment_read)):
    """Exact additional survey fields, grouped by existing AidTrack screens."""
    return {
        "assessment": [APIS2022_CATALOG[name] for name in APIS2022_CATALOG
                       if name in APIS2022_ASSESSMENT_KEYS],
        "social": [APIS2022_CATALOG[name] for name in APIS2022_CATALOG
                   if name in APIS2022_SOCIAL_KEYS],
    }


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
                    "SELECT household_size, household_member FROM public.households "
                    "WHERE household_id = %s FOR SHARE;",
                    (data.household_id,),
                )
                household = cursor.fetchone()
                if household is None:
                    raise HTTPException(status_code=404, detail="Household not found.")
                if not registration_matches_size(
                    household["household_size"], household["household_member"]
                ):
                    raise HTTPException(
                        status_code=422,
                        detail="Complete the household member list in Registration before assessing.",
                    )

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
                        household_id, assessment_date, age_0_5_count, age_6_17_count, age_18_59_count,
                        age_60_plus_count, senior_citizens_count, pwd_count, beneficiary_status, disaster_affected,
                        displaced, roof_material, wall_material, electricity, drinking_water_source,
                        toilet_facility, working_adult_present, apis_single_family, apis2022_i2, apis2022_i3,
                        apis2022_i4, apis2022_i8, apis2022_ws1, apis2022_ws11a, apis2022_g15_kit,
                        apis2022_g16_nat_disas, apis2022_g16a_evac, apis2022_g16b_recov, apis2022_mem_age_6_11, apis2022_mem_age_12_17,
                        apis2022_monthly_household_income_php, apis2022_extended_answers, apis2022_social_answers, apis2022_program_selections, data_origin,
                        recorded_by
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                        %s, %s, %s, %s, %s, %s
                    ) RETURNING assessment_id;
                    """,
                    (
                        data.household_id, data.assessment_date, data.age_0_5_count,
                        data.age_6_17_count, data.age_18_59_count, data.age_60_plus_count,
                        data.senior_citizens_count, data.pwd_count, data.beneficiary_status,
                        data.disaster_affected, data.displaced, data.roof_material,
                        data.wall_material, data.electricity, data.drinking_water_source,
                        data.toilet_facility, data.working_adult_present, data.apis_single_family,
                        data.apis2022_i2, data.apis2022_i3, data.apis2022_i4,
                        data.apis2022_i8, data.apis2022_ws1, data.apis2022_ws11a,
                        data.apis2022_g15_kit, data.apis2022_g16_nat_disas, data.apis2022_g16a_evac,
                        data.apis2022_g16b_recov, data.apis2022_mem_age_6_11, data.apis2022_mem_age_12_17,
                        data.apis2022_monthly_household_income_php, Jsonb(data.apis2022_extended_answers), Jsonb(data.apis2022_social_answers),
                        Jsonb(data.apis2022_program_selections), data.data_origin, current_user["user_id"]
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


# The editing form and prediction pipeline both lock the household row first.
# This prevents a prediction from racing with an assessment update.
@router.put("/{assessment_id}", response_model=AssessmentResponse)
def update_assessment(
    data: AssessmentCreate,
    assessment_id: int = Path(ge=1),
    current_user: dict = Depends(require_assessment_write),
):
    """Edit the current household questionnaire before classification.

    Preserve legacy-only fields not collected in the current APIS 2022 form,
    and never overwrite the evidence used by an existing classification.
    """
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                # Same household lock/order used by the prediction endpoint.
                cursor.execute(
                    """SELECT a.household_id, h.household_size, h.household_member
                       FROM public.household_assessments a
                       JOIN public.households h ON h.household_id = a.household_id
                       WHERE a.assessment_id = %s FOR UPDATE OF h;""",
                    (assessment_id,),
                )
                existing = cursor.fetchone()
                if existing is None:
                    raise HTTPException(status_code=404, detail="Assessment not found.")
                if existing["household_id"] != data.household_id:
                    raise HTTPException(
                        status_code=422,
                        detail="Cannot change the registered household of an assessment.",
                    )
                if not registration_matches_size(
                    existing["household_size"], existing["household_member"]
                ):
                    raise HTTPException(
                        status_code=422,
                        detail="Complete the member list in Registration before editing.",
                    )
                age_total = (
                    data.age_0_5_count + data.age_6_17_count
                    + data.age_18_59_count + data.age_60_plus_count
                )
                if age_total != existing["household_size"]:
                    raise HTTPException(
                        status_code=422,
                        detail="Age group totals must match registered household size.",
                    )
                # Only update fields supported by the live Assessment form.
                # Never clear historical finance, demographic or other context.
                current_fields = (
                    "assessment_date", "age_0_5_count", "age_6_17_count",
                    "age_18_59_count", "age_60_plus_count", "senior_citizens_count",
                    "data_origin", "apis_single_family", "apis2022_i2", "apis2022_i3",
                    "apis2022_i4", "apis2022_i8", "apis2022_ws1", "apis2022_ws11a",
                    "apis2022_g15_kit", "apis2022_g16_nat_disas",
                    "apis2022_g16a_evac", "apis2022_g16b_recov",
                    "apis2022_mem_age_6_11", "apis2022_mem_age_12_17",
                    "apis2022_monthly_household_income_php",
                    "apis2022_extended_answers", "apis2022_social_answers",
                    "apis2022_program_selections",
                )
                values = []
                for field in current_fields:
                    value = getattr(data, field)
                    if field in ("apis2022_extended_answers", "apis2022_social_answers",
                                 "apis2022_program_selections"):
                        value = Jsonb(value)
                    values.append(value)
                assignments = ", ".join(f"{field} = %s" for field in current_fields)
                cursor.execute(
                    f"""UPDATE public.household_assessments AS a
                        SET {assignments}
                        WHERE a.assessment_id = %s AND NOT EXISTS (
                            SELECT 1 FROM public.vulnerability_classifications vc
                            WHERE vc.assessment_id = a.assessment_id
                        ) RETURNING a.assessment_id;""",
                    (*values, assessment_id),
                )
                if cursor.fetchone() is None:
                    raise HTTPException(
                        status_code=409,
                        detail="This assessment has already been classified. "
                               "Create a new assessment for revised answers.",
                    )
                cursor.execute(
                    ASSESSMENT_SELECT + " WHERE a.assessment_id = %s;",
                    (assessment_id,),
                )
                saved = cursor.fetchone()
    except UniqueViolation:
        raise HTTPException(
            status_code=409,
            detail="This household already has an assessment on that date.",
        )
    return saved


@router.put("/{assessment_id}/social-protection")
def update_assessment_social_protection(
    data: APIS2022SocialInputs,
    assessment_id: int = Path(ge=1),
    current_user: dict = Depends(require_assessment_write),
):
    """Edit model social answers for an assessment that has not been classified.

    The values remain inside household_assessments; no new database table.
    Never silently change the inputs of an existing classification.
    """
    answers = data.answers
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """SELECT h.household_id FROM public.households h
                   JOIN public.household_assessments a ON a.household_id = h.household_id
                   WHERE a.assessment_id = %s FOR UPDATE OF h;""",
                (assessment_id,),
            )
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="Assessment not found.")
            cursor.execute(
                """UPDATE public.household_assessments AS a
                   SET apis2022_social_answers = %s,
                       apis2022_program_selections = '{}'::jsonb
                   WHERE a.assessment_id = %s
                     AND NOT EXISTS (
                         SELECT 1 FROM public.vulnerability_classifications vc
                         WHERE vc.assessment_id = a.assessment_id
                     )
                   RETURNING a.assessment_id, a.apis2022_social_answers;""",
                (Jsonb(answers), assessment_id),
            )
            saved = cursor.fetchone()
            if saved is None:
                cursor.execute(
                    "SELECT 1 FROM public.household_assessments WHERE assessment_id = %s;",
                    (assessment_id,),
                )
                if cursor.fetchone() is not None:
                    raise HTTPException(
                        status_code=409,
                        detail="This assessment already has a classification. "
                               "Create a new assessment for revised answers.",
                    )
                raise HTTPException(status_code=404, detail="Assessment not found.")
    return saved
