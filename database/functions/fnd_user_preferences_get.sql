-- ============================================================
-- fnd_user_preferences_get
-- Returns the signed-in user's preferences as { appearance: {...} } ('{}' appearance when never saved).
-- SECURITY INVOKER: RLS limits the row to the caller. Prerequisites: fnd_user_preferences.sql + policies.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_user_preferences_get()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = bps, public
AS $$
DECLARE
  v_user_id BIGINT := bps.fnd_nav_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No BPS user for this session';
  END IF;

  RETURN jsonb_build_object(
    'appearance',
    COALESCE((SELECT p.appearance FROM fnd_user_preferences p WHERE p.user_id = v_user_id), '{}'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION bps.fnd_user_preferences_get() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_user_preferences_get() TO authenticated, bps_dev, service_role;
