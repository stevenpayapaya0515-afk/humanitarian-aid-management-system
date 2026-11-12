from pydantic import BaseModel, Field
from uuid import UUID
from datetime import datetime


# Data sent by the login page
class LoginRequest(BaseModel):
    recaptcha_token: str = Field(min_length=1, max_length=8192)
    email: str = Field(min_length=1, max_length=254)
    password: str = Field(min_length=1, max_length=1024)


# Account details returned after login
class UserResponse(BaseModel):
    user_id: int
    full_name: str
    email: str
    role: str


# Response after a successful login
class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse

# Data submitted when changing the logged-in user's password.
class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=1024)
    new_password: str = Field(min_length=12, max_length=1024)

class LoginChallengeResponse(BaseModel):
    challenge_id: UUID
    expires_at: datetime
    message: str = "Check your email for the six-digit login code."


class VerifyLoginRequest(BaseModel):
    challenge_id: UUID
    code: str = Field(pattern=r"^[0-9]{6}$")
