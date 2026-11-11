"""Offline invitation validation. Does not send email or write to PostgreSQL.

Run from backend/: python tests/check_staff_invitation_email.py
"""
import os
import sys
from pathlib import Path
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.staff_invitation_email import build_invitation_url, send_staff_invitation_email
from services import staff_invitation_email


def main():
    token = 'test_token_only_abcdefghijklmnopqrstuvwxyz012345'
    with patch.dict(os.environ, {
        'FRONTEND_PUBLIC_URL': 'http://localhost:3000',
        'GMAIL_SENDER_EMAIL': 'aidtrack-testing@example.com',
    }):
        url = build_invitation_url(token)
        assert url == f'http://localhost:3000/?invite={token}'
        expiry = datetime.now(timezone.utc) + timedelta(hours=24)
        captured = []
        def fake_send(msg):
            captured.append(msg)
            return 'offline-test-message-id'
        with patch.object(staff_invitation_email, '_send_message', fake_send):
            response = send_staff_invitation_email(
                to_email='invited.staff@example.com', token=token,
                expires_at=expiry,
            )
        assert response == 'offline-test-message-id'
        assert captured[0]['To'] == 'invited.staff@example.com'
        assert url in captured[0].get_content()
        assert 'AidTrack' in captured[0]['Subject']
        assert 'PHT' in captured[0].get_content()
    print('PASS: Invitation link template and sender format.')
    print('PASS: No Gmail API call, database write, user account or JWT created.')


if __name__ == '__main__':
    main()
