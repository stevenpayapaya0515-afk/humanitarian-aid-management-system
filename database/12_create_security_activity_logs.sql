-- AidTrack · Login Security Phase 1
-- Security audit logs are append-only for the FastAPI application role.
-- Run in aidtrack_db as the database administrator (not aidtrack_app).
BEGIN;

DO $$
BEGIN
    IF current_database() <> 'aidtrack_db' THEN
        RAISE EXCEPTION 'Wrong database: connect to aidtrack_db before running migration 12.';
    END IF;
    IF current_user = 'aidtrack_app' THEN
        RAISE EXCEPTION 'Run migrations as a database administrator, not aidtrack_app.';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.security_activity_logs (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Examples: LOGIN_FAILED, OTP_SENT, OTP_FAILED, LOGIN_SUCCESS,
    -- LOCKOUT_TIER_1, IP_BLOCKED, ALERT_EMAIL_SENT.
    event_type VARCHAR(64) NOT NULL
        CHECK (event_type ~ '^[A-Z][A-Z0-9_]{2,63}$'),
    -- Stores email attempted at login, even if no account exists.
    -- Deliberately not a foreign key: a removed staff account must NOT
    -- erase or modify historical security events.
    email_typed TEXT,
    user_id INTEGER,
    ip_address INET,
    user_agent TEXT,
    -- Structured, non-secret metadata only. NEVER store passwords,
    -- OTPs, bearer tokens, CAPTCHA responses or API keys here.
    details JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(details) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_security_events_recent
ON public.security_activity_logs (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_security_events_type_time
ON public.security_activity_logs (event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_security_events_ip_time
ON public.security_activity_logs (ip_address, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_security_events_email_time
ON public.security_activity_logs (email_typed, created_at DESC);

-- Do not grant UPDATE or DELETE to aidtrack_app: security events remain
-- append-only when the backend uses this dedicated non-owner role.
GRANT SELECT, INSERT
ON TABLE public.security_activity_logs TO aidtrack_app;
REVOKE UPDATE, DELETE, TRUNCATE
ON TABLE public.security_activity_logs FROM aidtrack_app;
GRANT USAGE, SELECT
ON SEQUENCE public.security_activity_logs_event_id_seq TO aidtrack_app;

COMMIT;
