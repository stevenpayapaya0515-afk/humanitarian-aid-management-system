from pydantic import BaseModel


# Totals returned to the Staff Dashboard.
class DashboardSummary(BaseModel):
    total_households: int
    total_population: int