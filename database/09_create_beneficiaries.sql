
-- AidTrack: Beneficiary Management
-- Run in the existing development database after scripts 01-08.
-- Synthetic ML results are not official eligibility decisions.

CREATE TABLE IF NOT EXISTS public.beneficiaries (
    beneficiary_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    household_id INTEGER NOT NULL UNIQUE
        REFERENCES public.households(household_id),

    assessment_id INTEGER NOT NULL
        REFERENCES public.household_assessments(assessment_id),

    classification_id INTEGER NOT NULL
        REFERENCES public.vulnerability_classifications(classification_id),

    status VARCHAR(20) NOT NULL DEFAULT 'Pending'
        CHECK (
            status IN (
                'Pending',
                'For Review',
                'Approved',
                'Rejected'
            )
        ),

    review_notes TEXT NOT NULL DEFAULT ''
        CHECK (char_length(review_notes) <= 1000),

    registered_by INTEGER NOT NULL
        REFERENCES public.users(user_id),

    updated_by INTEGER
        REFERENCES public.users(user_id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_beneficiaries_status
ON public.beneficiaries(status);


-- Keep an audit trail whenever a review status changes.
CREATE TABLE IF NOT EXISTS public.beneficiary_status_history (
    event_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    beneficiary_id INTEGER NOT NULL
        REFERENCES public.beneficiaries(beneficiary_id),

    old_status VARCHAR(20),
    new_status VARCHAR(20) NOT NULL,

    review_notes TEXT NOT NULL DEFAULT '',

    changed_by INTEGER NOT NULL
        REFERENCES public.users(user_id),

    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_beneficiary_history_id
ON public.beneficiary_status_history(
    beneficiary_id,
    changed_at DESC
);


-- Allow the AidTrack backend to access these records.
GRANT SELECT, INSERT, UPDATE
ON TABLE public.beneficiaries TO aidtrack_app;

GRANT SELECT, INSERT
ON TABLE public.beneficiary_status_history TO aidtrack_app;

GRANT USAGE, SELECT
ON SEQUENCE public.beneficiaries_beneficiary_id_seq
TO aidtrack_app;

GRANT USAGE, SELECT
ON SEQUENCE public.beneficiary_status_history_event_id_seq
TO aidtrack_app;
