-- ============================================================
-- po_check
-- Internal: checks the caller may act on Purchasing (vendors and vendor items) in this tenant.
-- p_action: 'R' read, 'W' write, 'D' delete (purchasing.vendors access).
-- Called only from the SECURITY DEFINER po_* functions; app users cannot execute it.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.po_check(p_tenant_id bigint, p_action text)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('purchasing.vendors', p_action) THEN
    RAISE EXCEPTION 'You do not have access to % vendors',
      CASE upper(p_action) WHEN 'R' THEN 'view' WHEN 'D' THEN 'delete' ELSE 'edit' END USING ERRCODE = '42501';
  END IF;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.po_check(bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.po_check(bigint, text) TO service_role, bps_dev;
