import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt
from dotenv import load_dotenv
from pwdlib import PasswordHash
import re
from zxcvbn import zxcvbn


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
def create_access_token(user_id: int) -> str:
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=ACCESS_TOKEN_EXPIRE_MINUTES
    )

    payload = {
        "sub": str(user_id),
        "exp": expires_at,
    }

    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


# Verify the signature and expiration of a token
def decode_access_token(token: str) -> dict:
    return jwt.decode(
        token,
        SECRET_KEY,
        algorithms=[ALGORITHM],
        options={"require": ["sub", "exp"]},
    )

def password_error(password: str, full_name: str = "", email: str = "") -> str | None:
    """Return a safe error message, or None when a new password passes."""
    # Check length before running the strength estimator. Never trim passwords.
    if not 12 <= len(password) <= 64:
        return "Use 12 to 64 characters."

    if not any(c.isupper() for c in password):
        return "Add at least one uppercase letter."
    if not any(c.islower() for c in password):
        return "Add at least one lowercase letter."
    if not any(c.isdigit() for c in password):
        return "Add at least one number."
    if not any(not c.isalnum() and not c.isspace() for c in password):
        return "Add at least one symbol, such as !, @, or #."

    # Treat personal and system names as predictable password material.
    personal_words = ["aidtrack", "administrator", "staff"]
    personal_words += re.findall(r"\w+", full_name.casefold())
    personal_words += re.findall(r"\w+", email.partition("@")[0].casefold())
    personal_words = [word for word in personal_words if len(word) >= 3]

    if any(word in password.casefold() for word in personal_words):
        return "Avoid your name, email name, role, or the system name."

    # Runs locally. Never log or return the result: it contains the password.
    result = zxcvbn(password, user_inputs=personal_words)
    if result["score"] < 4:
        return (
            "Password is too predictable. Avoid common passwords, "
            "sequences, repeated characters, and simple word substitutions."
        )
    return None