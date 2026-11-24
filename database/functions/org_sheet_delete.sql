-- ============================================================
-- org_sheet_delete
-- Deletes a sheet. Only its owner may (row security).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_sheet_delete(p_tenant_id bigint, p_sheet_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  DELETE FROM org_sheets WHERE tenant_id = p_tenant_id AND sheet_id = p_sheet_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Only the owner can delete this sheet'; END IF;
  RETURN jsonb_build_object('deleted', p_sheet_id);
END $function$;
