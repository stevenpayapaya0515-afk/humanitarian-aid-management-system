-- Run as the database owner in aidtrack_db BEFORE starting the updated backend.
-- Existing assessments remain NULL: no fabricated answers or rewritten history.
BEGIN;
ALTER TABLE public.household_assessments ADD COLUMN IF NOT EXISTS roof_material INTEGER CHECK (roof_material IN (1, 2, 3, 4, 5, 6));
ALTER TABLE public.household_assessments ADD COLUMN IF NOT EXISTS wall_material INTEGER CHECK (wall_material IN (1, 2, 3, 4, 5, 6));
ALTER TABLE public.household_assessments ADD COLUMN IF NOT EXISTS electricity INTEGER CHECK (electricity IN (1, 2));
ALTER TABLE public.household_assessments ADD COLUMN IF NOT EXISTS drinking_water_source INTEGER CHECK (drinking_water_source IN (11, 12, 13, 14, 21, 31, 32, 41, 42, 51, 61, 71, 72, 81, 91, 92));
ALTER TABLE public.household_assessments ADD COLUMN IF NOT EXISTS toilet_facility INTEGER CHECK (toilet_facility IN (11, 12, 13, 14, 21, 22, 23, 31, 41, 51, 95));
ALTER TABLE public.household_assessments ADD COLUMN IF NOT EXISTS working_adult_present INTEGER CHECK (working_adult_present IN (0, 1));
ALTER TABLE public.household_assessments ADD COLUMN IF NOT EXISTS apis_single_family BOOLEAN;
ALTER TABLE public.vulnerability_classifications ADD COLUMN IF NOT EXISTS proxy_details JSONB;
-- Locate the existing single-column constraint without relying on truncated names.
DO $$
DECLARE item RECORD;
BEGIN
 FOR item IN SELECT conname FROM pg_constraint
 WHERE conrelid = 'public.vulnerability_classifications'::regclass
 AND contype = 'c'
 AND conkey = ARRAY[(SELECT attnum FROM pg_attribute
 WHERE attrelid = 'public.vulnerability_classifications'::regclass
 AND attname = 'model_training_data_origin')]::smallint[]
 LOOP
  EXECUTE format('ALTER TABLE public.vulnerability_classifications DROP CONSTRAINT %I', item.conname);
 END LOOP;
END $$;
ALTER TABLE public.vulnerability_classifications ADD CONSTRAINT vc_training_origin_check
CHECK (model_training_data_origin IN ('synthetic', 'lgu_authorized', 'psa_apis2019'));
COMMIT;
