-- AidTrack 32: Immutable correction audit for previously saved aid transactions.
-- Back up aidtrack_db first. Execute as database owner, AFTER migration 31.
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'aidtrack_db' THEN
    RAISE EXCEPTION 'Select aidtrack_db before running migration 32';
  END IF;
  IF to_regclass('public.aid_distributions') IS NULL THEN
    RAISE EXCEPTION 'Missing aid_distributions table; apply earlier migrations first';
  END IF;
END $$;

ALTER TABLE public.aid_distributions
  ADD COLUMN IF NOT EXISTS revision INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE public.aid_distributions
  DROP CONSTRAINT IF EXISTS aid_distribution_revision_positive;
ALTER TABLE public.aid_distributions
  ADD CONSTRAINT aid_distribution_revision_positive CHECK (revision >= 1);

CREATE TABLE IF NOT EXISTS public.aid_distribution_corrections (
  correction_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  distribution_id INTEGER NOT NULL
    REFERENCES public.aid_distributions(distribution_id) ON DELETE RESTRICT,
  revision_before INTEGER NOT NULL CHECK (revision_before >= 1),
  revision_after INTEGER NOT NULL CHECK (revision_after > 1),
  old_values JSONB NOT NULL,
  new_values JSONB NOT NULL,
  correction_reason VARCHAR(500) NOT NULL
    CHECK (char_length(btrim(correction_reason)) >= 10),
  changed_by INTEGER NOT NULL REFERENCES public.users(user_id),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT aid_distribution_correction_revision_check
    CHECK (revision_after = revision_before + 1),
  CONSTRAINT aid_distribution_correction_version_unique
    UNIQUE (distribution_id, revision_after)
);
CREATE INDEX IF NOT EXISTS idx_aid_distribution_corrections_distribution
  ON public.aid_distribution_corrections(distribution_id, correction_id DESC);

-- The app user can edit original rows but cannot remove correction audit records.
GRANT SELECT, UPDATE ON public.aid_distributions TO aidtrack_app;
GRANT SELECT, INSERT ON public.aid_distribution_corrections TO aidtrack_app;
GRANT USAGE, SELECT ON SEQUENCE public.aid_distribution_corrections_correction_id_seq TO aidtrack_app;
COMMIT;
