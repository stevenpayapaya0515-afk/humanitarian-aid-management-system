-- AidTrack APIS 2022 assessment inputs; run after migrations 23 and 24.
-- Preserve historical assessments; never fill unknown survey answers automatically.
BEGIN;
ALTER TABLE public.household_assessments
  ADD COLUMN IF NOT EXISTS apis2022_i2 INTEGER CHECK (apis2022_i2 IN (1,2,3,4,5,6,7)),
  ADD COLUMN IF NOT EXISTS apis2022_i3 INTEGER CHECK (apis2022_i3 IN (1,2,3,4,5,6,7,8,10)),
  ADD COLUMN IF NOT EXISTS apis2022_i4 INTEGER CHECK (apis2022_i4 IN (1,2,3,4,5,6)),
  ADD COLUMN IF NOT EXISTS apis2022_i8 INTEGER CHECK (apis2022_i8 IN (1,2)),
  ADD COLUMN IF NOT EXISTS apis2022_ws1 INTEGER CHECK (apis2022_ws1 IN (11,12,13,14,21,31,32,41,42,51,61,71,72,81,91)),
  ADD COLUMN IF NOT EXISTS apis2022_ws11a INTEGER CHECK (apis2022_ws11a IN (11,12,13,14,21,22,23,31,41,51,95)),
  ADD COLUMN IF NOT EXISTS apis2022_g15_kit INTEGER CHECK (apis2022_g15_kit IN (1,2)),
  ADD COLUMN IF NOT EXISTS apis2022_g16_nat_disas INTEGER CHECK (apis2022_g16_nat_disas IN (1,2)),
  ADD COLUMN IF NOT EXISTS apis2022_g16a_evac INTEGER CHECK (apis2022_g16a_evac IN (1,2)),
  ADD COLUMN IF NOT EXISTS apis2022_g16b_recov INTEGER CHECK (apis2022_g16b_recov IN (1,2)),
  ADD COLUMN IF NOT EXISTS apis2022_mem_age_6_11 INTEGER CHECK (apis2022_mem_age_6_11 >= 0),
  ADD COLUMN IF NOT EXISTS apis2022_mem_age_12_17 INTEGER CHECK (apis2022_mem_age_12_17 >= 0),
  ADD COLUMN IF NOT EXISTS apis2022_monthly_household_income_php NUMERIC(14,2);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid = 'public.household_assessments'::regclass
      AND conname = 'household_apis2022_age_split_check') THEN
    ALTER TABLE public.household_assessments
      ADD CONSTRAINT household_apis2022_age_split_check CHECK (
        apis2022_mem_age_6_11 IS NULL OR apis2022_mem_age_12_17 IS NULL OR
        (apis2022_mem_age_6_11 >= 0 AND apis2022_mem_age_12_17 >= 0 AND
         apis2022_mem_age_6_11 + apis2022_mem_age_12_17 = age_6_17_count)
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
      WHERE conrelid = 'public.household_assessments'::regclass
      AND conname = 'household_apis2022_income_check') THEN
    ALTER TABLE public.household_assessments
      ADD CONSTRAINT household_apis2022_income_check CHECK (
        apis2022_monthly_household_income_php IS NULL OR
        apis2022_monthly_household_income_php >= 0
      );
  END IF;
END $$;
COMMIT;
