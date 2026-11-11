"""OTP primitives for AidTrack's staged two-step login.

This module does not send emails or issue JWTs. That wiring comes later.
"""
import hashlib
import hmac
import os
import secrets
from pathlib import Path
from uuid import UUID, uuid4

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / '.env')


def _otp_key() -> bytes:
    """Read the private 32-byte OTP HMAC key from configuration."""
    raw = os.getenv('OTP_HMAC_SECRET', '').strip()
    try:
        key = bytes.fromhex(raw)
    except ValueError:
        raise RuntimeError('OTP_HMAC_SECRET must be 64 hexadecimal characters.') from None
    if len(key) != 32:
        raise RuntimeError('OTP_HMAC_SECRET must be 64 hexadecimal characters.')
    return key


def generate_login_otp() -> str:
    """Return a cryptographically secure six-digit code."""
    return f'{secrets.randbelow(1_000_000):06d}'


def generate_challenge_id() -> UUID:
    """Create an unpredictable ID for one pending login."""
    return uuid4()


def hash_login_otp(code: str, *, user_id: int, challenge_id: UUID) -> str:
    """Bind the hash to this account, challenge and login purpose."""
    if not (isinstance(code, str) and len(code) == 6 and code.isascii() and code.isdigit()):
        raise ValueError('OTP must contain exactly six digits.')
    message = f'login:{user_id}:{challenge_id}:{code}'.encode('utf-8')
    return hmac.new(_otp_key(), message, hashlib.sha256).hexdigest()


def verify_login_otp(
    code: str, *, user_id: int, challenge_id: UUID, stored_hash: str
) -> bool:
    """Compare an entered code against its stored keyed hash."""
    if not (isinstance(code, str) and len(code) == 6 and code.isascii() and code.isdigit()):
        return False
    if not isinstance(stored_hash, str) or len(stored_hash) != 64:
        return False
    expected = hash_login_otp(code, user_id=user_id, challenge_id=challenge_id)
    return hmac.compare_digest(expected, stored_hash)
