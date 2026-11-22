-- ============================================================
-- fnd_user_preferences_save
-- Creates or replaces the signed-in user's appearance preferences (p_appearance must be a JSON object, max 64 KB).
-- SECURITY INVOKER: RLS limits the row to the caller.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_user_preferences_save(p_appearance JSONB)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = bps, public
AS $$
DECLARE
  v_user_id BIGINT := bps.fnd_nav_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No BPS user for this session';
  END IF;

  IF p_appearance IS NULL OR jsonb_typeof(p_appearance) <> 'object' THEN
    RAISE EXCEPTION 'p_appearance must be a JSON object';
  END IF;

  INSERT INTO fnd_user_preferences (user_id, appearance, created_by, updated_by)
  VALUES (v_user_id, p_appearance, v_user_id, v_user_id)
  ON CONFLICT (user_id) DO UPDATE
    SET appearance = EXCLUDED.appearance,
        updated_at = clock_timestamp(),
        updated_by = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION bps.fnd_user_preferences_save(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_user_preferences_save(JSONB) TO authenticated, bps_dev, service_role;
