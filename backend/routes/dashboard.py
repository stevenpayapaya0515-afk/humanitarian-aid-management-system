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


# Only logged-in Admin and Staff accounts can view the totals.
@router.get("/summary", response_model=DashboardSummary)
def get_dashboard_summary(
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("Admin", "Staff"):
        raise HTTPException(
            status_code=403,
            detail="You do not have access to the dashboard.",
        )

    with get_connection() as connection:
        with connection.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """
                SELECT
                    COUNT(*) AS total_households,
                    COALESCE(SUM(household_size), 0) AS total_population
                FROM public.households;
                """
            )

            summary = cursor.fetchone()

    return summary