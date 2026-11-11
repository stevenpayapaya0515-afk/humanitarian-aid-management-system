"""Send private AidTrack Staff registration invitations using existing Gmail OAuth.

Works with backend/services/gmail_login_email.py from the previous Gmail phase.
An invite link is not a login token and does NOT create an authenticated session.
"""

from datetime import datetime, timedelta, timezone
from urllib.parse import quote
import os

from services.gmail_login_email import _make_message, _send_message


def build_invitation_url(token: str) -> str:
    # The host is explicitly configured, never taken from the incoming Host header.
    base_url = os.getenv('FRONTEND_PUBLIC_URL', 'http://localhost:3000').strip().rstrip('/')
    if not (base_url.startswith('https://') or base_url.startswith('http://localhost:') or base_url.startswith('http://127.0.0.1:')):
        raise RuntimeError('FRONTEND_PUBLIC_URL must be HTTPS, except for local development.')
    return f'{base_url}/?invite={quote(token, safe="")}'


def send_staff_invitation_email(*, to_email: str, token: str, expires_at: datetime) -> str:
    if expires_at.tzinfo is None:
        raise ValueError('expires_at must include a timezone')
    expires_pht = expires_at.astimezone(timezone(timedelta(hours=8)))
    text = (
        'An LGU Administrator invited you to register as an AidTrack Staff member.\n\n'
        'Open this private registration link:\n'
        f'{build_invitation_url(token)}\n\n'
        f'It expires on {expires_pht:%B %d, %Y at %I:%M %p} PHT, and can only be used once.\n'
        'The registration email is fixed to the address that received this invitation.\n\n'
        'If you did not expect this invitation, ignore this message.\n'
        'Never forward your invitation link. AidTrack will never ask for your password by email.\n'
    )
    return _send_message(_make_message(
        to_email=to_email,
        subject='AidTrack | Staff registration invitation',
        body=text,
    ))
