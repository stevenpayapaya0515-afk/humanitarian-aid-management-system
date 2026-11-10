
"""Request and response schemas for AidTrack Aid Distribution."""

from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field


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


class DistributionBeneficiary(BaseModel):
    beneficiary_id: int
    household_id: int
    household_head: str
    barangay: str
    status: Literal["Pending", "For Review"]
    predicted_class: Literal["Low", "Medium", "High"]


class DistributionResponse(DistributionCreate):
    distribution_id: int
    household_id: int
    household_head: str
    barangay: str
    beneficiary_status: str
    predicted_class: Literal["Low", "Medium", "High"]
    is_simulation: bool
    recorded_by: int
    created_at: datetime
