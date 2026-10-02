from datetime import datetime

from pydantic import BaseModel, Field, field_validator, model_validator


# Create/edit request. Names are stored in ONE column in households.
class HouseholdCreate(BaseModel):
    household_head: str = Field(min_length=1, max_length=100)
    barangay: str = Field(min_length=1, max_length=100)
    purok: str | None = Field(default=None, max_length=100)
    address: str = Field(min_length=1)
    household_size: int = Field(ge=1, le=2147483647, strict=True)

    # OTHER members only, one full name per line. The head is separate.
    household_member: str = ""

    @field_validator("household_head", "barangay", "address")
    @classmethod
    def clean_required_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("This field is required.")
        return value

    @field_validator("purok")
    @classmethod
    def clean_purok(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return value.strip() or None

    @field_validator("household_member")
    @classmethod
    def clean_member_names(cls, value: str) -> str:
        # Normalize Windows line breaks and ignore empty lines.
        names = [line.strip() for line in value.splitlines() if line.strip()]
        if any(len(name) > 100 for name in names):
            raise ValueError("Each member name must be at most 100 characters.")
        # Do not deduplicate: different people may have the same full name.
        return "\n".join(names)

    @model_validator(mode="after")
    def check_member_count(self):
        names = self.household_member.splitlines()
        if self.household_size != len(names) + 1:
            raise ValueError(
                "Household size must equal 1 head plus the other members."
            )
        return self


# Details returned to Flutter. Old incomplete lists can still be viewed.
class HouseholdResponse(BaseModel):
    household_id: int
    household_head: str
    barangay: str
    purok: str | None
    address: str
    household_size: int
    household_member: str
    registered_by: int
    created_at: datetime
    updated_at: datetime
    members_complete: bool
