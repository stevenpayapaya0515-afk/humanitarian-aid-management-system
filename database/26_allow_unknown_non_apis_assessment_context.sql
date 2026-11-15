-- Preserve unknown legacy context for APIS 2022-only assessment entry.
-- Apply after migration 25. Existing data is unchanged.
BEGIN;
ALTER TABLE public.household_assessments
    ALTER COLUMN pwd_count DROP NOT NULL,
    ALTER COLUMN previous_humanitarian_assistance DROP NOT NULL,
    ALTER COLUMN disaster_affected DROP NOT NULL,
    ALTER COLUMN housing_damage_level DROP NOT NULL,
    ALTER COLUMN displaced DROP NOT NULL;
COMMIT;
