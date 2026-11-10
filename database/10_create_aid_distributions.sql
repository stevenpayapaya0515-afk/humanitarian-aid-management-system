
-- AidTrack: Aid Distribution Simulation
-- Run after 09_create_beneficiaries.sql.
-- Development/testing only. Not evidence of real aid delivery.

CREATE TABLE IF NOT EXISTS public.aid_distributions (
    distribution_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    beneficiary_id INTEGER NOT NULL
        REFERENCES public.beneficiaries(beneficiary_id),

    aid_type VARCHAR(40) NOT NULL
        CHECK (aid_type IN (
            'Food Packs',
            'Drinking Water',
            'Hygiene Kits',
            'Clothing',
            'Blankets',
            'Medical Supplies',
            'Other'
        )),

    quantity INTEGER NOT NULL
        CHECK (quantity >= 1 AND quantity <= 100000),

    unit VARCHAR(20) NOT NULL
        CHECK (unit IN (
            'packs',
            'pieces',
            'liters',
            'kilograms',
            'boxes',
            'sets'
        )),

    distribution_date DATE NOT NULL,

    batch_code VARCHAR(32) NOT NULL
        CHECK (batch_code ~ '^[A-Z0-9][A-Z0-9_-]*$'),

    notes TEXT NOT NULL DEFAULT ''
        CHECK (char_length(notes) <= 500),

    -- Safety: this version cannot store an official delivery.
    is_simulation BOOLEAN NOT NULL DEFAULT TRUE
        CHECK (is_simulation = TRUE),

    recorded_by INTEGER NOT NULL
        REFERENCES public.users(user_id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- One type of aid per beneficiary per distribution batch.
    CONSTRAINT unique_aid_distribution_entry
        UNIQUE (beneficiary_id, batch_code, aid_type)
);

CREATE INDEX IF NOT EXISTS idx_aid_distribution_beneficiary
ON public.aid_distributions(beneficiary_id);

CREATE INDEX IF NOT EXISTS idx_aid_distribution_date
ON public.aid_distributions(distribution_date);

GRANT SELECT, INSERT
ON TABLE public.aid_distributions
TO aidtrack_app;

GRANT USAGE, SELECT
ON SEQUENCE public.aid_distributions_distribution_id_seq
TO aidtrack_app;
