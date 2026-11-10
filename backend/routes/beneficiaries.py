
"""AidTrack Beneficiary Management API."""

from fastapi import APIRouter, Depends, HTTPException
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row

from core.dependencies import get_current_user
from database import get_connection

from schemas.beneficiaries import (
    BeneficiaryCandidate,
    BeneficiaryCreate,
    BeneficiaryHistoryEvent,
    BeneficiaryResponse,
    BeneficiaryUpdate,
)


router = APIRouter(
    prefix="/beneficiaries",
    tags=["Beneficiary Management"],
)


# ==========================================
# ROLE PERMISSIONS
# ==========================================

def require_read(
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("Admin", "Staff"):
        raise HTTPException(
            status_code=403,
            detail="Beneficiary access denied.",
        )

    return current_user


def require_write(
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "Staff":
        raise HTTPException(
            status_code=403,
            detail="Only Staff can manage beneficiaries.",
        )

    return current_user


# ==========================================
# SHARED DATABASE QUERY
# ==========================================

BENEFICIARY_SELECT = """
    SELECT
        b.beneficiary_id,
        b.household_id,
        b.assessment_id,
        b.classification_id,
        b.status,
        b.review_notes,
        b.registered_by,
        b.updated_by,
        b.created_at,
        b.updated_at,

        h.household_head,
        h.barangay,
        h.household_size,

        a.assessment_date,
        a.data_origin AS assessment_data_origin,

        v.predicted_class,
        v.model_training_data_origin,
        v.prediction_status

    FROM public.beneficiaries b

    JOIN public.households h
        ON h.household_id = b.household_id

    JOIN public.household_assessments a
        ON a.assessment_id = b.assessment_id

    JOIN public.vulnerability_classifications v
        ON v.classification_id = b.classification_id
"""


# ==========================================
# AVAILABLE HOUSEHOLDS FOR REVIEW
# ==========================================

@router.get(
    "/candidates",
    response_model=list[BeneficiaryCandidate],
)
def list_candidates(
    current_user: dict = Depends(require_read),
):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                WITH latest_assessment AS (
                    SELECT DISTINCT ON (a.household_id)
                        a.household_id,
                        a.assessment_id,
                        a.assessment_date,
                        a.data_origin

                    FROM public.household_assessments a

                    ORDER BY
                        a.household_id,
                        a.assessment_date DESC,
                        a.assessment_id DESC
                ),

                latest_prediction AS (
                    SELECT DISTINCT ON (v.assessment_id)
                        v.assessment_id,
                        v.classification_id,
                        v.predicted_class,
                        v.model_training_data_origin,
                        v.prediction_status

                    FROM public.vulnerability_classifications v

                    ORDER BY
                        v.assessment_id,
                        v.created_at DESC,
                        v.classification_id DESC
                )

                SELECT
                    la.household_id,
                    h.household_head,
                    h.barangay,
                    h.household_size,

                    la.assessment_id,
                    la.assessment_date,

                    lp.classification_id,
                    lp.predicted_class,

                    la.data_origin AS assessment_data_origin,
                    lp.model_training_data_origin,
                    lp.prediction_status

                FROM latest_assessment la

                JOIN latest_prediction lp
                    ON lp.assessment_id = la.assessment_id

                JOIN public.households h
                    ON h.household_id = la.household_id

                LEFT JOIN public.beneficiaries b
                    ON b.household_id = la.household_id

                WHERE b.beneficiary_id IS NULL

                ORDER BY
                    h.household_head,
                    h.household_id;
                """
            )

            return cursor.fetchall()


# ==========================================
# LIST BENEFICIARY REVIEW RECORDS
# ==========================================

@router.get(
    "",
    response_model=list[BeneficiaryResponse],
)
def list_beneficiaries(
    current_user: dict = Depends(require_read),
):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                BENEFICIARY_SELECT
                + " ORDER BY b.beneficiary_id DESC;"
            )

            return cursor.fetchall()


# ==========================================
# REGISTER HOUSEHOLD FOR REVIEW
# ==========================================

@router.post(
    "",
    response_model=BeneficiaryResponse,
    status_code=201,
)
def create_beneficiary(
    data: BeneficiaryCreate,
    current_user: dict = Depends(require_write),
):
    try:
        with get_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:

                # Lock the household during registration.
                cursor.execute(
                    """
                    SELECT household_id
                    FROM public.households
                    WHERE household_id = %s
                    FOR UPDATE;
                    """,
                    (data.household_id,),
                )

                if cursor.fetchone() is None:
                    raise HTTPException(
                        status_code=404,
                        detail="Household not found.",
                    )

                # Retrieve the household's latest assessment.
                cursor.execute(
                    """
                    SELECT assessment_id
                    FROM public.household_assessments
                    WHERE household_id = %s
                    ORDER BY
                        assessment_date DESC,
                        assessment_id DESC
                    LIMIT 1;
                    """,
                    (data.household_id,),
                )

                assessment = cursor.fetchone()

                if assessment is None:
                    raise HTTPException(
                        status_code=409,
                        detail=(
                            "This household needs an assessment first."
                        ),
                    )

                # Retrieve the latest classification
                # for that assessment.
                cursor.execute(
                    """
                    SELECT classification_id
                    FROM public.vulnerability_classifications
                    WHERE assessment_id = %s
                    ORDER BY
                        created_at DESC,
                        classification_id DESC
                    LIMIT 1;
                    """,
                    (assessment["assessment_id"],),
                )

                classification = cursor.fetchone()

                if classification is None:
                    raise HTTPException(
                        status_code=409,
                        detail=(
                            "Classify the latest household "
                            "assessment first."
                        ),
                    )

                # All newly registered records begin Pending.
                # ML predictions cannot approve beneficiaries.
                cursor.execute(
                    """
                    INSERT INTO public.beneficiaries (
                        household_id,
                        assessment_id,
                        classification_id,
                        status,
                        review_notes,
                        registered_by
                    )
                    VALUES (
                        %s, %s, %s,
                        'Pending',
                        %s, %s
                    )
                    RETURNING beneficiary_id;
                    """,
                    (
                        data.household_id,
                        assessment["assessment_id"],
                        classification["classification_id"],
                        data.review_notes.strip(),
                        current_user["user_id"],
                    ),
                )

                beneficiary_id = cursor.fetchone()[
                    "beneficiary_id"
                ]

                # Save the initial history event.
                cursor.execute(
                    """
                    INSERT INTO public.beneficiary_status_history (
                        beneficiary_id,
                        old_status,
                        new_status,
                        review_notes,
                        changed_by
                    )
                    VALUES (
                        %s, NULL, 'Pending', %s, %s
                    );
                    """,
                    (
                        beneficiary_id,
                        data.review_notes.strip(),
                        current_user["user_id"],
                    ),
                )

                cursor.execute(
                    BENEFICIARY_SELECT
                    + " WHERE b.beneficiary_id = %s;",
                    (beneficiary_id,),
                )

                return cursor.fetchone()

    except UniqueViolation:
        raise HTTPException(
            status_code=409,
            detail=(
                "This household already has a "
                "beneficiary review record."
            ),
        )


# ==========================================
# UPDATE BENEFICIARY REVIEW
# ==========================================

@router.patch(
    "/{beneficiary_id}",
    response_model=BeneficiaryResponse,
)
def update_beneficiary(
    beneficiary_id: int,
    data: BeneficiaryUpdate,
    current_user: dict = Depends(require_write),
):
    if beneficiary_id < 1:
        raise HTTPException(
            status_code=422,
            detail="Invalid beneficiary ID.",
        )

    notes = data.review_notes.strip()

    if data.status in ("Approved", "Rejected") and not notes:
        raise HTTPException(
            status_code=422,
            detail=(
                "Review notes are required for "
                "Approved or Rejected records."
            ),
        )

    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:

            cursor.execute(
                """
                SELECT
                    b.household_id,
                    b.assessment_id,
                    b.classification_id,
                    b.status,
                    b.review_notes,

                    a.data_origin AS assessment_data_origin,

                    v.model_training_data_origin,
                    v.prediction_status

                FROM public.beneficiaries b

                JOIN public.household_assessments a
                    ON a.assessment_id = b.assessment_id

                JOIN public.vulnerability_classifications v
                    ON v.classification_id = b.classification_id

                WHERE b.beneficiary_id = %s

                FOR UPDATE OF b;
                """,
                (beneficiary_id,),
            )

            record = cursor.fetchone()

            if record is None:
                raise HTTPException(
                    status_code=404,
                    detail="Beneficiary not found.",
                )

            # Final decisions are blocked for synthetic
            # and preliminary records in this prototype.
            if data.status in ("Approved", "Rejected"):

                if (
                    record["assessment_data_origin"]
                    != "lgu_authorized"
                    or record["model_training_data_origin"]
                    != "lgu_authorized"
                    or record["prediction_status"]
                    != "validated"
                ):
                    raise HTTPException(
                        status_code=409,
                        detail=(
                            "Cannot finalize this decision using "
                            "synthetic or preliminary data. "
                            "Use Pending or For Review during testing."
                        ),
                    )

                # Avoid finalizing a record linked to
                # an outdated household assessment.
                cursor.execute(
                    """
                    SELECT assessment_id
                    FROM public.household_assessments
                    WHERE household_id = %s
                    ORDER BY
                        assessment_date DESC,
                        assessment_id DESC
                    LIMIT 1;
                    """,
                    (record["household_id"],),
                )

                current_assessment = cursor.fetchone()

                if (
                    current_assessment["assessment_id"]
                    != record["assessment_id"]
                ):
                    raise HTTPException(
                        status_code=409,
                        detail=(
                            "A newer assessment exists. "
                            "Review the latest assessment first."
                        ),
                    )

                cursor.execute(
                    """
                    SELECT classification_id
                    FROM public.vulnerability_classifications
                    WHERE assessment_id = %s
                    ORDER BY
                        created_at DESC,
                        classification_id DESC
                    LIMIT 1;
                    """,
                    (record["assessment_id"],),
                )

                current_prediction = cursor.fetchone()

                if (
                    current_prediction["classification_id"]
                    != record["classification_id"]
                ):
                    raise HTTPException(
                        status_code=409,
                        detail=(
                            "A newer classification exists. "
                            "Review the latest prediction first."
                        ),
                    )

            # Only save a new history event
            # when something actually changes.
            if (
                record["status"] != data.status
                or record["review_notes"] != notes
            ):

                cursor.execute(
                    """
                    UPDATE public.beneficiaries
                    SET
                        status = %s,
                        review_notes = %s,
                        updated_by = %s,
                        updated_at = NOW()
                    WHERE beneficiary_id = %s;
                    """,
                    (
                        data.status,
                        notes,
                        current_user["user_id"],
                        beneficiary_id,
                    ),
                )

                cursor.execute(
                    """
                    INSERT INTO public.beneficiary_status_history (
                        beneficiary_id,
                        old_status,
                        new_status,
                        review_notes,
                        changed_by
                    )
                    VALUES (%s, %s, %s, %s, %s);
                    """,
                    (
                        beneficiary_id,
                        record["status"],
                        data.status,
                        notes,
                        current_user["user_id"],
                    ),
                )

            cursor.execute(
                BENEFICIARY_SELECT
                + " WHERE b.beneficiary_id = %s;",
                (beneficiary_id,),
            )

            return cursor.fetchone()


# ==========================================
# BENEFICIARY STATUS HISTORY
# ==========================================

@router.get(
    "/{beneficiary_id}/history",
    response_model=list[BeneficiaryHistoryEvent],
)
def get_beneficiary_history(
    beneficiary_id: int,
    current_user: dict = Depends(require_read),
):
    if beneficiary_id < 1:
        raise HTTPException(
            status_code=422,
            detail="Invalid beneficiary ID.",
        )

    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:

            cursor.execute(
                """
                SELECT 1
                FROM public.beneficiaries
                WHERE beneficiary_id = %s;
                """,
                (beneficiary_id,),
            )

            if cursor.fetchone() is None:
                raise HTTPException(
                    status_code=404,
                    detail="Beneficiary not found.",
                )

            cursor.execute(
                """
                SELECT
                    event_id,
                    beneficiary_id,
                    old_status,
                    new_status,
                    review_notes,
                    changed_by,
                    changed_at

                FROM public.beneficiary_status_history

                WHERE beneficiary_id = %s

                ORDER BY
                    changed_at DESC,
                    event_id DESC;
                """,
                (beneficiary_id,),
            )

            return cursor.fetchall()
