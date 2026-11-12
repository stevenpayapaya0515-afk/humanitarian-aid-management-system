"""Integration tests against a DISPOSABLE database, never your AidTrack DB.

Install pytest/httpx; set AIDTRACK_TEST_DSN to a PostgreSQL connection string
whose database name is exactly aidtrack_security_test, then:
    python -m pytest tests/test_login_security.py -q
Tables in that test database are recreated by the suite. Gmail is mocked.
"""
import os
import sys
from pathlib import Path
from datetime import datetime, timedelta, timezone
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

import psycopg
import pytest
import jwt
from fastapi import FastAPI
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.setdefault('JWT_SECRET_KEY', 'isolated-test-key-' * 4)
os.environ.setdefault('OTP_HMAC_SECRET', 'a1' * 32)
from routes import auth
from core import dependencies
from core.security import hash_password, create_access_token
from services import login_captcha
from services.login_otp_store import create_login_challenge, mark_login_otp_sent

DSN = os.getenv('AIDTRACK_TEST_DSN')
pytestmark = pytest.mark.skipif(not DSN, reason='Disposable PostgreSQL AIDTRACK_TEST_DSN required')
PASSWORD = 'Private-Test-Password!9274'


def connect():
    assert psycopg.conninfo.conninfo_to_dict(DSN).get('dbname') == 'aidtrack_security_test'
    return psycopg.connect(DSN)


@pytest.fixture(autouse=True)
def setup_database():
    with connect() as connection:
        connection.execute('DROP TABLE IF EXISTS public.login_captchas, public.login_otps, public.users CASCADE')
        connection.execute('''CREATE TABLE public.users (
            user_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            full_name TEXT, email TEXT UNIQUE, password_hash TEXT, role TEXT,
            is_active BOOLEAN DEFAULT TRUE, failed_login_attempts INTEGER DEFAULT 0,
            locked_until TIMESTAMPTZ, auth_version INTEGER DEFAULT 1)''')
        root = Path(__file__).resolve().parents[2]
        # Execute the production CREATE TABLE/index SQL, without deployment guards/grants.
        for filename in ['11_create_login_otps.sql', '17_create_login_captchas.sql']:
            sql = (root / 'database' / filename).read_text()
            start = sql.index('CREATE TABLE')
            end = sql.index('GRANT', start)
            connection.execute(sql[start:end])
        connection.execute('''INSERT INTO public.users (full_name,email,password_hash,role)
            VALUES ('Test Admin','test@example.test',%s,'Admin')''', (hash_password(PASSWORD),))
    with patch.object(auth, 'get_connection', connect), \
         patch.object(dependencies, 'get_connection', connect), \
         patch.object(login_captcha, 'get_connection', connect):
        yield


@pytest.fixture
def client():
    app = FastAPI()
    app.include_router(auth.router)
    with TestClient(app, client=("127.0.0.1", 50000)) as value:
        yield value


def credentials(client, password=PASSWORD):
    with patch.object(login_captcha.secrets, 'choice', return_value='A'):
        response = client.get('/auth/captcha')
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'no-store'
    return dict(email='test@example.test', password=password,
                captcha_id=response.json()['captcha_id'], captcha_answer='AAAAAA')


def start_login(client):
    body = credentials(client)
    with patch.object(auth, 'send_login_otp_email', return_value='test-message') as mail:
        response = client.post('/auth/login', json=body)
    assert response.status_code == 200, response.text
    assert 'access_token' not in response.json()
    assert 'code' not in response.json()
    return response.json()['challenge_id'], mail.call_args.kwargs['code']


def verify(client, challenge, code):
    return client.post('/auth/verify-otp', json={'challenge_id': challenge, 'code': code})


def test_password_only_cannot_authenticate(client):
    assert client.post('/auth/login', json={'email':'test@example.test','password':PASSWORD}).status_code == 422
    assert client.get('/auth/me').status_code == 401


def test_success_token_and_replay(client):
    challenge, code = start_login(client)
    response = verify(client, challenge, code)
    assert response.status_code == 200
    token = response.json()['access_token']
    assert client.get('/auth/me', headers={'Authorization': f'Bearer {token}'}).status_code == 200
    assert verify(client, challenge, code).status_code == 401


def test_three_wrong_attempts_persist(client):
    challenge, code = start_login(client)
    wrong = '000000' if code != '000000' else '999999'
    for _ in range(3):
        assert verify(client, challenge, wrong).status_code == 401
    assert verify(client, challenge, code).status_code == 401
    with connect() as connection:
        assert connection.execute('SELECT failed_attempts FROM login_otps').fetchone()[0] == 3


def test_expired_and_unsent_codes(client):
    with connect() as connection:
        challenge = create_login_challenge(connection, user_id=1, email='test@example.test')
    assert verify(client, str(challenge.challenge_id), challenge.code).status_code == 401
    with connect() as connection:
        mark_login_otp_sent(connection, challenge_id=challenge.challenge_id)
        connection.execute("UPDATE login_otps SET created_at=NOW()-INTERVAL '10 minutes', expires_at=NOW()-INTERVAL '1 minute'")
    assert verify(client, str(challenge.challenge_id), challenge.code).status_code == 401


def test_wrong_and_reused_captcha(client):
    body = credentials(client)
    wrong = dict(body, captcha_answer='BBBBBB')
    assert client.post('/auth/login', json=wrong).status_code == 400
    assert client.post('/auth/login', json=body).status_code == 400


def test_captcha_issuance_limit(client):
    for _ in range(30):
        assert client.get('/auth/captcha').status_code == 200
    assert client.get('/auth/captcha').status_code == 429


def test_password_lockout(client):
    for attempt in range(5):
        response = client.post('/auth/login', json=credentials(client, 'wrong'))
        assert response.status_code == (429 if attempt == 4 else 401)
    assert client.post('/auth/login', json=credentials(client)).status_code == 429


def test_email_failure_commits_invalidation_and_cooldown(client):
    body = credentials(client)
    with patch.object(auth, 'send_login_otp_email', side_effect=RuntimeError('private provider detail')):
        response = client.post('/auth/login', json=body)
    assert response.status_code == 503
    assert 'private provider detail' not in response.text
    with connect() as connection:
        row = connection.execute('SELECT invalidated_at, sent_at FROM login_otps').fetchone()
        assert row[0] is not None and row[1] is None
    assert client.post('/auth/login', json=credentials(client)).status_code == 429


def test_resend_invalidates_previous_code(client):
    old, old_code = start_login(client)
    with connect() as connection:
        connection.execute("UPDATE login_otps SET created_at=NOW()-INTERVAL '2 minutes'")
    new, new_code = start_login(client)
    assert old != new
    assert verify(client, old, old_code).status_code == 401
    assert verify(client, new, new_code).status_code == 200


def test_old_wrong_version_and_non_otp_tokens_rejected(client):
    from core.security import SECRET_KEY
    base = {'sub':'1', 'exp':datetime.now(timezone.utc)+timedelta(minutes=10)}
    for claims in [base, dict(base, auth_version=1, amr=['pwd']),
                   dict(base, auth_version=2, amr=['pwd','email_otp'])]:
        token = jwt.encode(claims, SECRET_KEY, algorithm='HS256')
        assert client.get('/auth/me', headers={'Authorization':f'Bearer {token}'}).status_code == 401


def test_deactivated_account_and_version_change(client):
    challenge, code = start_login(client)
    with connect() as connection:
        connection.execute('UPDATE users SET is_active=FALSE')
    assert verify(client, challenge, code).status_code == 401
    token = create_access_token(1, auth_version=1)
    with connect() as connection:
        connection.execute('UPDATE users SET is_active=TRUE, auth_version=2')
    assert client.get('/auth/me', headers={'Authorization':f'Bearer {token}'}).status_code == 401


def test_concurrent_verification_only_one_session(client):
    challenge, code = start_login(client)
    with ThreadPoolExecutor(max_workers=2) as pool:
        codes = list(pool.map(lambda _: verify(client, challenge, code).status_code, range(2)))
    assert sorted(codes) == [200, 401]


def test_password_change_revokes_token_and_pending_code(client):
    challenge, code = start_login(client)
    token = verify(client, challenge, code).json()['access_token']
    with connect() as connection:
        connection.execute("UPDATE login_otps SET created_at=NOW()-INTERVAL '2 minutes'")
    pending, pending_code = start_login(client)
    with patch.object(auth, 'password_error', return_value=None):
        response = client.post('/auth/change-password',
            headers={'Authorization':f'Bearer {token}'},
            json={'current_password':PASSWORD, 'new_password':'Changed-Test-Password!5482'})
    assert response.status_code == 200
    assert client.get('/auth/me', headers={'Authorization':f'Bearer {token}'}).status_code == 401
    assert verify(client, pending, pending_code).status_code == 401
