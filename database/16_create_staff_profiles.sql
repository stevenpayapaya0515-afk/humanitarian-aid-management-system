
BEGIN;

CREATE TABLE IF NOT EXISTS public.staff_profiles (
    user_id INTEGER PRIMARY KEY
        REFERENCES public.users(user_id)
        ON DELETE CASCADE,

    first_name VARCHAR(50) NOT NULL,
    middle_name VARCHAR(50),
    last_name VARCHAR(50),

    employee_number VARCHAR(32) UNIQUE,

    contact_number VARCHAR(11) NOT NULL
        CHECK (contact_number ~ '^09[0-9]{9}$'),

    position VARCHAR(100) NOT NULL,
    office VARCHAR(100) NOT NULL,

    assigned_barangay VARCHAR(100),
    home_address VARCHAR(255),

    privacy_consented_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMIT;

GRANT SELECT, INSERT
ON TABLE public.staff_profiles
TO aidtrack_app;
