from datetime import datetime

from pydantic import BaseModel, Field, field_validator


# Details needed when the Admin creates a Staff account
class StaffCreate(BaseModel):
    full_name: str = Field(min_length=1, max_length=100)
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=12, max_length=1024)

    # Remove extra spaces and check the name
    @field_validator("full_name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        value = value.strip()

        if not value:
            raise ValueError("Full name is required.")

        return value

    # Normalize email and perform a basic format check
    @field_validator("email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        value = value.strip().lower()

        if value.count("@") != 1 or any(
            character.isspace() for character in value
        ):
            raise ValueError("Enter a valid email address.")

        name, domain = value.split("@")

        if (
            not name
            or "." not in domain
            or domain.startswith(".")
            or domain.endswith(".")
        ):
            raise ValueError("Enter a valid email address.")

        return value


# Safe account details returned to the frontend
class UserListResponse(BaseModel):
    user_id: int
    full_name: str
    email: str
    role: str
    is_active: bool
    created_at: datetime

# Request for activating or deactivating a Staff account
class UserStatusUpdate(BaseModel):
    is_active: bool