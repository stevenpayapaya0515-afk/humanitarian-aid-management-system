
"""AidTrack Aid Distribution API - simulation-only prototype."""

from fastapi import APIRouter, Depends, HTTPException
from psycopg.rows import dict_row

from core.dependencies import get_current_user
from database import get_connection

from schemas.distributions import (
    DistributionBeneficiary,
    DistributionCreate,
    DistributionResponse,
)


router = APIRouter(
    prefix="/distributions",
    tags=["Aid Distribution"],
)


# ==========================================
# ROLE PERMISSIONS
# ==========================================

def require_distribution_read(
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("Admin", "Staff"):
        raise HTTPException(
            status_code=403,
            detail="Aid distribution access denied.",
        )
    return current_user


def require_distribution_write(
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "Staff":
        raise HTTPException(
            status_code=403,
            detail="Only Staff can record aid distribution simulations.",
        )
    return current_user


# ==========================================
# SHARED RECORD QUERY
# ==========================================

DISTRIBUTION_SELECT = """
    SELECT
        d.distribution_id,
        d.beneficiary_id,
        d.aid_type,
        d.quantity,
        d.unit,
        d.distribution_date,
        d.batch_code,
        d.notes,
        d.is_simulation,
        d.recorded_by,
        d.created_at,

        b.household_id,
        b.status AS beneficiary_status,

        h.household_head,
        h.barangay,

        v.predicted_class

    FROM public.aid_distributions d

    JOIN public.beneficiaries b
        ON b.beneficiary_id = d.beneficiary_id

    JOIN public.households h
        ON h.household_id = b.household_id

    JOIN public.vulnerability_classifications v
        ON v.classification_id = b.classification_id
"""


# ==========================================
# SELECTABLE BENEFICIARIES FOR SIMULATION
# ==========================================

@router.get(
    "/beneficiaries",
    response_model=list[DistributionBeneficiary],
)
def list_distribution_beneficiaries(
    current_user: dict = Depends(require_distribution_read),
):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT
                    b.beneficiary_id,
                    b.household_id,
                    h.household_head,
                    h.barangay,
                    b.status,
                    v.predicted_class

                FROM public.beneficiaries b

                JOIN public.households h
                    ON h.household_id = b.household_id

                JOIN public.vulnerability_classifications v
                    ON v.classification_id = b.classification_id

                WHERE b.status IN ('Pending', 'For Review')

                ORDER BY h.household_head, b.beneficiary_id;
                """
            )

            return cursor.fetchall()


# ==========================================
# DISTRIBUTION HISTORY
# ==========================================

@router.get(
    "",
    response_model=list[DistributionResponse],
)
def list_distributions(
    current_user: dict = Depends(require_distribution_read),
):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                DISTRIBUTION_SELECT
                + " ORDER BY d.distribution_id DESC;"
            )

            return cursor.fetchall()


# ==========================================
# RECORD DISTRIBUTION SIMULATION
# ==========================================

@router.post(
    "",
    response_model=DistributionResponse,
    status_code=201,
)
def create_distribution(
    data: DistributionCreate,
    current_user: dict = Depends(require_distribution_write),
):
    batch_code = data.batch_code.strip().upper()

    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:

            # Verify beneficiary record and lock it
            # against concurrent status changes.
            cursor.execute(
                """
                SELECT beneficiary_id, status
                FROM public.beneficiaries
                WHERE beneficiary_id = %s
                FOR SHARE;
                """,
                (data.beneficiary_id,),
            )

            beneficiary = cursor.fetchone()

            if beneficiary is None:
                raise HTTPException(
                    status_code=404,
                    detail="Beneficiary record not found.",
                )

            # Pending/For Review records may be used
            # ONLY in clearly labeled simulations.
            if beneficiary["status"] not in ("Pending", "For Review"):
                raise HTTPException(
                    status_code=409,
                    detail=(
                        "This beneficiary status is not available "
                        "for the simulation workflow."
                    ),
                )

            # The database forces is_simulation = TRUE.
            # No physical aid delivery is recorded here.
            cursor.execute(
                """
                INSERT INTO public.aid_distributions (
                    beneficiary_id,
                    aid_type,
                    quantity,
                    unit,
                    distribution_date,
                    batch_code,
                    notes,
                    is_simulation,
                    recorded_by
                )
                VALUES (
                    %s, %s, %s, %s, %s, %s, %s, TRUE, %s
                )
                ON CONFLICT (
                    beneficiary_id,
                    batch_code,
                    aid_type
                )
                DO NOTHING
                RETURNING distribution_id;
                """,
                (
                    data.beneficiary_id,
                    data.aid_type,
                    data.quantity,
                    data.unit,
                    data.distribution_date,
                    batch_code,
                    data.notes.strip(),
                    current_user["user_id"],
                ),
            )

            inserted = cursor.fetchone()

            if inserted is None:
                raise HTTPException(
                    status_code=409,
                    detail=(
                        "This beneficiary already has the same "
                        "aid type recorded for this batch."
                    ),
                )

            distribution_id = inserted["distribution_id"]

            cursor.execute(
                DISTRIBUTION_SELECT
                + " WHERE d.distribution_id = %s;",
                (distribution_id,),
            )

            return cursor.fetchone()
