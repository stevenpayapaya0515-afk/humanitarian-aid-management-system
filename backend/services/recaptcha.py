"""Verify web reCAPTCHA v2 tokens on the server; never trust the checkbox alone."""
import os
import logging
from services.network_deadline import call_with_deadline, ProviderTimeout, ProviderBusy
logger = logging.getLogger("uvicorn.error")
import requests
from fastapi import HTTPException


def verify_recaptcha(token: str) -> None:
    secret = os.getenv("RECAPTCHA_SECRET_KEY", "").strip()
    hosts = {host.strip().lower() for host in
             os.getenv("RECAPTCHA_ALLOWED_HOSTNAMES", "").split(",") if host.strip()}
    if not secret or not hosts:
        raise HTTPException(503, "Security verification is not configured. Contact your administrator.")
    try:
        response = call_with_deadline("captcha", 10, lambda: requests.post(
            "https://www.google.com/recaptcha/api/siteverify",
            data={"secret": secret, "response": token},
            timeout=(3, 6),
        ))
        response.raise_for_status()
        result = response.json()
    except (requests.RequestException, ValueError, ProviderTimeout, ProviderBusy) as error:
        logger.warning("LOGIN captcha unavailable: %s", type(error).__name__)
        raise HTTPException(503, "Security verification is unavailable. Please try again.") from None
    
    if not isinstance(result, dict):
        raise HTTPException(503, "Security verification is unavailable. Please try again.")

    if result.get("success") is not True:
        errors = result.get("error-codes", [])
        known = {"missing-input-secret", "invalid-input-secret", "missing-input-response",
                 "invalid-input-response", "bad-request", "timeout-or-duplicate"}
        codes = [code for code in errors if isinstance(code, str) and code in known] if isinstance(errors, list) else []
        logger.warning("LOGIN captcha rejected: codes=%s", codes)
        if any(code in codes for code in ("missing-input-secret", "invalid-input-secret")):
            raise HTTPException(503, "Server reCAPTCHA secret is invalid. Contact your administrator.")
        raise HTTPException(400, "reCAPTCHA expired or was rejected. Please check it again.")
    if str(result.get("hostname", "")).lower() not in hosts:
        logger.warning("LOGIN captcha hostname mismatch (check RECAPTCHA_ALLOWED_HOSTNAMES)")
        raise HTTPException(400, "This website hostname is not allowed by the server CAPTCHA settings.")
    logger.info("LOGIN captcha passed")
