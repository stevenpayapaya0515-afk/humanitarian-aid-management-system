from datetime import date, datetime

from pydantic import BaseModel


class ReportCounts(BaseModel):
    total_households: int
    total_population: int
    assessed_households: int
    classified_households: int
    low_vulnerability: int
    medium_vulnerability: int
    high_vulnerability: int
    pending_beneficiaries: int
    for_review_beneficiaries: int
    approved_beneficiaries: int
    rejected_beneficiaries: int
    aid_distributions: int
    simulated_distributions: int


class BarangayReport(ReportCounts):
    barangay: str


class ReportsSummary(BaseModel):
    generated_at: datetime
    from_date: date | None
    to_date: date | None
    barangay_filter: str | None
    totals: ReportCounts
    barangays: list[BarangayReport]
