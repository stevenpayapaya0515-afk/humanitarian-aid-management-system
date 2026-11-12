-- Run once in aidtrack_db as the database administrator, after migrations 11–16.
-- New concept: the backend uses a transaction advisory lock to serialize
-- CAPTCHA issuance for one IP across multiple API workers.
BEGIN;
DO $$
BEGIN
    IF current_database() <> 'aidtrack_db' OR current_user = 'aidtrack_app' THEN
        RAISE EXCEPTION 'Run migration 17 in aidtrack_db as the database administrator.';
    END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.login_captchas (
    challenge_id UUID PRIMARY KEY,
    answer_hmac CHAR(64) NOT NULL,
    requested_ip INET NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_login_captchas_ip_created
    ON public.login_captchas(requested_ip, created_at);
GRANT SELECT, INSERT, UPDATE ON public.login_captchas TO aidtrack_app;
COMMIT;
-- Maintenance as administrator: periodically delete CAPTCHA rows older than
-- one day. Never delete the last 15 minutes; they enforce issuance limits.
