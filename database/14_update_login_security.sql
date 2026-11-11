-- AidTrack · Login Security Phase 1
-- Minimal changes to the EXISTING users table.
-- Do NOT DROP or recreate users; existing accounts and passwords remain.
-- Run in aidtrack_db as the database administrator (not aidtrack_app).
BEGIN;

DO $$
BEGIN
    IF current_database() <> 'aidtrack_db' THEN
        RAISE EXCEPTION 'Wrong database: connect to aidtrack_db before running migration 14.';
    END IF;
    IF current_user = 'aidtrack_app' THEN
        RAISE EXCEPTION 'Run migrations as a database administrator, not aidtrack_app.';
    END IF;
END $$;

-- Existing failed_login_attempts / locked_until are preserved.
-- FastAPI will increment this tier during progressive lockouts.
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS login_lockout_tier SMALLINT NOT NULL DEFAULT 0
    CHECK (login_lockout_tier BETWEEN 0 AND 3);

-- Future OTP-verified JWTs will carry this version; the API will reject
-- old tokens without a matching version when 2-step login goes live.
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS auth_version INTEGER NOT NULL DEFAULT 1
    CHECK (auth_version >= 1);

COMMIT;
