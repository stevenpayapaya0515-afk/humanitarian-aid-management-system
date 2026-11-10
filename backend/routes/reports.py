
from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from psycopg.rows import dict_row

from core.dependencies import get_current_user
from database import get_connection
from schemas.reports import ReportsSummary


router = APIRouter(
    prefix="/reports",
    tags=["Staff Reports"],
)


COUNT_FIELDS = (
    "total_households",
    "total_population",
    "assessed_households",
    "classified_households",
    "low_vulnerability",
    "medium_vulnerability",
    "high_vulnerability",
    "pending_beneficiaries",
    "for_review_beneficiaries",
    "approved_beneficiaries",
    "rejected_beneficiaries",
    "simulated_distributions",
)


@router.get("/summary", response_model=ReportsSummary)
def get_reports_summary(
    from_date: date | None = None,
    to_date: date | None = None,
    barangay: str | None = Query(default=None, max_length=100),
    current_user: dict = Depends(get_current_user),
):
    # Read-only report for authorized personnel.
    if current_user["role"] not in ("Admin", "Staff"):
        raise HTTPException(
            status_code=403,
            detail="You do not have access to reports.",
        )

    if (from_date is None) != (to_date is None):
        raise HTTPException(
            status_code=400,
            detail="Provide both from_date and to_date.",
        )

    if from_date is not None and from_date > to_date:
        raise HTTPException(
            status_code=400,
            detail="From Date cannot be after To Date.",
        )

    barangay_filter = (barangay or "").strip() or None

    # Use bound parameters for all user-provided filters.
    search_pattern = (
        f"%{barangay_filter}%" if barangay_filter else None
    )

    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                WITH latest_assessment AS (
                    SELECT DISTINCT ON (household_id)
                        household_id,
                        assessment_id
                    FROM public.household_assessments
                    ORDER BY
                        household_id,
                        assessment_date DESC,
                        assessment_id DESC
                ),

                latest_prediction AS (
                    SELECT DISTINCT ON (la.household_id)
                        la.household_id,
                        vc.predicted_class
                    FROM latest_assessment la
                    JOIN public.vulnerability_classifications vc
                        ON vc.assessment_id = la.assessment_id
                    ORDER BY
                        la.household_id,
                        vc.created_at DESC,
                        vc.classification_id DESC
                ),

                distribution_totals AS (
                    SELECT
                        b.household_id,
                        COUNT(*) AS simulation_count
                    FROM public.aid_distributions d
                    JOIN public.beneficiaries b
                        ON b.beneficiary_id = d.beneficiary_id
                    WHERE d.is_simulation = TRUE
                    GROUP BY b.household_id
                )

                SELECT
                    MIN(BTRIM(h.barangay)) AS barangay,

                    COUNT(*) AS total_households,

                    COALESCE(
                        SUM(h.household_size), 0
                    ) AS total_population,

                    COUNT(*) FILTER (
                        WHERE la.assessment_id IS NOT NULL
                    ) AS assessed_households,

                    COUNT(*) FILTER (
                        WHERE lp.predicted_class IS NOT NULL
                    ) AS classified_households,

                    COUNT(*) FILTER (
                        WHERE lp.predicted_class = 'Low'
                    ) AS low_vulnerability,

                    COUNT(*) FILTER (
                        WHERE lp.predicted_class = 'Medium'
                    ) AS medium_vulnerability,

                    COUNT(*) FILTER (
                        WHERE lp.predicted_class = 'High'
                    ) AS high_vulnerability,

                    COUNT(*) FILTER (
                        WHERE b.status = 'Pending'
                    ) AS pending_beneficiaries,

                    COUNT(*) FILTER (
                        WHERE b.status = 'For Review'
                    ) AS for_review_beneficiaries,

                    COUNT(*) FILTER (
                        WHERE b.status = 'Approved'
                    ) AS approved_beneficiaries,

                    COUNT(*) FILTER (
                        WHERE b.status = 'Rejected'
                    ) AS rejected_beneficiaries,

                    COALESCE(
                        SUM(dt.simulation_count), 0
                    ) AS simulated_distributions

                FROM public.households h

                LEFT JOIN latest_assessment la
                    ON la.household_id = h.household_id

                LEFT JOIN latest_prediction lp
                    ON lp.household_id = h.household_id

                LEFT JOIN public.beneficiaries b
                    ON b.household_id = h.household_id

                LEFT JOIN distribution_totals dt
                    ON dt.household_id = h.household_id

                WHERE (
                    %s::date IS NULL
                    OR (h.created_at AT TIME ZONE 'Asia/Manila')::date
                       >= %s::date
                )
                AND (
                    %s::date IS NULL
                    OR (h.created_at AT TIME ZONE 'Asia/Manila')::date
                       <= %s::date
                )
                AND (
                    %s::text IS NULL
                    OR h.barangay ILIKE %s
                )

                GROUP BY LOWER(BTRIM(h.barangay))
                ORDER BY LOWER(BTRIM(h.barangay));
                """,
                (
                    from_date,
                    from_date,
                    to_date,
                    to_date,
                    search_pattern,
                    search_pattern,
                ),
            )

            rows = cursor.fetchall()

    totals = {
        field: sum(int(row[field]) for row in rows)
        for field in COUNT_FIELDS
    }

    return {
        "generated_at": datetime.now(timezone.utc),
        "from_date": from_date,
        "to_date": to_date,
        "barangay_filter": barangay_filter,
        "totals": totals,
        "barangays": rows,
    }
