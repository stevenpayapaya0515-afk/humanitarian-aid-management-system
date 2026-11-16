-- AidTrack Migration 30: normalized household location
-- Run in pgAdmin against aidtrack_db AFTER exporting a backup of
-- public.households (especially household_id and the old address).
-- Existing households are assumed to be under Cabadbaran City LGU.
-- This migration updates ONLY public.households.
-- IMPORTANT: Existing FastAPI/Flutter Household Registration still uses
-- address; update those application layers immediately after this migration.

BEGIN;

ALTER TABLE public.households
    ADD COLUMN IF NOT EXISTS province VARCHAR(100),
    ADD COLUMN IF NOT EXISTS city_municipality VARCHAR(100);

-- Populate newly introduced location fields on existing LGU records.
-- Preserve any location values already entered in these columns.
UPDATE public.households
SET province = COALESCE(NULLIF(BTRIM(province), ''), 'Agusan del Norte'),
    city_municipality = COALESCE(
        NULLIF(BTRIM(city_municipality), ''), 'Cabadbaran City'
    )
WHERE province IS NULL OR BTRIM(province) = ''
   OR city_municipality IS NULL OR BTRIM(city_municipality) = '';

ALTER TABLE public.households
    ALTER COLUMN province SET NOT NULL,
    ALTER COLUMN city_municipality SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.households'::regclass
          AND conname = 'households_province_not_blank_ck'
    ) THEN
        ALTER TABLE public.households
            ADD CONSTRAINT households_province_not_blank_ck
            CHECK (BTRIM(province) <> '');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.households'::regclass
          AND conname = 'households_city_municipality_not_blank_ck'
    ) THEN
        ALTER TABLE public.households
            ADD CONSTRAINT households_city_municipality_not_blank_ck
            CHECK (BTRIM(city_municipality) <> '');
    END IF;
END $$;

-- The staff will enter the four structured fields instead of a separate
-- free-text address. PostgreSQL RESTRICT prevents removal if a dependent
-- view/object references the old column. All changes roll back on failure.
ALTER TABLE public.households
    DROP COLUMN IF EXISTS address RESTRICT;

COMMENT ON COLUMN public.households.province IS
    'Household province; used with city_municipality, barangay, and purok for display.';
COMMENT ON COLUMN public.households.city_municipality IS
    'Household city or municipality; used with the other location fields for display.';

COMMIT;

-- Verification: no rows should have missing location components.
SELECT COUNT(*) AS total_households,
       COUNT(*) FILTER (
           WHERE province IS NULL OR BTRIM(province) = ''
              OR city_municipality IS NULL OR BTRIM(city_municipality) = ''
       ) AS incomplete_location_rows
FROM public.households;

-- Verification: expected location columns exist; 'address' is absent.
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'households'
ORDER BY ordinal_position;
