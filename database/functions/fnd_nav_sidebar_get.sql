-- ============================================================
-- fnd_nav_sidebar_get
-- One round trip for the sidebar: the user's menu action usage/pins (all tenants) and the user's recent
-- records for p_tenant_id (optionally limited to p_types, at most p_limit per type).
-- Ranking/defaults are applied in the app (website/lib/quick-access.ts).
-- SECURITY INVOKER: RLS limits rows to the caller and the tenants in allowed_tenant_ids.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_nav_sidebar_get(
  p_tenant_id BIGINT,
  p_types     TEXT[] DEFAULT NULL,
  p_limit     INTEGER DEFAULT 5
)
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

  IF p_tenant_id IS NULL OR NOT (
    p_tenant_id::text = ANY (ARRAY(
      SELECT jsonb_array_elements_text(
        (NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'
      )
    ))
  ) THEN
    RAISE EXCEPTION 'Access denied for tenant %', p_tenant_id;
  END IF;

  RETURN jsonb_build_object(
    'actions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'action_key',   a.action_key,
               'use_count',    a.use_count,
               'last_used_at', a.last_used_at,
               'is_pinned',    a.is_pinned,
               'pin_order',    a.pin_order
             ) ORDER BY a.is_pinned DESC, a.pin_order, a.use_count DESC, a.last_used_at DESC NULLS LAST)
        FROM (SELECT * FROM fnd_user_menu_actions WHERE user_id = v_user_id LIMIT 100) a
    ), '[]'::jsonb),
    'recents', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'record_type',      r.record_type,
               'record_key',       r.record_key,
               'label',            r.label,
               'sublabel',         r.sublabel,
               'last_accessed_at', r.last_accessed_at
             ) ORDER BY r.record_type, r.last_accessed_at DESC)
        FROM (
          SELECT x.*, ROW_NUMBER() OVER (PARTITION BY x.record_type ORDER BY x.last_accessed_at DESC) AS rn
            FROM fnd_user_recent_records x
           WHERE x.user_id = v_user_id AND x.tenant_id = p_tenant_id
             AND (p_types IS NULL OR x.record_type = ANY (p_types))
        ) r
       WHERE r.rn <= GREATEST(1, LEAST(COALESCE(p_limit, 5), 20))
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION bps.fnd_nav_sidebar_get(BIGINT, TEXT[], INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_nav_sidebar_get(BIGINT, TEXT[], INTEGER) TO authenticated, bps_dev, service_role;
