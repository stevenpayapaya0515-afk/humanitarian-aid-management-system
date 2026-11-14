-- Run as database owner in aidtrack_db with the backend stopped.
-- Keeps all earlier simulation rows. Does not convert test data into deliveries.
BEGIN;
DO $$ BEGIN
 IF current_database() <> 'aidtrack_db' THEN
  RAISE EXCEPTION 'Select aidtrack_db before running this migration';
 END IF;
END $$;
ALTER TABLE public.aid_distributions
 ADD COLUMN IF NOT EXISTS assessment_id INTEGER REFERENCES public.household_assessments(assessment_id),
 ADD COLUMN IF NOT EXISTS classification_id INTEGER REFERENCES public.vulnerability_classifications(classification_id),
 ADD COLUMN IF NOT EXISTS assessment_data_origin VARCHAR(20),
 ADD COLUMN IF NOT EXISTS beneficiary_status_at_distribution VARCHAR(20);
-- Remove the original simulation-only check; replace it with explicit delivery rules.
DO $$ DECLARE item RECORD; BEGIN
 FOR item IN SELECT conname FROM pg_constraint
 WHERE conrelid = 'public.aid_distributions'::regclass AND contype = 'c'
 AND conkey = ARRAY[(SELECT attnum FROM pg_attribute
     WHERE attrelid = 'public.aid_distributions'::regclass
     AND attname = 'is_simulation')]::smallint[]
 LOOP
  EXECUTE format('ALTER TABLE public.aid_distributions DROP CONSTRAINT %I', item.conname);
 END LOOP;
END $$;
ALTER TABLE public.aid_distributions DROP CONSTRAINT IF EXISTS distribution_delivery_source_check;
ALTER TABLE public.aid_distributions ADD CONSTRAINT distribution_delivery_source_check
 CHECK (is_simulation OR (
   assessment_id IS NOT NULL AND classification_id IS NOT NULL
   AND assessment_data_origin IS NOT NULL AND assessment_data_origin = 'lgu_authorized'
   AND beneficiary_status_at_distribution IS NOT NULL AND beneficiary_status_at_distribution = 'Approved'
 ));
ALTER TABLE public.aid_distributions DROP CONSTRAINT IF EXISTS distribution_snapshot_check;
ALTER TABLE public.aid_distributions ADD CONSTRAINT distribution_snapshot_check
 CHECK ((assessment_id IS NULL AND classification_id IS NULL AND assessment_data_origin IS NULL
         AND beneficiary_status_at_distribution IS NULL AND is_simulation)
     OR (assessment_id IS NOT NULL AND classification_id IS NOT NULL
         AND assessment_data_origin IS NOT NULL AND assessment_data_origin IN ('synthetic','lgu_authorized')
         AND beneficiary_status_at_distribution IS NOT NULL AND beneficiary_status_at_distribution = 'Approved'));
-- Leave the default TRUE: older clients cannot accidentally record a real delivery.
COMMIT;
