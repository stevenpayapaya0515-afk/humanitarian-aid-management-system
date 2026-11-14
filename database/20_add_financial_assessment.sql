-- Run on your AidTrack database as its owner before starting the updated backend.
-- Optional columns: existing assessments remain NULL and retain their history.
BEGIN;
ALTER TABLE public.household_assessments
    ADD COLUMN IF NOT EXISTS financial_reference_year INTEGER,
    ADD COLUMN IF NOT EXISTS financial_single_family BOOLEAN,
    ADD COLUMN IF NOT EXISTS average_family_size NUMERIC(7,2),
    ADD COLUMN IF NOT EXISTS annual_family_income NUMERIC(14,2),
    ADD COLUMN IF NOT EXISTS annual_family_expenditure NUMERIC(14,2),
    ADD COLUMN IF NOT EXISTS annual_food_expenditure NUMERIC(14,2);
ALTER TABLE public.household_assessments
    DROP CONSTRAINT IF EXISTS assessment_financial_history_check;
ALTER TABLE public.household_assessments
    ADD CONSTRAINT assessment_financial_history_check CHECK (
        (financial_reference_year IS NULL AND financial_single_family IS NULL
         AND average_family_size IS NULL AND annual_family_income IS NULL
         AND annual_family_expenditure IS NULL AND annual_food_expenditure IS NULL)
        OR
        (financial_reference_year IS NOT NULL AND financial_reference_year >= 1900
         AND financial_reference_year < EXTRACT(YEAR FROM assessment_date)
         AND financial_single_family IS TRUE
         AND average_family_size IS NOT NULL AND average_family_size >= 1
         AND average_family_size <> 'NaN'::numeric
         AND (annual_family_income IS NOT NULL OR annual_family_expenditure IS NOT NULL OR annual_food_expenditure IS NOT NULL)
         AND (annual_family_income IS NULL OR annual_family_income <> 'NaN'::numeric)
         AND (annual_family_expenditure IS NULL OR (annual_family_expenditure >= 0 AND annual_family_expenditure <> 'NaN'::numeric))
         AND (annual_food_expenditure IS NULL OR (annual_food_expenditure >= 0 AND annual_food_expenditure <> 'NaN'::numeric))
         AND (annual_food_expenditure IS NULL OR annual_family_expenditure IS NULL OR annual_food_expenditure <= annual_family_expenditure))
    );
COMMIT;
