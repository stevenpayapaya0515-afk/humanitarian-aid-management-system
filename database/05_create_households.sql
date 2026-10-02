-- Household Registration records
-- Run once when setting up a NEW database.

CREATE TABLE public.households (
    -- Automatically generated household ID
    household_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- Name of the household head
    household_head VARCHAR(100) NOT NULL,

    -- Household location
    barangay VARCHAR(100) NOT NULL,
    purok VARCHAR(100),
    address TEXT NOT NULL,

    -- Total people, including the household head
    household_size INTEGER NOT NULL
        CHECK (household_size >= 1),

    -- Other household members' names, one full name per line
    -- The head is already recorded in household_head
    household_member TEXT NOT NULL DEFAULT '',

    -- Account that registered the household
    registered_by INTEGER NOT NULL
        REFERENCES public.users(user_id),

    -- Registration and last-update timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Allow the backend to view, register, edit, and delete households
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE public.households
TO aidtrack_app;