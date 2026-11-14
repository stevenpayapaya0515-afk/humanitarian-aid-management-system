"""Household assessment request and response formats for AidTrack."""

from decimal import Decimal
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator


class AssessmentCreate(BaseModel):
    household_id: int = Field(ge=1, strict=True)
    assessment_date: date

    age_0_5_count: int = Field(ge=0, strict=True)
    age_6_17_count: int = Field(ge=0, strict=True)
    age_18_59_count: int = Field(ge=0, strict=True)
    age_60_plus_count: int = Field(ge=0, strict=True)
    senior_citizens_count: int = Field(ge=0, strict=True)
    pwd_count: int = Field(ge=0, strict=True)

    monthly_income_range: str = Field(min_length=1, max_length=30)
    employment_status: str = Field(min_length=1, max_length=40)
    livelihood_type: str = Field(min_length=1, max_length=50)
    previous_humanitarian_assistance: bool
    beneficiary_status: str = Field(min_length=1, max_length=30)

    disaster_affected: bool
    housing_damage_level: Literal["None", "Minor", "Major", "Destroyed"]
    displaced: bool
    data_origin: Literal["synthetic", "lgu_authorized"] = "synthetic"

    roof_material: int | None = Field(default=None, strict=True)
    wall_material: int | None = Field(default=None, strict=True)
    electricity: int | None = Field(default=None, strict=True)
    drinking_water_source: int | None = Field(default=None, strict=True)
    toilet_facility: int | None = Field(default=None, strict=True)
    working_adult_present: int | None = Field(default=None, strict=True)
    apis_single_family: bool | None = Field(default=None, strict=True)

    # Optional financial history adapted from FIES concepts, not an imported PSA record.
    financial_reference_year: int | None = Field(default=None, ge=1900, strict=True)
    financial_single_family: bool | None = Field(default=None, strict=True)
    average_family_size: Decimal | None = Field(default=None, ge=1, max_digits=7, decimal_places=2)
    annual_family_income: Decimal | None = Field(default=None, max_digits=14, decimal_places=2)
    annual_family_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    annual_food_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)

    # Residence classification and spending refer to the same financial year.
    financial_residence_classification: Literal["Urban", "Rural"] | None = None
    annual_housing_utilities_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    annual_health_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    annual_education_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)
    annual_transport_expenditure: Decimal | None = Field(default=None, ge=0, max_digits=14, decimal_places=2)

    @model_validator(mode="after")
    def check_financial_history(self):
        values = (self.average_family_size, self.annual_family_income,
                  self.annual_family_expenditure, self.annual_food_expenditure)
        detailed = (self.annual_housing_utilities_expenditure, self.annual_health_expenditure, self.annual_education_expenditure, self.annual_transport_expenditure)
        supplied = self.financial_residence_classification is not None or any(v is not None for v in detailed) or self.financial_reference_year is not None or self.financial_single_family is not None or any(v is not None for v in values)
        if not supplied:
            return self  # Legacy assessments remain readable; unknown is not zero.
        if self.financial_reference_year is None or self.financial_reference_year >= self.assessment_date.year:
            raise ValueError("Financial history must identify a completed calendar year before the assessment year.")
        if self.financial_single_family is not True:
            raise ValueError("Financial amounts must refer to one family sharing income and expenses during that year.")
        if self.average_family_size is None:
            raise ValueError("Enter the average family size for the reference year.")
        if all(v is None for v in values[1:]):
            raise ValueError("Enter at least one known annual financial amount, or omit financial history.")
        if self.annual_food_expenditure is not None and self.annual_family_expenditure is not None and self.annual_food_expenditure > self.annual_family_expenditure:
            raise ValueError("Food expenditure cannot exceed total expenditure for the same year.")
        if any(v is not None for v in detailed):
            if self.annual_family_expenditure is None:
                raise ValueError("Enter total annual expenditure when recording spending categories.")
            # Missing components remain NULL; sum only the known disjoint categories.
            known = [v for v in (self.annual_food_expenditure, *detailed) if v is not None]
            if sum(known, Decimal("0")) > self.annual_family_expenditure:
                raise ValueError("Known food, housing/utilities, health, education and transport expenses cannot exceed total annual expenditure.")
        return self

    @model_validator(mode="after")
    def check_apis_codes(self):
        from ml_service.apis_rules import VALID
        for name, codes in VALID.items():
            value = getattr(self, name)
            if value is not None and value not in codes:
                raise ValueError(f"Unsupported {name} code; use null for unknown/not applicable.")
        if self.working_adult_present == 1 and self.age_18_59_count + self.age_60_plus_count == 0:
            raise ValueError("A working adult requires at least one member aged 18 or above.")
        return self

    @model_validator(mode="after")
    def check_age_and_pwd_counts(self):
        total = (
            self.age_0_5_count + self.age_6_17_count
            + self.age_18_59_count + self.age_60_plus_count
        )
        if total < 1:
            raise ValueError("An assessment must include at least one person.")
        if self.senior_citizens_count != self.age_60_plus_count:
            raise ValueError("Senior citizen count must match the age 60+ count.")
        if self.pwd_count > total:
            raise ValueError("PWD count cannot exceed household population.")
        return self


class AssessmentResponse(AssessmentCreate):
    assessment_id: int
    household_head: str
    barangay: str
    recorded_by: int
    created_at: datetime
