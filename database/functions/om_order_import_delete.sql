-- ============================================================
-- om_order_import_delete
-- Removes an import that is not approved, with the orders it created. Approved imports cannot be deleted here
-- (their orders are regular orders by then; change them in Order Entry).
-- Returns { deleted_orders }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_order_import_delete(p_tenant_id bigint, p_order_import_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_status text; v_n integer;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can delete imports';
    END IF;
    SELECT import_status INTO v_status FROM om_order_imports WHERE tenant_id = p_tenant_id AND order_import_id = p_order_import_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Import not found'; END IF;
    IF v_status = 'APPROVED' THEN RAISE EXCEPTION 'An approved import cannot be deleted'; END IF;
    DELETE FROM om_orders WHERE tenant_id = p_tenant_id AND order_import_id = p_order_import_id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    DELETE FROM om_order_imports WHERE order_import_id = p_order_import_id;
    RETURN jsonb_build_object('deleted_orders', v_n);
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_order_import_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_order_import_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
