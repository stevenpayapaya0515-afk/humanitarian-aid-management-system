"""Verify web reCAPTCHA v2 tokens on the server; never trust the checkbox alone."""
import os
import requests
from fastapi import HTTPException


def verify_recaptcha(token: str) -> None:
    secret = os.getenv("RECAPTCHA_SECRET_KEY", "").strip()
    hosts = {host.strip().lower() for host in
             os.getenv("RECAPTCHA_ALLOWED_HOSTNAMES", "").split(",") if host.strip()}
    if not secret or not hosts:
        raise HTTPException(503, "Security verification is not configured. Contact your administrator.")
    try:
        response = requests.post(
            "https://www.google.com/recaptcha/api/siteverify",
            data={"secret": secret, "response": token},
            timeout=(5, 10),
        )
        response.raise_for_status()
        result = response.json()
    except (requests.RequestException, ValueError):
        raise HTTPException(503, "Security verification is unavailable. Please try again.") from None
    if not isinstance(result, dict):
        raise HTTPException(503, "Security verification is unavailable. Please try again.")
    if (result.get("success") is not True or
            str(result.get("hostname", "")).lower() not in hosts):
        raise HTTPException(400, "Please complete the reCAPTCHA checkbox again.")
