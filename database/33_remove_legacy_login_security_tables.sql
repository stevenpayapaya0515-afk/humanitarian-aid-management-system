
-- Remove unused CAPTCHA and IP-block tables.
-- Keep login_otps for two-step authentication.

BEGIN;

DROP TABLE IF EXISTS public.login_captchas RESTRICT;
DROP TABLE IF EXISTS public.ip_blocks RESTRICT;

COMMIT;
