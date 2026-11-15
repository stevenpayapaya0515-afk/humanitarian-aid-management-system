-- Run after migration 23 as the database owner.
BEGIN;
ALTER TABLE public.vulnerability_classifications
    DROP CONSTRAINT IF EXISTS vc_training_origin_check;
ALTER TABLE public.vulnerability_classifications
    ADD CONSTRAINT vc_training_origin_check CHECK (
        model_training_data_origin IN (
            'synthetic', 'lgu_authorized', 'psa_apis2019', 'psa_apis2022'
        )
    );
COMMIT;
