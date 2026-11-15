-- Migration 23: Add optional social protection context to EXISTING assessments.
-- No extra assessment table. Existing rows and classifications are untouched.
-- Run as database owner in aidtrack_db, AFTER migration 22.
-- These fields are LGU context, NOT raw PSA APIS PUF codes or model predictors.
BEGIN;
DO $$ BEGIN
    IF current_database() <> 'aidtrack_db' THEN
        RAISE EXCEPTION 'Select aidtrack_db before running migration 23';
    END IF;
END $$;

ALTER TABLE public.household_assessments
    ADD COLUMN IF NOT EXISTS social_insurance VARCHAR(15),
    ADD COLUMN IF NOT EXISTS social_assistance VARCHAR(15),
    ADD COLUMN IF NOT EXISTS labor_market_support VARCHAR(15),
    ADD COLUMN IF NOT EXISTS government_feeding VARCHAR(15),
    ADD COLUMN IF NOT EXISTS philhealth_coverage VARCHAR(15),
    ADD COLUMN IF NOT EXISTS government_services_access VARCHAR(15),
    ADD COLUMN IF NOT EXISTS social_protection_updated_by INTEGER REFERENCES public.users(user_id),
    ADD COLUMN IF NOT EXISTS social_protection_updated_at TIMESTAMPTZ;

ALTER TABLE public.household_assessments
    DROP CONSTRAINT IF EXISTS household_social_insurance_status_check,
    DROP CONSTRAINT IF EXISTS household_social_assistance_status_check,
    DROP CONSTRAINT IF EXISTS household_labor_support_status_check,
    DROP CONSTRAINT IF EXISTS household_feeding_status_check,
    DROP CONSTRAINT IF EXISTS household_philhealth_status_check,
    DROP CONSTRAINT IF EXISTS household_gov_services_status_check;

ALTER TABLE public.household_assessments
    ADD CONSTRAINT household_social_insurance_status_check CHECK (social_insurance IN ('yes','no','unknown','not_assessed')),
    ADD CONSTRAINT household_social_assistance_status_check CHECK (social_assistance IN ('yes','no','unknown','not_assessed')),
    ADD CONSTRAINT household_labor_support_status_check CHECK (labor_market_support IN ('yes','no','unknown','not_assessed')),
    ADD CONSTRAINT household_feeding_status_check CHECK (government_feeding IN ('yes','no','unknown','not_assessed')),
    ADD CONSTRAINT household_philhealth_status_check CHECK (philhealth_coverage IN ('yes','no','unknown','not_assessed')),
    ADD CONSTRAINT household_gov_services_status_check CHECK (government_services_access IN ('yes','no','unknown','not_assessed'));
COMMIT;
