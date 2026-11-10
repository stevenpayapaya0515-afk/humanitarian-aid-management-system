from datetime import datetime

from pydantic import BaseModel, Field


class RecentActivity(BaseModel):
    activity_type: str
    description: str
    occurred_at: datetime


# Data returned to the Staff Dashboard.
class DashboardSummary(BaseModel):
    total_households: int
    total_population: int

    assessed_households: int

    classified_households: int
    low_vulnerability: int
    medium_vulnerability: int
    high_vulnerability: int

    # None until the Aid Distribution database module is implemented.
    aid_distributions: int | None = None
    simulated_distributions: int
    recent_activity: list[RecentActivity] = Field(default_factory=list)