-- AidTrack migration 22: The prior synthetic-era socioeconomic form fields
-- are retained as nullable historical fields, but new household assessments
-- no longer require or populate them. Existing rows are untouched.
-- Run after migration 21, against the correct AidTrack PostgreSQL database.
BEGIN;
ALTER TABLE public.household_assessments
    ALTER COLUMN monthly_income_range DROP NOT NULL,
    ALTER COLUMN employment_status DROP NOT NULL,
    ALTER COLUMN livelihood_type DROP NOT NULL,
    ALTER COLUMN beneficiary_status DROP NOT NULL;
COMMIT;
