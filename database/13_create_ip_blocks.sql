-- AidTrack · Login Security Phase 1
-- Track temporary IP blocks for repeated failed logins across accounts.
-- Run in aidtrack_db as the database administrator (not aidtrack_app).
BEGIN;

DO $$
BEGIN
    IF current_database() <> 'aidtrack_db' THEN
        RAISE EXCEPTION 'Wrong database: connect to aidtrack_db before running migration 13.';
    END IF;
    IF current_user = 'aidtrack_app' THEN
        RAISE EXCEPTION 'Run migrations as a database administrator, not aidtrack_app.';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.ip_blocks (
    ip_address INET PRIMARY KEY,
    blocked_until TIMESTAMPTZ NOT NULL,
    failures_at_block INTEGER NOT NULL
        CHECK (failures_at_block >= 1),
    reason VARCHAR(100) NOT NULL DEFAULT 'Repeated failed login attempts',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ip_blocks_expires
ON public.ip_blocks (blocked_until);

-- A row is blocked only while blocked_until > NOW().
-- Keeping expired rows makes debugging easier, without requiring deletes.
GRANT SELECT, INSERT, UPDATE
ON TABLE public.ip_blocks TO aidtrack_app;

COMMIT;
