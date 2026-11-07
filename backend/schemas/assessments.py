"""Household assessment request and response formats for AidTrack."""

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
