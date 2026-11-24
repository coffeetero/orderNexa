-- ============================================================
-- om_order_export_get
-- The orders of one account (the account and its departments/sites) for a production date and code, as import-file rows:
--   [{ cus_no, customer_name, department_event, item_number, item_desc, qty }]
-- in the layout om_order_import_upload reads, so the file imports back as the same orders. Every order in the slot
-- (entered, standing, imported approved or not). item_desc is the item's current name (no description warning on import);
-- lines with a quantity of 0 or less are left out (the import refuses them). Staff only (row security applies).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_order_export_get(p_tenant_id bigint, p_account_id bigint, p_production_date date, p_production_code text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v jsonb;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can export orders';
    END IF;
    IF p_account_id IS NULL OR NOT EXISTS (SELECT 1 FROM fnd_customers WHERE tenant_id = p_tenant_id AND customer_id = p_account_id
                                              AND upper(btrim(customer_type)) = 'ACCOUNT') THEN
        RAISE EXCEPTION 'Pick the customer account to export';
    END IF;
    IF p_production_date IS NULL OR NULLIF(btrim(p_production_code), '') IS NULL THEN
        RAISE EXCEPTION 'Production date and production code are required';
    END IF;

    WITH RECURSIVE tree(customer_id) AS (
        SELECT p_account_id
        UNION ALL
        SELECT c.customer_id FROM fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
         WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'cus_no', c.customer_number, 'customer_name', c.customer_name, 'item_number', i.item_number, 'item_desc', i.item_name,
               'qty', trim_scale(l.quantity)::text, 'department_event', o.department_event)
             ORDER BY c.customer_number, o.department_event, o.order_number, l.order_line_id), '[]'::jsonb)
      INTO v
      FROM om_orders o
      JOIN tree t ON t.customer_id = o.customer_id
      JOIN fnd_customers c ON c.customer_id = o.customer_id
      JOIN om_order_lines l ON l.order_id = o.order_id
      JOIN fnd_items i ON i.item_id = l.item_id
     WHERE o.tenant_id = p_tenant_id AND o.production_date = p_production_date
       AND o.production_code = upper(btrim(p_production_code)) AND l.quantity > 0;
    RETURN v;
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_order_export_get(bigint, bigint, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_order_export_get(bigint, bigint, date, text) TO authenticated, service_role, bps_dev;
