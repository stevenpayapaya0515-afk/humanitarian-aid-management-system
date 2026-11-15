-- Migration 27: APIS 2022 71-feature research-assessment input storage.
-- Apply AFTER migration 26. No additional tables, no dataset imports.
-- Existing rows remain unchanged; unrecorded answers are never backfilled.
BEGIN;
DO $$ BEGIN
    IF current_database() <> 'aidtrack_db' THEN
        RAISE EXCEPTION 'Select aidtrack_db before migration 27';
    END IF;
END $$;
ALTER TABLE public.household_assessments
  ADD COLUMN IF NOT EXISTS apis2022_extended_answers JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS apis2022_social_answers JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.household_assessments
  DROP CONSTRAINT IF EXISTS apis2022_extended_is_object,
  DROP CONSTRAINT IF EXISTS apis2022_social_is_object;
ALTER TABLE public.household_assessments
  ADD CONSTRAINT apis2022_extended_is_object CHECK (jsonb_typeof(apis2022_extended_answers) = 'object'),
  ADD CONSTRAINT apis2022_social_is_object CHECK (jsonb_typeof(apis2022_social_answers) = 'object');
COMMIT;
