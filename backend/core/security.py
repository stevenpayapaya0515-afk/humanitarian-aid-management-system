import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt
from dotenv import load_dotenv
from pwdlib import PasswordHash


# Read backend/.env
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

SECRET_KEY = os.environ["JWT_SECRET_KEY"]
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

password_hasher = PasswordHash.recommended()


# Hash the password before saving
def hash_password(password: str) -> str:
    return password_hasher.hash(password)


# Compare the entered password with the saved hash
def verify_password(password: str, saved_hash: str) -> bool:
    return password_hasher.verify(password, saved_hash)


# Create a token after successful login
def create_access_token(user_id: int, *, auth_version: int) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=ACCESS_TOKEN_EXPIRE_MINUTES
    )

    payload = {
        "sub": str(user_id),
        "auth_version": auth_version,
        "amr": ["pwd", "email_otp"],
        "exp": expires_at,
    }

    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


# Verify the signature and expiration of a token
def decode_access_token(token: str) -> dict:
    return jwt.decode(
        token,
        SECRET_KEY,
        algorithms=[ALGORITHM],
        options={"require": ["sub", "exp", "auth_version", "amr"]},
    )

def password_error(password: str, full_name: str = "", email: str = "") -> str | None:
    """Validate only the configured length and four character requirements."""
    # Identity parameters remain for existing route and invitation call sites.
    if not 12 <= len(password) <= 64:
        return "Use 12 to 64 characters."
    if not any("A" <= char <= "Z" for char in password):
        return "Add at least one uppercase letter."
    if not any("a" <= char <= "z" for char in password):
        return "Add at least one lowercase letter."
    if not any("0" <= char <= "9" for char in password):
        return "Add at least one number."
    if not any(not char.isalnum() and not char.isspace() for char in password):
        return "Add at least one symbol, such as !, @, or #."
    return None
