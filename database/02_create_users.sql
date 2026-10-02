-- AidTrack user accounts
-- Connect to aidtrack_db before running this file.
-- Run only when the users table does not exist yet.

CREATE TABLE public.users (
    -- Automatically generated account ID
    user_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- Account owner's full name
    full_name VARCHAR(100) NOT NULL,

    -- Each account must have a unique email
    email VARCHAR(254) NOT NULL UNIQUE,

    -- Store the password hash, not the original password
    password_hash TEXT NOT NULL,

    -- Only Admin and Staff roles are allowed
    role VARCHAR(20) NOT NULL
        CHECK (role IN ('Admin', 'Staff')),

    -- New accounts are active by default
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    -- Automatically record when the account was created
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);