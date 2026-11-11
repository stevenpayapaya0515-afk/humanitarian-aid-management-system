-- AidTrack · Login Security Phase 1
-- Run in aidtrack_db as the database administrator (not aidtrack_app).
-- PostgreSQL 13+; does not alter existing rows or application features.
BEGIN;

DO $$
BEGIN
    IF current_database() <> 'aidtrack_db' THEN
        RAISE EXCEPTION 'Wrong database: connect to aidtrack_db before running migration 11.';
    END IF;
    IF current_user = 'aidtrack_app' THEN
        RAISE EXCEPTION 'Run migrations as a database administrator, not aidtrack_app.';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.login_otps (
    otp_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- FastAPI will generate a random UUID for each pending login challenge.
    challenge_id UUID NOT NULL UNIQUE,
    user_id INTEGER NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    purpose VARCHAR(20) NOT NULL DEFAULT 'login'
        CHECK (purpose = 'login'),
    -- HMAC-SHA256 of the six-digit OTP, keyed with a private server secret.
    -- Do not store the plaintext OTP or an ordinary unsalted SHA-256 of it.
    otp_hmac_sha256 CHAR(64) NOT NULL
        CHECK (otp_hmac_sha256 ~ '^[0-9a-f]{64}$'),
    sent_to_email VARCHAR(254) NOT NULL,
    requested_ip INET,
    failed_attempts SMALLINT NOT NULL DEFAULT 0
        CHECK (failed_attempts BETWEEN 0 AND 3),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    invalidated_at TIMESTAMPTZ,
    CHECK (expires_at > created_at),
    CHECK (consumed_at IS NULL OR invalidated_at IS NULL)
);

-- Prevent concurrent valid pending challenges for a single account.
-- FastAPI must invalidate an older challenge before resending an OTP,
-- including when a previous challenge has expired.
CREATE UNIQUE INDEX IF NOT EXISTS uq_login_otps_one_pending
ON public.login_otps (user_id)
WHERE purpose = 'login'
  AND consumed_at IS NULL
  AND invalidated_at IS NULL;

-- FastAPI can count OTP sends in the last 15 minutes for rate limiting.
CREATE INDEX IF NOT EXISTS idx_login_otps_user_created
ON public.login_otps (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_login_otps_expiry
ON public.login_otps (expires_at);

GRANT SELECT, INSERT, UPDATE
ON TABLE public.login_otps TO aidtrack_app;
GRANT USAGE, SELECT
ON SEQUENCE public.login_otps_otp_id_seq TO aidtrack_app;

COMMIT;
