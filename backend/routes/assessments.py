"""Household assessments using the APIS 2022 CARAGA 46-feature schema.

Assessment persistence only. Predictive classifications remain a separate workflow.
"""
from fastapi import APIRouter, Depends, HTTPException, Path, Query
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row

from core.dependencies import get_current_user
from database import get_connection
from schemas.assessments import (
    APIS2022_FEATURE_CATALOG, APIS2022_WRITE_FIELDS,
    AssessmentCreate, AssessmentResponse, AssessmentSocialUpdate,
)
from schemas.households import registration_matches_size

router = APIRouter(prefix="/assessments", tags=["Household Assessment"])


def require_assessment_read(current_user: dict = Depends(get_current_user)):
    if current_user["role"] not in ("Admin", "Staff"):
        raise HTTPException(status_code=403, detail="Assessment access denied.")
    return current_user


def require_assessment_write(current_user: dict = Depends(get_current_user)):
    if current_user["role"] != "Staff":
        raise HTTPException(status_code=403, detail="Only Staff may edit assessments.")
    return current_user


# Fixed, code-owned identifier names. Client values never enter SQL identifiers.
BASE_FIELDS = ("assessment_id", "household_id", "assessment_date",
               "data_origin", "recorded_by", "created_at", "region_code",
               "member_record_count", "member_roster_complete",
               "monthly_income_per_capita")
ALL_FIELDS = BASE_FIELDS + APIS2022_WRITE_FIELDS
assert len(ALL_FIELDS) == 56, (len(ALL_FIELDS), len(set(ALL_FIELDS)))
assert len(set(ALL_FIELDS)) == len(ALL_FIELDS)
ASSESSMENT_SELECT = (
    "SELECT " + ", ".join(f"a.{name}" for name in ALL_FIELDS) + ", "
    "EXISTS (SELECT 1 FROM public.vulnerability_classifications vc "
    "WHERE vc.assessment_id = a.assessment_id) AS has_classification, "
    "h.household_head, h.barangay "
    "FROM public.household_assessments a "
    "JOIN public.households h ON h.household_id = a.household_id"
)


@router.get("/apis2022/feature-catalog")
def apis2022_feature_catalog(current_user: dict = Depends(require_assessment_read)):
    return {
        "region_code": 16,
        "model_inputs": APIS2022_FEATURE_CATALOG,
        "derived_features": ["monthly_income_per_capita"],
        "source_inputs": ["monthly_income"],
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
                cursor.execute(ASSESSMENT_SELECT +
                    " WHERE a.household_id = %s ORDER BY a.assessment_id DESC;",
                    (household_id,))
            return cursor.fetchall()


@router.get("/{assessment_id}", response_model=AssessmentResponse)
def get_assessment(
    assessment_id: int = Path(ge=1),
    current_user: dict = Depends(require_assessment_read),
):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(ASSESSMENT_SELECT +
                           " WHERE a.assessment_id = %s;", (assessment_id,))
            saved = cursor.fetchone()
            if saved is None:
                raise HTTPException(status_code=404, detail="Assessment not found.")
            return saved


def _require_registration(cursor, household_id: int) -> dict:
    cursor.execute(
        "SELECT household_size, household_member FROM public.households "
        "WHERE household_id = %s FOR SHARE;", (household_id,)
    )
    registered = cursor.fetchone()
    if registered is None:
        raise HTTPException(status_code=404, detail="Household not found.")
    if not registration_matches_size(registered["household_size"],
                                     registered["household_member"]):
        raise HTTPException(status_code=422,
            detail="Complete the household member list in Registration first.")
    return registered


def _validate_family_size(data: AssessmentCreate, registered: dict) -> int:
    family_size = registered["household_size"]
    if data.family_size is not None and data.family_size != family_size:
        raise HTTPException(status_code=422,
            detail="Family size must match household registration (single-family assumption).")
    age_fields = (data.members_age_0_5, data.members_age_6_11,
                  data.members_age_12_17, data.members_age_60_plus)
    if all(v is not None for v in age_fields) and sum(age_fields) > family_size:
        raise HTTPException(status_code=422,
            detail="Selected age bands exceed registered household size.")
    return family_size


@router.post("", response_model=AssessmentResponse, status_code=201)
def create_assessment(
    data: AssessmentCreate,
    current_user: dict = Depends(require_assessment_write),
):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                registered = _require_registration(cursor, data.household_id)
                family_size = _validate_family_size(data, registered)
                values = data.model_dump(exclude={"household_id", "assessment_date",
                                                  "data_origin", "region_code",
                                                  "family_size"})
                # Fixed survey fields only; derived per-capita income is DB-generated.
                assert set(values) == set(APIS2022_WRITE_FIELDS) - {"family_size"}
                insert_fields = ("household_id", "assessment_date", "data_origin",
                                 "region_code", "family_size",
                                 "member_record_count", "member_roster_complete") + (
                                    tuple(k for k in APIS2022_WRITE_FIELDS if k != "family_size")
                                 ) + ("recorded_by",)
                params = (data.household_id, data.assessment_date, data.data_origin,
                          16, family_size, family_size, 1) + (
                    tuple(values[k] for k in APIS2022_WRITE_FIELDS if k != "family_size")
                ) + (current_user["user_id"],)
                query = ("INSERT INTO public.household_assessments ("
                         + ", ".join(insert_fields) + ") VALUES ("
                         + ", ".join(["%s"] * len(insert_fields))
                         + ") RETURNING assessment_id;")
                cursor.execute(query, params)
                assessment_id = cursor.fetchone()["assessment_id"]
                cursor.execute(ASSESSMENT_SELECT +
                               " WHERE a.assessment_id = %s;", (assessment_id,))
                return cursor.fetchone()
    except UniqueViolation as exc:
        raise HTTPException(status_code=409,
            detail="This household already has an assessment on that date.") from exc


@router.put("/{assessment_id}", response_model=AssessmentResponse)
def update_assessment(
    data: AssessmentCreate,
    assessment_id: int = Path(ge=1),
    current_user: dict = Depends(require_assessment_write),
):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                # Lock household first, same order used by the prediction workflow.
                cursor.execute(
                    "SELECT a.household_id FROM public.household_assessments a "
                    "JOIN public.households h ON h.household_id = a.household_id "
                    "WHERE a.assessment_id = %s FOR UPDATE OF h;",
                    (assessment_id,))
                existing = cursor.fetchone()
                if existing is None:
                    raise HTTPException(status_code=404, detail="Assessment not found.")
                if existing["household_id"] != data.household_id:
                    raise HTTPException(status_code=422,
                        detail="Cannot change the registered household of an assessment.")
                registered = _require_registration(cursor, data.household_id)
                family_size = _validate_family_size(data, registered)
                values = data.model_dump(exclude={"household_id", "region_code",
                                                  "family_size"})
                values["family_size"] = family_size
                values["member_record_count"] = family_size
                values["member_roster_complete"] = 1
                fields = tuple(values)
                assert set(fields) == set(APIS2022_WRITE_FIELDS) | {
                    "assessment_date", "data_origin", "member_record_count",
                    "member_roster_complete"
                }
                cursor.execute(
                    "UPDATE public.household_assessments a SET "
                    + ", ".join(f"{k} = %s" for k in fields)
                    + " WHERE a.assessment_id = %s AND NOT EXISTS ("
                    "SELECT 1 FROM public.vulnerability_classifications vc "
                    "WHERE vc.assessment_id = a.assessment_id) "
                    "RETURNING a.assessment_id;",
                    (*tuple(values[k] for k in fields), assessment_id))
                if cursor.fetchone() is None:
                    raise HTTPException(status_code=409,
                        detail="Assessment already classified. Create a new assessment.")
                cursor.execute(ASSESSMENT_SELECT +
                               " WHERE a.assessment_id = %s;", (assessment_id,))
                return cursor.fetchone()
    except UniqueViolation as exc:
        raise HTTPException(status_code=409,
            detail="This household already has an assessment on that date.") from exc


@router.put("/{assessment_id}/social-protection", response_model=AssessmentResponse)
def update_assessment_social_protection(
    data: AssessmentSocialUpdate,
    assessment_id: int = Path(ge=1),
    current_user: dict = Depends(require_assessment_write),
):
    # This endpoint now expects flat named fields, not old APIS-code JSON.
    updated = data.model_dump(exclude_unset=True)
    if not updated:
        raise HTTPException(status_code=422, detail="No social-protection answers supplied.")
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                "SELECT a.household_id FROM public.household_assessments a "
                "JOIN public.households h ON h.household_id = a.household_id "
                "WHERE a.assessment_id = %s FOR UPDATE OF h;", (assessment_id,))
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="Assessment not found.")
            cursor.execute(
                "UPDATE public.household_assessments a SET "
                + ", ".join(f"{k} = %s" for k in updated)
                + " WHERE a.assessment_id = %s AND NOT EXISTS ("
                "SELECT 1 FROM public.vulnerability_classifications vc "
                "WHERE vc.assessment_id = a.assessment_id) "
                "RETURNING a.assessment_id;",
                (*updated.values(), assessment_id))
            if cursor.fetchone() is None:
                raise HTTPException(status_code=409,
                    detail="Assessment already classified. Create a new assessment.")
            cursor.execute(ASSESSMENT_SELECT +
                           " WHERE a.assessment_id = %s;", (assessment_id,))
            return cursor.fetchone()
