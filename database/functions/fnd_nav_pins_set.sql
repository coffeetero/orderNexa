-- ============================================================
-- fnd_nav_pins_set
-- Replaces the signed-in user's pinned Quick Access actions with p_action_keys (ordered, max 3, unique).
-- Pass an empty array to unpin everything. Usage counts are preserved; actions without a row get one.
-- SECURITY INVOKER: RLS limits the rows to the caller.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_nav_pins_set(p_action_keys TEXT[])
RETURNS VOID
LANGUAGE plpgsql
SET search_path = bps, public
AS $$
DECLARE
  v_user_id BIGINT := bps.fnd_nav_app_user_id();
  v_keys    TEXT[] := COALESCE(p_action_keys, ARRAY[]::TEXT[]);
  v_i       INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No BPS user for this session';
  END IF;

  IF cardinality(v_keys) > 3 THEN
    RAISE EXCEPTION 'At most 3 actions can be pinned';
  END IF;

  IF (SELECT COUNT(DISTINCT k) FROM unnest(v_keys) AS k) <> cardinality(v_keys) THEN
    RAISE EXCEPTION 'Pinned actions must be unique';
  END IF;

  UPDATE fnd_user_menu_actions
     SET is_pinned = FALSE, pin_order = NULL, updated_at = NOW()
   WHERE user_id = v_user_id AND is_pinned;

  FOR v_i IN 1 .. cardinality(v_keys) LOOP
    INSERT INTO fnd_user_menu_actions (user_id, action_key, is_pinned, pin_order)
    VALUES (v_user_id, v_keys[v_i], TRUE, v_i)
    ON CONFLICT (user_id, action_key) DO UPDATE
      SET is_pinned = TRUE, pin_order = v_i, updated_at = NOW();
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION bps.fnd_nav_pins_set(TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_nav_pins_set(TEXT[]) TO authenticated, bps_dev, service_role;
