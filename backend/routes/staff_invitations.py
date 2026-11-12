"""Invitation-only Staff onboarding for AidTrack.

Admin -> POST /staff-invitations -> email one-use link.
Staff -> POST /staff-invitations/validate -> POST /staff-invitations/accept.
Only accept creates a public.users Staff row. None of these routes issues JWTs.
"""

import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field, field_validator
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row

from core.dependencies import require_admin
from core.security import hash_password, password_error
from database import get_connection
from services.gmail_login_email import GmailConfigError, GmailDeliveryError, _email_address
from services.staff_invitation_email import send_staff_invitation_email

router = APIRouter(prefix='/staff-invitations', tags=['Staff Invitations'])
INVITE_HOURS = 24
INVITE_RESEND_COOLDOWN_SECONDS = 60


class InvitationEmail(BaseModel):
    email: str = Field(min_length=3, max_length=254)

    @field_validator('email')
    @classmethod
    def email_format(cls, value: str) -> str:
        from re import fullmatch
        email = value.strip().lower()
        if not fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+', email):
            raise ValueError('Please enter a valid email address.')
        try:
            return _email_address(email)
        except ValueError as exc:
            raise ValueError('Please enter a valid email address.') from exc


class InvitationToken(BaseModel):
    token: str = Field(min_length=32, max_length=128)


class AcceptInvitation(InvitationToken):
    # These are AidTrack employee details, not the seeded IT107 form fields.
    first_name: str = Field(min_length=2, max_length=50)
    middle_name: str | None = Field(default=None, max_length=50)
    last_name: str = Field(min_length=2, max_length=50)
    employee_number: str | None = Field(default=None, max_length=32)
    contact_number: str = Field(pattern=r"^09[0-9]{9}$")
    position: str = Field(min_length=2, max_length=100)
    office: str = Field(min_length=2, max_length=100)
    assigned_barangay: str | None = Field(default=None, max_length=100)
    home_address: str | None = Field(default=None, max_length=255)
    privacy_consent: bool
    password: str = Field(min_length=12, max_length=64)

    @field_validator('first_name', 'last_name', 'position', 'office')
    @classmethod
    def required_text(cls, value: str) -> str:
        value = ' '.join(value.split())
        if len(value) < 2:
            raise ValueError('This field requires at least two characters.')
        return value

    @field_validator('middle_name', 'employee_number', 'assigned_barangay',
                     'home_address', mode='before')
    @classmethod
    def clean_optional(cls, value):
        if value is None:
            return None
        value = ' '.join(str(value).split())
        return value or None

    @field_validator('employee_number')
    @classmethod
    def employee_no_format(cls, value: str | None) -> str | None:
        import re
        if value and not re.fullmatch(r'[A-Za-z0-9-]{3,32}', value):
            raise ValueError('Employee number must have 3–32 letters, numbers or hyphens.')
        return value


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode('utf-8')).hexdigest()


def _audit(cursor, *, kind: str, email: str, user_id: int | None, request: Request):
    # Never log passwords, invitation tokens, or other credentials.
    client_ip = request.client.host if request.client else None
    cursor.execute(
        """INSERT INTO public.security_activity_logs
            (event_type, email_typed, user_id, ip_address, user_agent)
            VALUES (%s, %s, %s, %s, %s);""",
        (kind, email, user_id, client_ip, request.headers.get('user-agent', '')[:1024]),
    )


def _find_valid_invite(cursor, token: str):
    cursor.execute(
        """SELECT invitation_id, invited_email, expires_at, sent_at,
                  accepted_at, revoked_at
           FROM public.staff_invitations
           WHERE token_sha256 = %s
           FOR UPDATE;""",
        (_hash_token(token),),
    )
    invitation = cursor.fetchone()
    if (
        invitation is None
        or invitation['sent_at'] is None
        or invitation['accepted_at'] is not None
        or invitation['revoked_at'] is not None
        or invitation['expires_at'] <= datetime.now(timezone.utc)
    ):
        raise HTTPException(status_code=410, detail='Invitation is invalid, expired, or already used. Contact your administrator.')
    return invitation


@router.post('', status_code=201)
def invite_staff(data: InvitationEmail, request: Request,
                 admin: dict = Depends(require_admin)):
    """Admin-only: issue a new one-time invitation, then email it."""
    token = secrets.token_urlsafe(32)  # at least 256 unpredictable bits
    digest = _hash_token(token)
    invitation_id = None
    expires_at = datetime.now(timezone.utc) + timedelta(hours=INVITE_HOURS)

    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            # Serialize invites per email to prevent concurrent resends.
            cursor.execute('SELECT pg_advisory_xact_lock(hashtext(%s));', (data.email,))
            cursor.execute('SELECT 1 FROM public.users WHERE lower(email) = %s;', (data.email,))
            if cursor.fetchone():
                raise HTTPException(status_code=409, detail='This email already has an AidTrack account.')
            cursor.execute(
                """SELECT 1 FROM public.staff_invitations
                   WHERE lower(invited_email) = %s AND sent_at > NOW() - INTERVAL '60 seconds'
                   LIMIT 1;""", (data.email,),
            )
            if cursor.fetchone():
                raise HTTPException(status_code=429, detail='Please wait a minute before sending another invitation.')
            cursor.execute(
                """UPDATE public.staff_invitations SET revoked_at = NOW()
                   WHERE lower(invited_email) = %s
                     AND accepted_at IS NULL AND revoked_at IS NULL;""", (data.email,),
            )
            cursor.execute(
                """INSERT INTO public.staff_invitations
                    (invited_email, token_sha256, invited_by, expires_at)
                   VALUES (%s, %s, %s, %s)
                   RETURNING invitation_id;""",
                (data.email, digest, admin['user_id'], expires_at),
            )
            invitation_id = cursor.fetchone()['invitation_id']

    # Email is an external side-effect: database transaction must not hold locks
    # while Gmail makes a network call. On failure revoke the pending invite.
    try:
        send_staff_invitation_email(
            to_email=data.email, token=token, expires_at=expires_at,
        )
    except (GmailConfigError, GmailDeliveryError, RuntimeError, ValueError):
        with get_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute(
                    """UPDATE public.staff_invitations SET revoked_at = NOW()
                       WHERE invitation_id = %s AND accepted_at IS NULL;""",
                    (invitation_id,),
                )
                _audit(cursor, kind='INVITE_EMAIL_FAILED', email=data.email,
                       user_id=admin['user_id'], request=request)
        raise HTTPException(status_code=503, detail='Could not send invitation. Check Gmail configuration and try again.') from None

    with get_connection() as conn:
        with conn.cursor() as cursor:
            cursor.execute(
                'UPDATE public.staff_invitations SET sent_at = NOW() WHERE invitation_id = %s;',
                (invitation_id,),
            )
            _audit(cursor, kind='INVITE_SENT', email=data.email,
                   user_id=admin['user_id'], request=request)

    return {
        'message': 'Staff invitation sent. The account is created only after registration.',
        'email': data.email,
        'invitation_id': invitation_id,
        'expires_at': expires_at,
    }


@router.get('')
def list_invitations(admin: dict = Depends(require_admin)):
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            cursor.execute(
                """SELECT invitation_id, invited_email, created_at, expires_at,
                          sent_at, accepted_at, revoked_at,
                          CASE
                            WHEN accepted_at IS NOT NULL THEN 'Accepted'
                            WHEN revoked_at IS NOT NULL THEN 'Revoked'
                            WHEN expires_at <= NOW() THEN 'Expired'
                            ELSE 'Pending'
                          END AS status
                   FROM public.staff_invitations
                   ORDER BY created_at DESC LIMIT 100;"""
            )
            return cursor.fetchall()


@router.post('/validate')
def validate_invitation(data: InvitationToken):
    # Public endpoint: never returns the token, account list or password hashes.
    with get_connection() as conn:
        with conn.cursor(row_factory=dict_row) as cursor:
            invite = _find_valid_invite(cursor, data.token)
            return {'email': invite['invited_email'], 'expires_at': invite['expires_at']}


@router.post('/accept', status_code=201)
def accept_invitation(data: AcceptInvitation, request: Request):
    if not data.privacy_consent:
        raise HTTPException(status_code=422, detail='Privacy consent is required.')

    # Existing Admin/Staff dashboards continue to read public.users.full_name.
    full_name = ' '.join(filter(None, [data.first_name, data.middle_name, data.last_name]))
    try:
        with get_connection() as conn:
            with conn.cursor(row_factory=dict_row) as cursor:
                invite = _find_valid_invite(cursor, data.token)
                error = password_error(data.password, full_name, invite['invited_email'])
                if error is not None:
                    raise HTTPException(status_code=400, detail=error)

                cursor.execute(
                    """INSERT INTO public.users (full_name, email, password_hash, role)
                       VALUES (%s, %s, %s, 'Staff')
                       RETURNING user_id;""",
                    (full_name, invite['invited_email'], hash_password(data.password)),
                )
                user_id = cursor.fetchone()['user_id']

                # User + employee profile + invitation consumption are atomic.
                cursor.execute(
                    """INSERT INTO public.staff_profiles
                         (user_id, first_name, middle_name, last_name,
                          employee_number, contact_number, position, office,
                          assigned_barangay, home_address)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s);""",
                    (user_id, data.first_name, data.middle_name, data.last_name,
                     data.employee_number, data.contact_number, data.position,
                     data.office, data.assigned_barangay, data.home_address),
                )
                cursor.execute(
                    'UPDATE public.staff_invitations SET accepted_at = NOW() WHERE invitation_id = %s;',
                    (invite['invitation_id'],),
                )
                _audit(cursor, kind='INVITE_ACCEPTED', email=invite['invited_email'],
                       user_id=user_id, request=request)
    except UniqueViolation:
        raise HTTPException(
            status_code=409,
            detail='The invited email or employee number is already registered.',
        ) from None

    return {'message': 'Staff registration completed. You may now sign in to AidTrack.'}
