-- AidTrack · Admin-invited Staff registration (run ONCE in aidtrack_db as postgres)
-- This is additive: existing Staff, users, and aid/ML tables remain unchanged.
BEGIN;

DO $$
BEGIN
    IF current_database() <> 'aidtrack_db' THEN
        RAISE EXCEPTION 'Connect to aidtrack_db before running migration 15.';
    END IF;
    IF current_user = 'aidtrack_app' THEN
        RAISE EXCEPTION 'Run this migration as postgres, not aidtrack_app.';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.staff_invitations (
    invitation_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invited_email VARCHAR(254) NOT NULL,
    token_sha256 CHAR(64) NOT NULL UNIQUE
        CHECK (token_sha256 ~ '^[0-9a-f]{64}$'),
    invited_by INTEGER REFERENCES public.users(user_id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    sent_at TIMESTAMPTZ,
    accepted_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    CHECK (expires_at > created_at),
    CHECK (NOT (accepted_at IS NOT NULL AND revoked_at IS NOT NULL))
);

-- Only one pending invitation for an email. Reinviting revokes the previous one.
CREATE UNIQUE INDEX IF NOT EXISTS uq_staff_invitation_pending_email
ON public.staff_invitations (lower(invited_email))
WHERE accepted_at IS NULL AND revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_staff_invitations_email_created
ON public.staff_invitations (lower(invited_email), created_at DESC);

GRANT SELECT, INSERT, UPDATE ON public.staff_invitations TO aidtrack_app;
GRANT USAGE, SELECT ON SEQUENCE public.staff_invitations_invitation_id_seq TO aidtrack_app;

COMMIT;
