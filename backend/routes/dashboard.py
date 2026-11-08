from fastapi import APIRouter, Depends, HTTPException
from psycopg.rows import dict_row

from core.dependencies import get_current_user
from database import get_connection
from schemas.dashboard import DashboardSummary


# Dashboard endpoints.
router = APIRouter(
    prefix="/dashboard",
    tags=["Dashboard"],
)


@router.get("/summary", response_model=DashboardSummary)
def get_dashboard_summary(
    current_user: dict = Depends(get_current_user),
):
    # Only logged-in Admin and Staff accounts can view dashboard totals.
    if current_user["role"] not in ("Admin", "Staff"):
        raise HTTPException(
            status_code=403,
            detail="You do not have access to the dashboard.",
        )

    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:

            # ==========================================
            # 1. HOUSEHOLD TOTALS
            # ==========================================

            cursor.execute(
                """
                SELECT
                    COUNT(*) AS total_households,
                    COALESCE(SUM(household_size), 0) AS total_population
                FROM public.households;
                """
            )

            summary = cursor.fetchone()

            # ==========================================
            # 2. ASSESSED HOUSEHOLDS
            # ==========================================

            cursor.execute(
                """
                SELECT
                    COUNT(DISTINCT household_id) AS assessed_households
                FROM public.household_assessments;
                """
            )

            assessment_summary = cursor.fetchone()

            # ==========================================
            # 3. LATEST VULNERABILITY CLASSIFICATIONS
            # ==========================================

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

                latest_classification AS (
                    SELECT DISTINCT ON (la.household_id)
                        la.household_id,
                        vc.predicted_class
                    FROM latest_assessment la

                    INNER JOIN public.vulnerability_classifications vc
                        ON vc.assessment_id = la.assessment_id

                    ORDER BY
                        la.household_id,
                        vc.created_at DESC,
                        vc.classification_id DESC
                )

                SELECT
                    COUNT(*) AS classified_households,

                    COUNT(*) FILTER (
                        WHERE predicted_class = 'Low'
                    ) AS low_vulnerability,

                    COUNT(*) FILTER (
                        WHERE predicted_class = 'Medium'
                    ) AS medium_vulnerability,

                    COUNT(*) FILTER (
                        WHERE predicted_class = 'High'
                    ) AS high_vulnerability

                FROM latest_classification;
                """
            )

            vulnerability_summary = cursor.fetchone()

            # ==========================================
            # 4. RECENT HOUSEHOLD ACTIVITIES
            # ==========================================

            cursor.execute(
                """
                SELECT
                    activity_type,
                    description,
                    occurred_at

                FROM (

                    -- Household registrations
                    SELECT
                        'Household Registration'::TEXT
                            AS activity_type,

                        'Registered '
                            || household_head
                            || ' in '
                            || barangay
                            AS description,

                        created_at AS occurred_at

                    FROM public.households

                    UNION ALL

                    -- Household assessments
                    SELECT
                        'Household Assessment'::TEXT
                            AS activity_type,

                        'Assessment recorded for '
                            || h.household_head
                            AS description,

                        ha.created_at AS occurred_at

                    FROM public.household_assessments ha

                    INNER JOIN public.households h
                        ON h.household_id = ha.household_id

                    UNION ALL

                    -- Vulnerability classifications
                    SELECT
                        'Vulnerability Classification'::TEXT
                            AS activity_type,

                        'Random Forest classified '
                            || h.household_head
                            || ' as '
                            || vc.predicted_class
                            || ' vulnerability'
                            AS description,

                        vc.created_at AS occurred_at

                    FROM public.vulnerability_classifications vc

                    INNER JOIN public.household_assessments ha
                        ON ha.assessment_id = vc.assessment_id

                    INNER JOIN public.households h
                        ON h.household_id = ha.household_id

                ) AS activities

                ORDER BY occurred_at DESC

                LIMIT 8;
                """
            )

            recent_activity = cursor.fetchall()

    # ==========================================
    # 5. COMBINE DASHBOARD DATA
    # ==========================================

    return {
        **summary,
        **assessment_summary,
        **vulnerability_summary,

        # Not connected until the Aid Distribution table exists.
        "aid_distributions": None,

        "recent_activity": recent_activity,
    }