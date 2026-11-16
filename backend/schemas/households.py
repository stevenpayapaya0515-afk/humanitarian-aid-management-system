from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


def registered_member_count(household_member: str | None) -> int:
    """Count other household members; the head is stored separately."""
    return sum(1 for name in (household_member or "").splitlines() if name.strip())


def registration_matches_size(household_size: int, household_member: str | None) -> bool:
    """A complete registration lists the head and every other household member."""
    return household_size == registered_member_count(household_member) + 1


def format_household_address(
    province: str,
    city_municipality: str,
    barangay: str,
    purok: str | None,
) -> str:
    """Construct a display address; it is not stored in PostgreSQL."""
    return ", ".join(
        part.strip()
        for part in (purok, barangay, city_municipality, province)
        if part and part.strip()
    )


class HouseholdCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    household_head: str = Field(min_length=1, max_length=100)
    province: str = Field(min_length=1, max_length=100)
    city_municipality: str = Field(min_length=1, max_length=100)
    barangay: str = Field(min_length=1, max_length=100)
    purok: str | None = Field(default=None, max_length=100)
    household_size: int = Field(ge=1, le=2147483647, strict=True)
    household_member: str = ""

    @field_validator("household_head", "province", "city_municipality", "barangay")
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
        names = [line.strip() for line in value.splitlines() if line.strip()]
        if any(len(name) > 100 for name in names):
            raise ValueError("Each member name must be at most 100 characters.")
        return "\n".join(names)

    @model_validator(mode="after")
    def check_member_count(self):
        if not registration_matches_size(self.household_size, self.household_member):
            raise ValueError("Household size must equal 1 head plus the other members.")
        return self


class HouseholdResponse(BaseModel):
    household_id: int
    household_head: str
    province: str
    city_municipality: str
    barangay: str
    purok: str | None
    full_address: str
    household_size: int
    household_member: str
    registered_by: int
    created_at: datetime
    updated_at: datetime
    members_complete: bool
