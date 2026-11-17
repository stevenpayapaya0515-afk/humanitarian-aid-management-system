"""Staff-recorded deliveries following manual beneficiary approval."""
from fastapi import APIRouter, Depends, HTTPException
from psycopg.rows import dict_row
from psycopg import errors
from psycopg.types.json import Jsonb
from core.dependencies import get_current_user
from database import get_connection
from ml_service.train_apis2022_vulnerability import MODEL_VERSION as VERSION
from schemas.distributions import (
    DistributionBeneficiary, DistributionCreate, DistributionCorrection,
    DistributionResponse, DistributionUpdate,
)

router = APIRouter(prefix="/distributions", tags=["Aid Distribution"])

def require_distribution_read(current_user: dict = Depends(get_current_user)):
    if current_user["role"] not in ("Admin", "Staff"):
        raise HTTPException(status_code=403, detail="Aid distribution access denied.")
    return current_user

def require_distribution_write(current_user: dict = Depends(get_current_user)):
    if current_user["role"] != "Staff":
        raise HTTPException(status_code=403, detail="Only Staff can record distributions.")
    return current_user

DISTRIBUTION_SELECT = """
    SELECT d.distribution_id, d.beneficiary_id, d.aid_type, d.quantity, d.unit,
           d.distribution_date, d.batch_code, d.notes, d.amount_php,
           d.assistance_purpose, d.source_agency, d.is_simulation, d.recorded_by,
           d.created_at, d.revision, d.updated_at, d.assessment_id, d.classification_id, d.assessment_data_origin,
           b.household_id, h.household_head, h.barangay, h.household_size,
           COALESCE(d.beneficiary_status_at_distribution, 'Not recorded') AS beneficiary_status,
           v.predicted_class
    FROM public.aid_distributions d
    JOIN public.beneficiaries b ON b.beneficiary_id = d.beneficiary_id
    JOIN public.households h ON h.household_id = b.household_id
    LEFT JOIN public.vulnerability_classifications v ON v.classification_id = d.classification_id
"""

@router.get("/beneficiaries", response_model=list[DistributionBeneficiary])
def list_distribution_beneficiaries(current_user: dict = Depends(require_distribution_read)):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute("""
                SELECT b.beneficiary_id, b.household_id, h.household_head, h.barangay,
                       h.household_size,
                       b.status, b.assessment_id, b.classification_id,
                       a.data_origin AS assessment_data_origin, v.predicted_class
                FROM public.beneficiaries b
                JOIN public.households h ON h.household_id = b.household_id
                JOIN public.household_assessments a ON a.assessment_id = b.assessment_id
                JOIN public.vulnerability_classifications v ON v.classification_id = b.classification_id
                WHERE b.status = 'Approved' AND v.model_version = %s
                  AND b.assessment_id = (SELECT assessment_id FROM public.household_assessments
                      WHERE household_id = b.household_id ORDER BY assessment_date DESC, assessment_id DESC LIMIT 1)
                  AND b.classification_id = (SELECT classification_id FROM public.vulnerability_classifications
                      WHERE assessment_id = b.assessment_id ORDER BY created_at DESC, classification_id DESC LIMIT 1)
                ORDER BY h.household_head, b.beneficiary_id;
            """, (VERSION,))
            return cursor.fetchall()

@router.get("", response_model=list[DistributionResponse])
def list_distributions(current_user: dict = Depends(require_distribution_read)):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(DISTRIBUTION_SELECT + " ORDER BY d.distribution_id DESC;")
            return cursor.fetchall()

@router.post("", response_model=DistributionResponse, status_code=201)
def create_distribution(data: DistributionCreate, current_user: dict = Depends(require_distribution_write)):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute("""SELECT h.household_id FROM public.households h
                JOIN public.beneficiaries b ON b.household_id = h.household_id
                WHERE b.beneficiary_id = %s FOR UPDATE OF h;""", (data.beneficiary_id,))
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="Beneficiary not found.")
            cursor.execute("""SELECT b.household_id, b.status, b.assessment_id, b.classification_id,
                    a.data_origin, v.model_version
                FROM public.beneficiaries b
                JOIN public.household_assessments a ON a.assessment_id = b.assessment_id
                JOIN public.vulnerability_classifications v ON v.classification_id = b.classification_id
                WHERE b.beneficiary_id = %s FOR UPDATE OF b;""", (data.beneficiary_id,))
            record = cursor.fetchone()
            if record["status"] != "Approved":
                raise HTTPException(status_code=409, detail="Approve the beneficiary review before recording distribution.")
            if (record["assessment_id"], record["classification_id"]) != (data.expected_assessment_id, data.expected_classification_id):
                raise HTTPException(status_code=409, detail="The review changed. Refresh beneficiaries and check the details again.")
            cursor.execute("""SELECT assessment_id FROM public.household_assessments
                WHERE household_id = %s ORDER BY assessment_date DESC, assessment_id DESC LIMIT 1;""",
                (record["household_id"],))
            latest = cursor.fetchone()
            cursor.execute("""SELECT classification_id FROM public.vulnerability_classifications
                WHERE assessment_id = %s ORDER BY created_at DESC, classification_id DESC LIMIT 1;""",
                (latest["assessment_id"],))
            prediction = cursor.fetchone()
            if (latest["assessment_id"] != record["assessment_id"] or prediction is None
                    or prediction["classification_id"] != record["classification_id"] or record["model_version"] != VERSION):
                raise HTTPException(status_code=409, detail="A newer assessment or classification needs staff review. Use latest assessment in Beneficiary Management.")
            practice = record["data_origin"] == "synthetic"
            if not practice and not data.delivery_confirmed:
                raise HTTPException(status_code=422, detail="Confirm that the assistance was received before recording delivery.")
            cursor.execute("""INSERT INTO public.aid_distributions
                (beneficiary_id, aid_type, quantity, unit, distribution_date, batch_code, notes,
                 amount_php, assistance_purpose, source_agency,
                 is_simulation, recorded_by, assessment_id, classification_id,
                 assessment_data_origin, beneficiary_status_at_distribution)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'Approved')
                ON CONFLICT (beneficiary_id, batch_code, aid_type) DO NOTHING RETURNING distribution_id;""",
                (data.beneficiary_id, data.aid_type, data.quantity, data.unit, data.distribution_date,
                 data.batch_code.strip().upper(), data.notes.strip(), data.amount_php,
                 data.assistance_purpose, data.source_agency, practice, current_user["user_id"],
                 record["assessment_id"], record["classification_id"], record["data_origin"]))
            inserted = cursor.fetchone()
            if inserted is None:
                raise HTTPException(status_code=409, detail="This aid type is already recorded for this beneficiary and batch.")
            cursor.execute(DISTRIBUTION_SELECT + " WHERE d.distribution_id = %s;", (inserted["distribution_id"],))
            return cursor.fetchone()

# Only editable transaction details can change; beneficiary and research
# provenance remain attached to the original recorded transaction.
_DISTRIBUTION_EDIT_FIELDS = (
    "aid_type", "quantity", "unit", "amount_php", "assistance_purpose",
    "source_agency", "distribution_date", "batch_code", "notes",
)


def _distribution_snapshot(row: dict) -> dict:
    snapshot = {}
    for field in _DISTRIBUTION_EDIT_FIELDS:
        value = row[field]
        if field in ("amount_php", "distribution_date") and value is not None:
            value = str(value)
        snapshot[field] = value
    return snapshot


@router.patch("/{distribution_id}", response_model=DistributionResponse)
def correct_distribution(
    distribution_id: int,
    data: DistributionUpdate,
    current_user: dict = Depends(require_distribution_write),
):
    if distribution_id < 1:
        raise HTTPException(status_code=422, detail="Invalid distribution ID.")
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                "SELECT * FROM public.aid_distributions WHERE distribution_id = %s FOR UPDATE;",
                (distribution_id,),
            )
            previous = cursor.fetchone()
            if previous is None:
                raise HTTPException(status_code=404, detail="Distribution record not found.")

            # Protect against stale Flutter forms and edits to a different record.
            if previous["revision"] != data.expected_revision:
                raise HTTPException(
                    status_code=409,
                    detail="This distribution was updated by someone else. Refresh the records and review the latest values.",
                )
            if (
                previous["beneficiary_id"] != data.beneficiary_id
                or previous["assessment_id"] != data.expected_assessment_id
                or previous["classification_id"] != data.expected_classification_id
            ):
                raise HTTPException(
                    status_code=409,
                    detail="Distribution reference changed. Refresh and reopen the record.",
                )
            if not previous["is_simulation"] and not data.delivery_confirmed:
                raise HTTPException(
                    status_code=422,
                    detail="Confirm the original real delivery details before correcting this transaction.",
                )

            before = _distribution_snapshot(previous)
            after = {
                "aid_type": data.aid_type,
                "quantity": data.quantity,
                "unit": data.unit,
                "amount_php": str(data.amount_php) if data.amount_php is not None else None,
                "assistance_purpose": data.assistance_purpose,
                "source_agency": data.source_agency,
                "distribution_date": str(data.distribution_date),
                "batch_code": data.batch_code.strip().upper(),
                "notes": data.notes.strip(),
            }
            if before == after:
                raise HTTPException(status_code=409, detail="No changes detected in the distribution record.")

            try:
                cursor.execute(
                    """UPDATE public.aid_distributions
                       SET aid_type = %s, quantity = %s, unit = %s, amount_php = %s,
                           assistance_purpose = %s, source_agency = %s,
                           distribution_date = %s, batch_code = %s, notes = %s,
                           revision = revision + 1, updated_at = NOW()
                       WHERE distribution_id = %s AND revision = %s
                       RETURNING revision;""",
                    (
                        data.aid_type, data.quantity, data.unit, data.amount_php,
                        data.assistance_purpose, data.source_agency,
                        data.distribution_date, data.batch_code.strip().upper(),
                        data.notes.strip(), distribution_id, data.expected_revision,
                    ),
                )
            except errors.UniqueViolation as exc:
                raise HTTPException(
                    status_code=409,
                    detail="This beneficiary already has the same aid type recorded for that batch.",
                ) from exc
            revision = cursor.fetchone()
            if revision is None:
                raise HTTPException(status_code=409, detail="Distribution changed. Refresh and try again.")
            cursor.execute(
                """INSERT INTO public.aid_distribution_corrections
                   (distribution_id, revision_before, revision_after, old_values,
                    new_values, correction_reason, changed_by)
                   VALUES (%s, %s, %s, %s, %s, %s, %s);""",
                (
                    distribution_id, data.expected_revision, revision["revision"],
                    Jsonb(before), Jsonb(after),
                    data.correction_reason, current_user["user_id"],
                ),
            )
            cursor.execute(
                DISTRIBUTION_SELECT + " WHERE d.distribution_id = %s;",
                (distribution_id,),
            )
            return cursor.fetchone()


@router.get("/{distribution_id}/corrections", response_model=list[DistributionCorrection])
def distribution_correction_history(
    distribution_id: int,
    current_user: dict = Depends(require_distribution_read),
):
    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                "SELECT 1 FROM public.aid_distributions WHERE distribution_id = %s;",
                (distribution_id,),
            )
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="Distribution record not found.")
            cursor.execute(
                """SELECT correction_id, distribution_id, revision_before,
                          revision_after, old_values, new_values, correction_reason,
                          changed_by, changed_at
                   FROM public.aid_distribution_corrections
                   WHERE distribution_id = %s
                   ORDER BY correction_id DESC LIMIT 100;""",
                (distribution_id,),
            )
            return cursor.fetchall()
