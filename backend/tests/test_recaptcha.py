import os
import sys
from pathlib import Path
from unittest.mock import Mock, patch
import pytest
import requests
from fastapi import HTTPException
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from services.recaptcha import verify_recaptcha

@pytest.fixture(autouse=True)
def configuration(monkeypatch):
    monkeypatch.setenv('RECAPTCHA_SECRET_KEY', 'private-test-secret')
    monkeypatch.setenv('RECAPTCHA_ALLOWED_HOSTNAMES', 'localhost')

def test_verified_hostname():
    response = Mock()
    response.json.return_value = {'success': True, 'hostname': 'localhost'}
    with patch('services.recaptcha.requests.post', return_value=response) as post:
        verify_recaptcha('valid-token')
        assert post.call_args.kwargs['data']['response'] == 'valid-token'
        assert post.call_args.kwargs['timeout'] == (5, 10)

@pytest.mark.parametrize('result', [
    {'success': False, 'error-codes': ['timeout-or-duplicate']},
    {'success': True, 'hostname': 'attacker.example'},
    {'success': True}, {'success': 'true', 'hostname': 'localhost'},
])
def test_rejected_tokens(result):
    response = Mock()
    response.json.return_value = result
    with patch('services.recaptcha.requests.post', return_value=response):
        with pytest.raises(HTTPException) as error:
            verify_recaptcha('invalid-token')
        assert error.value.status_code == 400

@pytest.mark.parametrize('failure', [requests.Timeout(), requests.ConnectionError()])
def test_network_failure_closed(failure):
    with patch('services.recaptcha.requests.post', side_effect=failure):
        with pytest.raises(HTTPException) as error:
            verify_recaptcha('token')
        assert error.value.status_code == 503

@pytest.mark.parametrize('result', [[], None, 'bad response'])
def test_malformed_response_closed(result):
    response = Mock()
    response.json.return_value = result
    with patch('services.recaptcha.requests.post', return_value=response):
        with pytest.raises(HTTPException) as error:
            verify_recaptcha('token')
        assert error.value.status_code == 503

@pytest.mark.parametrize('name', ['RECAPTCHA_SECRET_KEY', 'RECAPTCHA_ALLOWED_HOSTNAMES'])
def test_missing_configuration_closed(monkeypatch, name):
    monkeypatch.delenv(name)
    with patch('services.recaptcha.requests.post') as post:
        with pytest.raises(HTTPException) as error:
            verify_recaptcha('token')
        assert error.value.status_code == 503
        post.assert_not_called()
