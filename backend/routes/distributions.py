"""Staff-recorded deliveries following manual beneficiary approval."""
from fastapi import APIRouter, Depends, HTTPException
from psycopg.rows import dict_row
from core.dependencies import get_current_user
from database import get_connection
from ml_service.apis_rules import VERSION
from schemas.distributions import DistributionBeneficiary, DistributionCreate, DistributionResponse

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
           d.distribution_date, d.batch_code, d.notes, d.is_simulation, d.recorded_by,
           d.created_at, d.assessment_id, d.classification_id, d.assessment_data_origin,
           b.household_id, h.household_head, h.barangay,
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
                 is_simulation, recorded_by, assessment_id, classification_id,
                 assessment_data_origin, beneficiary_status_at_distribution)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'Approved')
                ON CONFLICT (beneficiary_id, batch_code, aid_type) DO NOTHING RETURNING distribution_id;""",
                (data.beneficiary_id, data.aid_type, data.quantity, data.unit, data.distribution_date,
                 data.batch_code.strip().upper(), data.notes.strip(), practice, current_user["user_id"],
                 record["assessment_id"], record["classification_id"], record["data_origin"]))
            inserted = cursor.fetchone()
            if inserted is None:
                raise HTTPException(status_code=409, detail="This aid type is already recorded for this beneficiary and batch.")
            cursor.execute(DISTRIBUTION_SELECT + " WHERE d.distribution_id = %s;", (inserted["distribution_id"],))
            return cursor.fetchone()
