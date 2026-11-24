-- ============================================================
-- om_order_import_upload
-- Imports a customer's order file for one account, production date and code. Staff only (row security applies).
-- p_payload: { customer_id (the ACCOUNT), production_date, production_code, file_name,
--              rows: [{ cus_no, item_number, item_desc, qty }] }  -- data rows only, in file order
-- Every row is kept in om_order_import_rows with what it matched and its issue:
--   ERROR   customer number not found / not in this account, item not found / inactive, quantity not above 0, no price
--   WARNING the description differs from the item's name (the item number wins)
-- Rows without an ERROR become order lines: one order per cus no, saved through om_orders_save (numbering, run, totals),
-- priced from the customer's pricing books for the delivery date (fnd_item_prices_map, as Order Entry). Orders are
-- marked order_source 'Import' and import_status IMPORTED, or ISSUES when some of that customer's rows have errors.
-- A not-yet-approved import for the same account, date and code is replaced (its orders deleted). Approved imports and
-- hand-entered orders are never touched. Refused when the run is closed or has shipped deliveries.
-- Returns om_order_import_get for the new import.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_order_import_upload(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_actor    bigint := bps.fnd_nav_app_user_id();
    v_account  bigint := NULLIF(p_payload ->> 'customer_id', '')::bigint;
    v_date     date   := NULLIF(p_payload ->> 'production_date', '')::date;
    v_code     text   := NULLIF(UPPER(TRIM(p_payload ->> 'production_code')), '');
    v_rows     jsonb  := COALESCE(p_payload -> 'rows', '[]'::jsonb);
    v_delivery date;
    v_import   bigint;
    v_cust     record;
    v_prices   jsonb;
    v_lines    jsonb;
    v_saved    jsonb;
    v_status   text;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can import orders';
    END IF;
    IF v_account IS NULL OR NOT EXISTS (SELECT 1 FROM fnd_customers WHERE tenant_id = p_tenant_id AND customer_id = v_account
                                           AND upper(btrim(customer_type)) = 'ACCOUNT') THEN
        RAISE EXCEPTION 'Pick the customer account the file is for';
    END IF;
    IF v_date IS NULL OR v_code IS NULL THEN
        RAISE EXCEPTION 'Production date and production code are required';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM om_production_codes WHERE tenant_id = p_tenant_id AND production_code = v_code) THEN
        RAISE EXCEPTION 'Production code % does not exist', v_code;
    END IF;
    IF jsonb_typeof(v_rows) <> 'array' OR jsonb_array_length(v_rows) = 0 THEN
        RAISE EXCEPTION 'The file has no rows';
    END IF;
    IF jsonb_array_length(v_rows) > 10000 THEN
        RAISE EXCEPTION 'The file has more than 10,000 rows';
    END IF;
    IF EXISTS (SELECT 1 FROM om_production_runs r WHERE r.tenant_id = p_tenant_id AND r.production_date = v_date AND r.production_code = v_code
                  AND (r.run_status = 'CLOSED' OR EXISTS (SELECT 1 FROM om_shipments s WHERE s.production_run_id = r.production_run_id
                                                            AND s.shipment_status IN ('SHIPPED', 'DELIVERED')))) THEN
        RAISE EXCEPTION 'The % % run is closed or has shipped deliveries; orders can no longer be imported', v_date, v_code;
    END IF;
    v_delivery := bps.om_delivery_date_calc(p_tenant_id, v_date, v_code);

    -- replace a not-yet-approved import for the same slot
    DELETE FROM om_orders o USING om_order_imports i
     WHERE o.order_import_id = i.order_import_id AND i.tenant_id = p_tenant_id AND i.customer_id = v_account
       AND i.production_date = v_date AND i.production_code = v_code AND i.import_status <> 'APPROVED';
    DELETE FROM om_order_imports
     WHERE tenant_id = p_tenant_id AND customer_id = v_account AND production_date = v_date AND production_code = v_code
       AND import_status <> 'APPROVED';

    INSERT INTO om_order_imports (tenant_id, customer_id, production_date, production_code, file_name, import_status, created_by, updated_by)
    VALUES (p_tenant_id, v_account, v_date, v_code, NULLIF(btrim(p_payload ->> 'file_name'), ''), 'IMPORTED', v_actor, v_actor)
    RETURNING order_import_id INTO v_import;

    -- the rows, matched to customers (inside the account: the account itself and its departments/sites) and items
    WITH RECURSIVE tree(customer_id) AS (
        SELECT v_account
        UNION ALL
        SELECT c.customer_id FROM fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
         WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
    ), src AS (
        SELECT ord::int AS row_number, NULLIF(btrim(r ->> 'cus_no'), '') AS cus_no, NULLIF(btrim(r ->> 'item_number'), '') AS item_number,
               NULLIF(btrim(r ->> 'item_desc'), '') AS item_desc, NULLIF(btrim(r ->> 'qty'), '') AS qty_text
          FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS x(r, ord)
    )
    INSERT INTO om_order_import_rows (tenant_id, order_import_id, row_number, cus_no, item_number, item_desc, qty_text,
                                      customer_id, item_id, quantity, severity, issue)
    SELECT p_tenant_id, v_import, s.row_number, s.cus_no, s.item_number, s.item_desc, s.qty_text,
           cin.customer_id, it.item_id, q.qty,
           CASE WHEN e.issue IS NOT NULL THEN 'ERROR' WHEN w.issue IS NOT NULL THEN 'WARNING' END,
           COALESCE(e.issue, w.issue)
      FROM src s
      LEFT JOIN LATERAL (SELECT c.customer_id FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_number = s.cus_no
                            AND c.customer_id IN (SELECT customer_id FROM tree) LIMIT 1) cin ON TRUE
      LEFT JOIN LATERAL (SELECT EXISTS (SELECT 1 FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_number = s.cus_no) AS found) cany ON TRUE
      LEFT JOIN LATERAL (SELECT i.item_id, i.item_name, i.is_active FROM fnd_items i WHERE i.tenant_id = p_tenant_id AND i.item_number = s.item_number
                          ORDER BY i.is_active DESC LIMIT 1) it ON TRUE
      LEFT JOIN LATERAL (SELECT CASE WHEN s.qty_text ~ '^\d+(\.\d+)?$' THEN s.qty_text::numeric END AS qty) q ON TRUE
      LEFT JOIN LATERAL (SELECT CASE
             WHEN s.cus_no IS NULL THEN 'Customer number is missing'
             WHEN cin.customer_id IS NULL AND cany.found THEN 'Customer number ' || s.cus_no || ' belongs to another account'
             WHEN cin.customer_id IS NULL THEN 'Customer number ' || s.cus_no || ' not found'
             WHEN s.item_number IS NULL THEN 'Item number is missing'
             WHEN it.item_id IS NULL THEN 'Item ' || s.item_number || ' not found'
             WHEN NOT it.is_active THEN 'Item ' || s.item_number || ' is not active'
             WHEN q.qty IS NULL OR q.qty <= 0 THEN 'Quantity ' || COALESCE(s.qty_text, '(blank)') || ' is not a number above 0'
           END AS issue) e ON TRUE
      LEFT JOIN LATERAL (SELECT CASE WHEN s.item_desc IS NOT NULL AND it.item_name IS NOT NULL
                                      AND upper(regexp_replace(s.item_desc, '\s+', ' ', 'g')) <> upper(regexp_replace(it.item_name, '\s+', ' ', 'g'))
                                     THEN 'Description differs from the item name (' || it.item_name || ')' END AS issue) w ON TRUE;

    -- prices for the delivery date, per customer
    FOR v_cust IN SELECT DISTINCT customer_id FROM om_order_import_rows
                   WHERE order_import_id = v_import AND customer_id IS NOT NULL AND item_id IS NOT NULL LOOP
        v_prices := bps.fnd_item_prices_map(p_tenant_id, v_cust.customer_id, v_delivery,
                      ARRAY(SELECT DISTINCT item_id FROM om_order_import_rows WHERE order_import_id = v_import AND customer_id = v_cust.customer_id));
        UPDATE om_order_import_rows r SET unit_price = (v_prices ->> r.item_id::text)::numeric
         WHERE r.order_import_id = v_import AND r.customer_id = v_cust.customer_id AND r.item_id IS NOT NULL;
    END LOOP;
    UPDATE om_order_import_rows SET severity = 'ERROR', issue = 'No price for this item in the customer''s pricing book'
     WHERE order_import_id = v_import AND item_id IS NOT NULL AND customer_id IS NOT NULL AND unit_price IS NULL
       AND severity IS DISTINCT FROM 'ERROR';

    -- one order per customer from its good rows
    FOR v_cust IN SELECT customer_id, bool_or(severity = 'ERROR') AS has_errors FROM om_order_import_rows
                   WHERE order_import_id = v_import AND customer_id IS NOT NULL GROUP BY customer_id LOOP
        SELECT jsonb_agg(jsonb_build_object('client_temp_id', r.order_import_row_id::text, 'item_id', r.item_id,
                                            'quantity', r.quantity, 'unit_price', r.unit_price, 'unit_discount', 0) ORDER BY r.row_number)
          INTO v_lines
          FROM om_order_import_rows r
         WHERE r.order_import_id = v_import AND r.customer_id = v_cust.customer_id AND r.severity IS DISTINCT FROM 'ERROR';
        CONTINUE WHEN v_lines IS NULL;
        v_saved := bps.om_orders_save(p_tenant_id, NULL, NULL, jsonb_build_object(
                     'customer_id', v_cust.customer_id, 'order_date', CURRENT_DATE, 'production_date', v_date,
                     'production_code', v_code, 'lines', v_lines));
        UPDATE om_orders SET order_import_id = v_import, order_source = 'Import',
                             import_status = CASE WHEN v_cust.has_errors THEN 'ISSUES' ELSE 'IMPORTED' END
         WHERE order_id = (v_saved ->> 'order_id')::bigint;
        UPDATE om_order_import_rows r SET order_id = (v_saved ->> 'order_id')::bigint, order_line_id = (ref ->> 'order_line_id')::bigint
          FROM jsonb_array_elements(v_saved -> 'line_refs') ref
         WHERE r.order_import_row_id = (ref ->> 'client_temp_id')::bigint;
    END LOOP;

    SELECT CASE WHEN bool_or(severity = 'ERROR') THEN 'ISSUES' ELSE 'IMPORTED' END INTO v_status
      FROM om_order_import_rows WHERE order_import_id = v_import;
    UPDATE om_order_imports i SET
           import_status = v_status,
           row_count     = (SELECT count(*) FROM om_order_import_rows r WHERE r.order_import_id = v_import),
           error_count   = (SELECT count(*) FROM om_order_import_rows r WHERE r.order_import_id = v_import AND r.severity = 'ERROR'),
           warning_count = (SELECT count(*) FROM om_order_import_rows r WHERE r.order_import_id = v_import AND r.severity = 'WARNING'),
           order_count   = (SELECT count(*) FROM om_orders o WHERE o.order_import_id = v_import),
           total_amount  = COALESCE((SELECT SUM(o.amount) FROM om_orders o WHERE o.order_import_id = v_import), 0)
     WHERE i.order_import_id = v_import;

    RETURN bps.om_order_import_get(p_tenant_id, v_import);
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_order_import_upload(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_order_import_upload(bigint, jsonb) TO authenticated, service_role, bps_dev;
