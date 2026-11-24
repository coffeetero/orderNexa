-- ============================================================
-- org_sheets_get
-- The sheets the caller can see (their own and shared ones), newest first, without the workbook.
-- Row security decides what is listed.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_sheets_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'sheet_id', s.sheet_id, 'sheet_name', s.sheet_name, 'visibility', s.visibility, 'version', s.version,
           'owner_name', u.user_name, 'is_owner', s.owner_user_id = bps.fnd_current_user_id(),
           'updated_at', s.updated_at, 'updated_by_name', ub.user_name)
         ORDER BY s.updated_at DESC), '[]'::jsonb)
    FROM bps.org_sheets s
    JOIN bps.fnd_users u ON u.user_id = s.owner_user_id
    LEFT JOIN bps.fnd_users ub ON ub.user_id = s.updated_by
   WHERE s.tenant_id = p_tenant_id
$function$;
REVOKE EXECUTE ON FUNCTION bps.org_sheets_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_sheets_get(bigint) TO authenticated, service_role, bps_dev;
