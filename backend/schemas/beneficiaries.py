
"""Beneficiary request and response schemas for AidTrack."""

from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field


BeneficiaryStatus = Literal[
    "Pending",
    "For Review",
    "Approved",
    "Rejected",
]


class BeneficiaryCreate(BaseModel):
    household_id: int = Field(ge=1, strict=True)
    review_notes: str = Field(default="", max_length=1000)


class BeneficiaryUpdate(BaseModel):
    expected_assessment_id: int = Field(ge=1, strict=True)
    expected_classification_id: int = Field(ge=1, strict=True)
    expected_status: BeneficiaryStatus
    review_confirmed: bool = Field(default=False, strict=True)
    status: BeneficiaryStatus
    review_notes: str = Field(default="", max_length=1000)


class BeneficiaryCandidate(BaseModel):
    household_id: int
    household_head: str
    barangay: str
    household_size: int

    assessment_id: int
    assessment_date: date

    classification_id: int
    predicted_class: Literal["Low", "Medium", "High"]

    assessment_data_origin: Literal[
        "synthetic",
        "lgu_authorized",
    ]

    model_training_data_origin: Literal[
        "psa_apis2019",
        "synthetic",
        "lgu_authorized",
    ]

    prediction_status: Literal[
        "preliminary",
        "validated",
    ]


class BeneficiaryResponse(BeneficiaryCandidate):
    beneficiary_id: int
    status: BeneficiaryStatus
    review_notes: str

    registered_by: int
    updated_by: int | None

    created_at: datetime
    updated_at: datetime


class BeneficiaryHistoryEvent(BaseModel):
    event_id: int
    beneficiary_id: int

    old_status: BeneficiaryStatus | None
    new_status: BeneficiaryStatus

    review_notes: str
    changed_by: int
    changed_at: datetime


class BeneficiaryReassessment(BaseModel):
    expected_assessment_id: int = Field(ge=1, strict=True)
    expected_classification_id: int = Field(ge=1, strict=True)
