-- ============================================================
-- org_sheet_get
-- One sheet with its workbook. Row security decides whether the caller may see it.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_sheet_get(p_tenant_id bigint, p_sheet_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  SELECT jsonb_build_object(
           'sheet_id', s.sheet_id, 'sheet_name', s.sheet_name, 'visibility', s.visibility, 'version', s.version,
           'owner_name', u.user_name, 'is_owner', s.owner_user_id = bps.fnd_current_user_id(),
           'updated_at', s.updated_at, 'workbook', s.workbook)
    INTO v
    FROM bps.org_sheets s JOIN bps.fnd_users u ON u.user_id = s.owner_user_id
   WHERE s.tenant_id = p_tenant_id AND s.sheet_id = p_sheet_id;
  IF v IS NULL THEN RAISE EXCEPTION 'Sheet not found'; END IF;
  RETURN v;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_sheet_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_sheet_get(bigint, bigint) TO authenticated, service_role, bps_dev;
