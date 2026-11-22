-- ============================================================
-- fnd_nav_app_user_id
-- Returns the BPS user id (fnd_users.user_id) from the JWT claim app_metadata.app_user_id that the
-- access-token hook (bps_access_token_hook) puts into every token. NULL when absent (e.g. anon).
-- Used by the per-user navigation tables' RLS policies and functions.
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_nav_app_user_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
SET search_path = bps, public
AS $$
  SELECT NULLIF(
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' ->> 'app_user_id'),
    'null'
  )::BIGINT
$$;

REVOKE ALL ON FUNCTION bps.fnd_nav_app_user_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_nav_app_user_id() TO authenticated, bps_dev, service_role;
