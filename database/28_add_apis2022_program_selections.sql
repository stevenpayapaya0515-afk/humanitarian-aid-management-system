-- Store the selected categories separately from the five trained model counts.
-- Existing assessment rows retain their original totals; no category choices
-- are guessed from historical counts. Run once in pgAdmin against aidtrack_db.
BEGIN;
ALTER TABLE public.household_assessments
  ADD COLUMN IF NOT EXISTS apis2022_program_selections JSONB NOT NULL DEFAULT '{}'::jsonb;
COMMIT;
