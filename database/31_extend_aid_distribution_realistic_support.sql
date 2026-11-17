-- AidTrack 31: Broaden reviewed Aid Distribution to non-disaster support.
-- Execute ONCE as database owner in aidtrack_db after backing up.
-- Preserves all existing aid_distributions and practice/real origin labels.
BEGIN;
DO $$ BEGIN
    IF current_database() <> 'aidtrack_db' THEN
        RAISE EXCEPTION 'Select aidtrack_db before applying this migration';
    END IF;
    IF to_regclass('public.aid_distributions') IS NULL THEN
        RAISE EXCEPTION 'aid_distributions does not exist; apply migrations 10 and 19 first';
    END IF;
END $$;

ALTER TABLE public.aid_distributions
    ADD COLUMN IF NOT EXISTS amount_php NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS assistance_purpose VARCHAR(250) NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS source_agency VARCHAR(120) NOT NULL DEFAULT '';

ALTER TABLE public.aid_distributions
    DROP CONSTRAINT IF EXISTS aid_distributions_aid_type_check;
ALTER TABLE public.aid_distributions
    ADD CONSTRAINT aid_distributions_aid_type_check CHECK (aid_type IN (
        'Food Packs','Drinking Water','Hygiene Kits','Clothing','Blankets',
        'Medical Supplies','School Supplies','Shelter Materials','Livelihood Kits',
        'Medical Assistance','Educational Assistance','Burial Assistance',
        'Transportation Assistance','Cash Relief','Livelihood Assistance','Other'
    ));

ALTER TABLE public.aid_distributions
    DROP CONSTRAINT IF EXISTS aid_distributions_unit_check;
ALTER TABLE public.aid_distributions
    ADD CONSTRAINT aid_distributions_unit_check CHECK (unit IN (
        'packs','pieces','liters','kilograms','boxes','sets','grants'
    ));

ALTER TABLE public.aid_distributions
    DROP CONSTRAINT IF EXISTS distribution_financial_shape_check;
ALTER TABLE public.aid_distributions
    ADD CONSTRAINT distribution_financial_shape_check CHECK (
        (aid_type IN (
            'Medical Assistance','Educational Assistance','Burial Assistance',
            'Transportation Assistance','Cash Relief','Livelihood Assistance'
        ) AND quantity = 1 AND unit = 'grants' AND amount_php IS NOT NULL AND amount_php > 0)
        OR
        (aid_type NOT IN (
            'Medical Assistance','Educational Assistance','Burial Assistance',
            'Transportation Assistance','Cash Relief','Livelihood Assistance'
        ) AND unit <> 'grants' AND amount_php IS NULL)
    );

COMMIT;
