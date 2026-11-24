-- ============================================================
-- om_order_import_get
-- One import for review: header, every file row with what it matched and its issue, and the orders it created.
-- Returns { order_import_id, customer_id, customer_name, customer_number, production_date, production_code, delivery_date,
--   file_name, import_status, row_count, order_count, error_count, warning_count, total_amount, created_at, approved_at,
--   run_status, rows: [{ row_number, cus_no, item_number, item_desc, qty, customer_name, item_name, unit_price, amount,
--   severity, issue, order_number }], orders: [{ order_id, order_number, customer_number, customer_name, department_event,
--   import_status, lines, quantity, amount }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_order_import_get(p_tenant_id bigint, p_order_import_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v jsonb;
BEGIN
    PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    SELECT jsonb_build_object(
        'order_import_id', i.order_import_id, 'customer_id', i.customer_id, 'customer_name', c.customer_name,
        'customer_number', c.customer_number, 'production_date', i.production_date, 'production_code', i.production_code,
        'delivery_date', bps.om_delivery_date_calc(p_tenant_id, i.production_date, i.production_code),
        'file_name', i.file_name, 'import_status', i.import_status, 'row_count', i.row_count, 'order_count', i.order_count,
        'error_count', i.error_count, 'warning_count', i.warning_count, 'total_amount', i.total_amount,
        'created_at', i.created_at, 'approved_at', i.approved_at,
        'run_status', (SELECT r.run_status FROM om_production_runs r WHERE r.tenant_id = p_tenant_id
                         AND r.production_date = i.production_date AND r.production_code = i.production_code),
        'rows', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                     'row_number', r.row_number, 'cus_no', r.cus_no, 'item_number', r.item_number, 'item_desc', r.item_desc,
                     'qty', r.qty_text, 'customer_name', rc.customer_name, 'item_name', it.item_name, 'unit_price', r.unit_price,
                     'amount', CASE WHEN r.severity IS DISTINCT FROM 'ERROR' THEN round(r.quantity * r.unit_price, 2) END,
                     'severity', r.severity, 'issue', r.issue, 'order_number', o.order_number) ORDER BY r.row_number)
              FROM om_order_import_rows r
              LEFT JOIN fnd_customers rc ON rc.customer_id = r.customer_id
              LEFT JOIN fnd_items it ON it.item_id = r.item_id
              LEFT JOIN om_orders o ON o.order_id = r.order_id
             WHERE r.order_import_id = i.order_import_id), '[]'::jsonb),
        'orders', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                     'order_id', o.order_id, 'order_number', o.order_number, 'customer_number', oc.customer_number,
                     'customer_name', oc.customer_name, 'department_event', o.department_event, 'import_status', o.import_status,
                     'lines', (SELECT count(*) FROM om_order_lines l WHERE l.order_id = o.order_id),
                     'quantity', o.quantity, 'amount', o.amount) ORDER BY oc.customer_number, o.order_number)
              FROM om_orders o JOIN fnd_customers oc ON oc.customer_id = o.customer_id
             WHERE o.order_import_id = i.order_import_id), '[]'::jsonb))
      INTO v
      FROM om_order_imports i JOIN fnd_customers c ON c.customer_id = i.customer_id
     WHERE i.tenant_id = p_tenant_id AND i.order_import_id = p_order_import_id;
    IF v IS NULL THEN RAISE EXCEPTION 'Import not found'; END IF;
    RETURN v;
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_order_import_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_order_import_get(bigint, bigint) TO authenticated, service_role, bps_dev;
