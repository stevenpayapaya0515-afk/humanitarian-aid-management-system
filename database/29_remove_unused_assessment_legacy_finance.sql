-- AidTrack migration 29: remove unused legacy socioeconomic and annual finance fields.
-- Generated against the reviewed 2026-11-15 AidTrack source tree.
-- This is IRREVERSIBLE without a verified backup. Requires updated backend/frontend deployed.
-- Run only on aidtrack_db, with the AidTrack backend stopped and after a fresh backup.
-- STOP if this migration raises an exception; it automatically rolls back.
-- The current APIS 2022 49-feature model and its monthly income field stay unchanged.
BEGIN;

-- Fail closed if accidentally run against another database.
DO $$
BEGIN
  IF current_database() <> 'aidtrack_db' THEN
    RAISE EXCEPTION 'Wrong database: expected aidtrack_db, got %', current_database();
  END IF;
END $$;

LOCK TABLE public.household_assessments IN ACCESS EXCLUSIVE MODE;

-- Previous two-row data audit found 11 candidate fields empty. This rechecks
-- ALL 16 affected fields (including five other finance columns) at execution.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.household_assessments
    WHERE monthly_income_range IS NOT NULL
           OR employment_status IS NOT NULL
           OR livelihood_type IS NOT NULL
           OR previous_humanitarian_assistance IS NOT NULL
           OR housing_damage_level IS NOT NULL
           OR financial_reference_year IS NOT NULL
           OR financial_single_family IS NOT NULL
           OR average_family_size IS NOT NULL
           OR annual_family_income IS NOT NULL
           OR annual_family_expenditure IS NOT NULL
           OR annual_food_expenditure IS NOT NULL
           OR financial_residence_classification IS NOT NULL
           OR annual_housing_utilities_expenditure IS NOT NULL
           OR annual_health_expenditure IS NOT NULL
           OR annual_education_expenditure IS NOT NULL
           OR annual_transport_expenditure IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Migration 29 aborted: at least one affected legacy/finance column contains data; no changes applied.';
  END IF;
END $$;

-- Only the two known optional-finance checks need removal.
-- No CASCADE: unknown dependent views/functions cause an error and rollback.
ALTER TABLE public.household_assessments
    DROP CONSTRAINT IF EXISTS assessment_financial_history_check,
    DROP CONSTRAINT IF EXISTS assessment_detailed_finance_check;

ALTER TABLE public.household_assessments
    DROP COLUMN monthly_income_range,
    DROP COLUMN employment_status,
    DROP COLUMN livelihood_type,
    DROP COLUMN previous_humanitarian_assistance,
    DROP COLUMN housing_damage_level,
    DROP COLUMN financial_reference_year,
    DROP COLUMN financial_single_family,
    DROP COLUMN average_family_size,
    DROP COLUMN annual_family_income,
    DROP COLUMN annual_family_expenditure,
    DROP COLUMN annual_food_expenditure,
    DROP COLUMN financial_residence_classification,
    DROP COLUMN annual_housing_utilities_expenditure,
    DROP COLUMN annual_health_expenditure,
    DROP COLUMN annual_education_expenditure,
    DROP COLUMN annual_transport_expenditure;

COMMIT;

-- Read-only post-check: 46 expected columns after removing 16 from 62.
SELECT COUNT(*) AS assessment_columns_after_cleanup
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'household_assessments';
SELECT COUNT(*) AS assessments_preserved FROM public.household_assessments;
SELECT COUNT(*) AS classifications_preserved FROM public.vulnerability_classifications;
