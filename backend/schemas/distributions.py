
"""Request and response schemas for AidTrack Aid Distribution."""

from datetime import date, datetime, timedelta, timezone
from typing import Literal

from pydantic import BaseModel, Field, field_validator


AidType = Literal[
    "Food Packs",
    "Drinking Water",
    "Hygiene Kits",
    "Clothing",
    "Blankets",
    "Medical Supplies",
    "Other",
]

AidUnit = Literal[
    "packs",
    "pieces",
    "liters",
    "kilograms",
    "boxes",
    "sets",
]


class DistributionCreate(BaseModel):
    beneficiary_id: int = Field(ge=1, strict=True)
    expected_assessment_id: int = Field(ge=1, strict=True)
    expected_classification_id: int = Field(ge=1, strict=True)
    delivery_confirmed: bool = Field(default=False, strict=True)
    aid_type: AidType
    quantity: int = Field(ge=1, le=100000, strict=True)
    unit: AidUnit
    distribution_date: date

    batch_code: str = Field(
        min_length=3,
        max_length=32,
        pattern=r"^[A-Za-z0-9][A-Za-z0-9_-]*$",
    )

    notes: str = Field(default="", max_length=500)


    @field_validator("distribution_date")
    @classmethod
    def no_future_delivery(cls, value):
        if value > datetime.now(timezone(timedelta(hours=8))).date():
            raise ValueError("Distribution date cannot be in the future.")
        return value


class DistributionBeneficiary(BaseModel):
    beneficiary_id: int
    household_id: int
    household_head: str
    barangay: str
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
    distribution_date: date
    batch_code: str
    notes: str
    assessment_id: int | None = None
    classification_id: int | None = None
    assessment_data_origin: str | None = None
    distribution_id: int
    household_id: int
    household_head: str
    barangay: str
    beneficiary_status: str
    predicted_class: Literal["Low", "Medium", "High"] | None
    is_simulation: bool
    recorded_by: int
    created_at: datetime
