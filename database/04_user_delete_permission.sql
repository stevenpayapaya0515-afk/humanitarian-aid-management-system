-- Allow the backend application role to delete user rows.
GRANT DELETE ON TABLE public.users TO aidtrack_app;