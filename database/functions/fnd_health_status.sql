-- ============================================================
-- fnd_health_status(tenant) → the health heart's state. Replaces the version in migration/add_health_checks.sql.
-- Owner decision 2026-11-28: red = open errors, orange = warnings only, blue = information only, green = nothing open;
-- 'never' before the first run, 'none' without Health Checks access.
-- Counts the open findings of enabled checks (not the last run's totals), so the heart changes as soon as findings are
-- fixed or inactivated from the Health Checks page.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_health_status(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_last timestamptz; v_i int; v_w int; v_e int;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.health', 'R') THEN RETURN jsonb_build_object('state', 'none', 'infos', 0, 'warnings', 0, 'errors', 0, 'last_run_at', NULL); END IF;
  SELECT max(last_run_at) INTO v_last FROM bps.fnd_health_checks WHERE tenant_id = p_tenant_id AND is_enabled;
  SELECT count(*) FILTER (WHERE l.type = 'Information'), count(*) FILTER (WHERE l.type = 'Warning'), count(*) FILTER (WHERE l.type = 'Error')
    INTO v_i, v_w, v_e
    FROM bps.fnd_health_log l JOIN bps.fnd_health_checks h ON h.tenant_id = l.tenant_id AND h.check_code = l.check_code AND h.is_enabled
   WHERE l.tenant_id = p_tenant_id AND l.fixed_at IS NULL;
  RETURN jsonb_build_object('state', CASE WHEN v_last IS NULL THEN 'never' WHEN v_e > 0 THEN 'error' WHEN v_w > 0 THEN 'warning' WHEN v_i > 0 THEN 'info' ELSE 'ok' END,
    'infos', v_i, 'warnings', v_w, 'errors', v_e, 'last_run_at', v_last);
END $$;
