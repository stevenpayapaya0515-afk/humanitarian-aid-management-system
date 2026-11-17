"""Request and response schemas for reviewed aid-distribution records."""

from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, model_validator, field_validator


AidType = Literal[
    "Food Packs", "Drinking Water", "Hygiene Kits", "Clothing", "Blankets",
    "Medical Supplies", "School Supplies", "Shelter Materials", "Livelihood Kits",
    "Medical Assistance", "Educational Assistance", "Burial Assistance",
    "Transportation Assistance", "Cash Relief", "Livelihood Assistance", "Other",
]

AidUnit = Literal["packs", "pieces", "liters", "kilograms", "boxes", "sets", "grants"]

FINANCIAL_AID_TYPES = frozenset({
    "Medical Assistance", "Educational Assistance", "Burial Assistance",
    "Transportation Assistance", "Cash Relief", "Livelihood Assistance",
})


class DistributionCreate(BaseModel):
    beneficiary_id: int = Field(ge=1, strict=True)
    expected_assessment_id: int = Field(ge=1, strict=True)
    expected_classification_id: int = Field(ge=1, strict=True)
    delivery_confirmed: bool = Field(default=False, strict=True)
    aid_type: AidType
    quantity: int = Field(ge=1, le=100000, strict=True)
    unit: AidUnit
    amount_php: Decimal | None = Field(default=None, gt=0, max_digits=12, decimal_places=2)
    assistance_purpose: str = Field(min_length=5, max_length=250)
    source_agency: str = Field(default="", max_length=120)
    distribution_date: date
    batch_code: str = Field(
        min_length=3, max_length=32, pattern=r"^[A-Za-z0-9][A-Za-z0-9_-]*$"
    )
    notes: str = Field(default="", max_length=500)

    @model_validator(mode="after")
    def validate_assistance_shape(self):
        self.assistance_purpose = self.assistance_purpose.strip()
        self.source_agency = self.source_agency.strip()
        if len(self.assistance_purpose) < 5:
            raise ValueError("Describe the assessed need in at least 5 characters.")
        if self.aid_type in FINANCIAL_AID_TYPES:
            if self.unit != "grants" or self.quantity != 1 or self.amount_php is None:
                raise ValueError("Financial assistance requires one grant and a PHP amount.")
        elif self.unit == "grants" or self.amount_php is not None:
            raise ValueError("In-kind assistance uses a quantity and unit, not a PHP grant amount.")
        return self

    @field_validator("distribution_date")
    @classmethod
    def no_future_delivery(cls, value):
        if value > datetime.now(timezone(timedelta(hours=8))).date():
            raise ValueError("Distribution date cannot be in the future.")
        return value



class DistributionUpdate(DistributionCreate):
    """Full replacement of editable details; immutable references are checked."""
    expected_revision: int = Field(ge=1, strict=True)
    correction_reason: str = Field(min_length=10, max_length=500)

    @field_validator("correction_reason")
    @classmethod
    def require_meaningful_reason(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 10:
            raise ValueError("Provide a correction reason of at least 10 characters.")
        return value


class DistributionCorrection(BaseModel):
    correction_id: int
    distribution_id: int
    revision_before: int
    revision_after: int
    old_values: dict
    new_values: dict
    correction_reason: str
    changed_by: int
    changed_at: datetime


class DistributionBeneficiary(BaseModel):
    beneficiary_id: int
    household_id: int
    household_head: str
    barangay: str
    household_size: int
    status: Literal["Approved"]
    assessment_id: int
    classification_id: int
    assessment_data_origin: Literal["synthetic", "lgu_authorized"]
    predicted_class: Literal["Low", "Medium", "High"]


class DistributionResponse(BaseModel):
    beneficiary_id: int
    aid_type: AidType
    quantity: int
    unit: AidUnit
    amount_php: Decimal | None
    assistance_purpose: str
    source_agency: str
    distribution_date: date
    batch_code: str
    notes: str
    assessment_id: int | None = None
    classification_id: int | None = None
    assessment_data_origin: str | None = None
    distribution_id: int
    household_id: int
    household_head: str
    household_size: int
    barangay: str
    beneficiary_status: str
    predicted_class: Literal["Low", "Medium", "High"] | None
    is_simulation: bool
    recorded_by: int
    created_at: datetime
    revision: int
    updated_at: datetime
