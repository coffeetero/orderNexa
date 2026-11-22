-- ============================================================
-- fnd_nav_touch
-- Records navigation activity for the signed-in user (fire-and-forget from the app):
--   • p_action_key  -> bumps fnd_user_menu_actions.use_count (Quick Access ranking)
--   • p_record_type -> upserts fnd_user_recent_records for (user, tenant, type, key) and prunes the
--                      list to the 20 most recent per (user, tenant, type)
-- SECURITY INVOKER: RLS on both tables enforces "own rows only" and allowed tenants; the tenant is also
-- validated here for a clear error. Prerequisites: fnd_user_menu_actions.sql, fnd_user_recent_records.sql,
-- fnd_nav_app_user_id.sql and both policy files.
-- clock_timestamp() (not NOW()) so ordering is exact even for several touches inside one transaction.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_nav_touch(
  p_tenant_id   BIGINT,
  p_action_key  TEXT DEFAULT NULL,
  p_record_type TEXT DEFAULT NULL,
  p_record_key  TEXT DEFAULT NULL,
  p_label       TEXT DEFAULT NULL,
  p_sublabel    TEXT DEFAULT NULL
)
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

  IF p_tenant_id IS NULL OR NOT (
    p_tenant_id::text = ANY (ARRAY(
      SELECT jsonb_array_elements_text(
        (NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
      )
    ))
  ) THEN
    RAISE EXCEPTION 'Access denied for tenant %', p_tenant_id;
  END IF;

  IF p_action_key IS NOT NULL THEN
    INSERT INTO fnd_user_menu_actions (user_id, action_key, use_count, last_used_at)
    VALUES (v_user_id, p_action_key, 1, clock_timestamp())
    ON CONFLICT (user_id, action_key) DO UPDATE
      SET use_count    = fnd_user_menu_actions.use_count + 1,
          last_used_at = clock_timestamp(),
          updated_at   = clock_timestamp();
  END IF;

  IF p_record_type IS NOT NULL THEN
    IF NULLIF(BTRIM(p_record_key), '') IS NULL OR NULLIF(BTRIM(p_label), '') IS NULL THEN
      RAISE EXCEPTION 'p_record_key and p_label are required when p_record_type is set';
    END IF;

    INSERT INTO fnd_user_recent_records (user_id, tenant_id, record_type, record_key, label, sublabel, last_accessed_at)
    VALUES (v_user_id, p_tenant_id, p_record_type, BTRIM(p_record_key),
            LEFT(BTRIM(p_label), 200), LEFT(NULLIF(BTRIM(COALESCE(p_sublabel, '')), ''), 200), clock_timestamp())
    ON CONFLICT (user_id, tenant_id, record_type, record_key) DO UPDATE
      SET label            = EXCLUDED.label,
          sublabel         = EXCLUDED.sublabel,
          access_count     = fnd_user_recent_records.access_count + 1,
          last_accessed_at = clock_timestamp();

    DELETE FROM fnd_user_recent_records r
     WHERE r.user_id = v_user_id AND r.tenant_id = p_tenant_id AND r.record_type = p_record_type
       AND r.record_key NOT IN (
         SELECT k.record_key FROM fnd_user_recent_records k
          WHERE k.user_id = v_user_id AND k.tenant_id = p_tenant_id AND k.record_type = p_record_type
          ORDER BY k.last_accessed_at DESC
          LIMIT 20
       );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION bps.fnd_nav_touch(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_nav_touch(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, bps_dev, service_role;
