-- ============================================================
-- om_order_import_approve
-- Staff confirm an import: its orders (and the import) become APPROVED and from then on count in production.
-- Refused while any row has an ERROR (fix the file and upload again; it replaces this import), when already approved,
-- or when the run is closed or has shipped deliveries. If the run was already processed, it must be processed again
-- (returned as needs_reprocess) so the new orders get their shipment and invoice lines.
-- Returns om_order_import_get plus needs_reprocess.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_order_import_approve(p_tenant_id bigint, p_order_import_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_actor bigint := bps.fnd_nav_app_user_id();
    v_imp   om_order_imports%ROWTYPE;
    v_run   om_production_runs%ROWTYPE;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can approve imports';
    END IF;
    SELECT * INTO v_imp FROM om_order_imports WHERE tenant_id = p_tenant_id AND order_import_id = p_order_import_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Import not found'; END IF;
    IF v_imp.import_status = 'APPROVED' THEN RAISE EXCEPTION 'This import is already approved'; END IF;
    IF EXISTS (SELECT 1 FROM om_order_import_rows WHERE order_import_id = p_order_import_id AND severity = 'ERROR') THEN
        RAISE EXCEPTION 'This import has rows with errors; fix the file and upload it again';
    END IF;
    SELECT * INTO v_run FROM om_production_runs
     WHERE tenant_id = p_tenant_id AND production_date = v_imp.production_date AND production_code = v_imp.production_code;
    IF FOUND AND (v_run.run_status = 'CLOSED' OR EXISTS (SELECT 1 FROM om_shipments s WHERE s.production_run_id = v_run.production_run_id
                                                          AND s.shipment_status IN ('SHIPPED', 'DELIVERED'))) THEN
        RAISE EXCEPTION 'The % % run is closed or has shipped deliveries', v_imp.production_date, v_imp.production_code;
    END IF;

    UPDATE om_orders SET import_status = 'APPROVED', updated_by = v_actor WHERE order_import_id = p_order_import_id;
    UPDATE om_order_imports SET import_status = 'APPROVED', approved_at = now(), approved_by = v_actor, updated_at = now(), updated_by = v_actor
     WHERE order_import_id = p_order_import_id;

    RETURN bps.om_order_import_get(p_tenant_id, p_order_import_id)
        || jsonb_build_object('needs_reprocess', COALESCE(v_run.run_status = 'PROCESSED', false));
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_order_import_approve(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_order_import_approve(bigint, bigint) TO authenticated, service_role, bps_dev;
