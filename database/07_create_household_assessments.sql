-- AidTrack: assessment records linked to existing household registration.
-- DEVELOPMENT DATABASE FIRST: inspect before executing; backup existing data.
-- Do not treat any synthetic label as an LGU-verified vulnerability class.

CREATE TABLE IF NOT EXISTS public.household_assessments (
    assessment_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    household_id INTEGER NOT NULL REFERENCES public.households(household_id),
    assessment_date DATE NOT NULL,
    age_0_5_count INTEGER NOT NULL CHECK (age_0_5_count >= 0),
    age_6_17_count INTEGER NOT NULL CHECK (age_6_17_count >= 0),
    age_18_59_count INTEGER NOT NULL CHECK (age_18_59_count >= 0),
    age_60_plus_count INTEGER NOT NULL CHECK (age_60_plus_count >= 0),
    senior_citizens_count INTEGER NOT NULL CHECK (senior_citizens_count >= 0),
    pwd_count INTEGER NOT NULL CHECK (pwd_count >= 0),
    monthly_income_range VARCHAR(30) NOT NULL,
    employment_status VARCHAR(40) NOT NULL,
    livelihood_type VARCHAR(50) NOT NULL,
    previous_humanitarian_assistance BOOLEAN NOT NULL,
    beneficiary_status VARCHAR(30) NOT NULL,
    disaster_affected BOOLEAN NOT NULL,
    housing_damage_level VARCHAR(15) NOT NULL
        CHECK (housing_damage_level IN ('None', 'Minor', 'Major', 'Destroyed')),
    displaced BOOLEAN NOT NULL,
    data_origin VARCHAR(20) NOT NULL DEFAULT 'synthetic'
        CHECK (data_origin IN ('synthetic', 'lgu_authorized')),
    recorded_by INTEGER NOT NULL REFERENCES public.users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (household_id, assessment_date),
    CHECK (senior_citizens_count = age_60_plus_count),
    CHECK (pwd_count <= (age_0_5_count + age_6_17_count +
                        age_18_59_count + age_60_plus_count)),
    CHECK ((age_0_5_count + age_6_17_count +
            age_18_59_count + age_60_plus_count) >= 1)
);

CREATE INDEX IF NOT EXISTS idx_assessments_household_id
ON public.household_assessments (household_id);

GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.household_assessments TO aidtrack_app;
GRANT USAGE, SELECT
ON SEQUENCE public.household_assessments_assessment_id_seq TO aidtrack_app;

-- Cross-table check that age counts sum to households.household_size
-- is performed in FastAPI when the assessment is created.
-- This starter does NOT implement model inference or bulk import.
