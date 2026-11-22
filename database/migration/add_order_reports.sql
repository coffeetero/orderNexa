-- Order reports (Phase 3 of order-to-invoice): data functions behind the Baker's Report, Packing Labels, Packaging List
-- (assigns invoice numbers) and Route Delivery Report. Requires add_order_processing.sql first. Local only.
SET search_path = bps, public;

-- ===== functions/om_customer_ship_address.sql =====
-- ============================================================
-- om_customer_ship_address
-- The customer's delivery address text: its active ADDRESS contact point, preferring the one marked use_as_shipping,
-- then primary. SECURITY DEFINER because app users have no direct access to the contact tables; tenant staff only.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_customer_ship_address(p_tenant_id bigint, p_customer_id bigint)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RETURN NULL;
    END IF;
    RETURN (SELECT cp.value
              FROM fnd_contacts ct
              JOIN fnd_contact_points cp ON cp.contact_id = ct.contact_id AND cp.tenant_id = ct.tenant_id
             WHERE ct.tenant_id = p_tenant_id AND ct.entity_id = p_customer_id AND ct.source_table = 'fnd_customers'
               AND cp.type = 'ADDRESS' AND cp.is_active
             ORDER BY cp.use_as_shipping DESC, cp.is_primary DESC, cp.sequence
             LIMIT 1);
END;
$function$;

-- ===== functions/om_report_customers_get.sql =====
-- ============================================================
-- om_report_customers_get
-- Customers to pick from on the Labels and Packaging pages, for production dates in [p_from, p_to] (and one production
-- code when given). Staff only.
--   p_basis 'ORDER'   : customers that have orders (the order's customer; a site's orders sit under its parent).
--   p_basis 'INVOICE' : invoice owners that have a DRAFT or OPEN invoice for a run in the range (process the run first).
-- Returns [{ customer_id, customer_name, customer_number, document_count }] ordered by name.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_report_customers_get(p_tenant_id bigint, p_from date, p_to date, p_production_code text, p_basis text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code   text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_result jsonb;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can run reports';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;

    IF UPPER(COALESCE(p_basis, 'ORDER')) = 'INVOICE' THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'customer_id', x.customer_id, 'customer_name', x.customer_name,
                   'customer_number', x.customer_number, 'document_count', x.n
               ) ORDER BY x.customer_name), '[]'::jsonb)
          INTO v_result
          FROM (
            SELECT c.customer_id, c.customer_name, c.customer_number, COUNT(*) AS n
              FROM ar_transactions t
              JOIN om_production_runs r ON r.production_run_id = t.production_run_id
              JOIN fnd_customers c ON c.customer_id = t.customer_id AND c.tenant_id = t.tenant_id
             WHERE t.tenant_id = p_tenant_id AND t.transaction_type = 'INV' AND t.status IN ('DRAFT', 'OPEN')
               AND r.production_date BETWEEN p_from AND p_to AND (v_code IS NULL OR r.production_code = v_code)
             GROUP BY c.customer_id, c.customer_name, c.customer_number
          ) x;
    ELSE
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'customer_id', x.customer_id, 'customer_name', x.customer_name,
                   'customer_number', x.customer_number, 'document_count', x.n
               ) ORDER BY x.customer_name), '[]'::jsonb)
          INTO v_result
          FROM (
            SELECT c.customer_id, c.customer_name, c.customer_number, COUNT(*) AS n
              FROM om_orders o
              JOIN fnd_customers c ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
             WHERE o.tenant_id = p_tenant_id AND o.production_date BETWEEN p_from AND p_to
               AND (v_code IS NULL OR o.production_code = v_code)
             GROUP BY c.customer_id, c.customer_name, c.customer_number
          ) x;
    END IF;
    RETURN v_result;
END;
$function$;

-- ===== functions/om_report_bakers_get.sql =====
-- ============================================================
-- om_report_bakers_get
-- Baker's Report data: for each run with production date in [p_from, p_to] (one code when given), the item totals grouped
-- by item category, with the dough type, unit and order count; category and run totals; and changed_since_print
-- (an order or order line created or changed after the last Baker's Report print). Staff only; does not stamp prints
-- (see om_production_runs_mark_printed).
-- Returns { runs: [{ production_run_id, production_date, production_code, delivery_date, order_count, total_quantity,
--   last_printed_at, changed_since_print, categories: [{ category, total_quantity, items: [{ item_number, item_name,
--   dough_type, unit_of_sale, quantity, order_count }] }] }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_report_bakers_get(p_tenant_id bigint, p_from date, p_to date, p_production_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_runs jsonb;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can run reports';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'production_run_id',   r.production_run_id,
               'production_date',     r.production_date,
               'production_code',     r.production_code,
               'delivery_date',       r.delivery_date,
               'order_count',         (SELECT COUNT(*) FROM om_orders o WHERE o.production_run_id = r.production_run_id),
               'total_quantity',      (SELECT COALESCE(SUM(ol.quantity), 0) FROM om_order_lines ol JOIN om_orders o ON o.order_id = ol.order_id WHERE o.production_run_id = r.production_run_id),
               'last_printed_at',     r.baker_sheet_printed_at,
               'changed_since_print', r.baker_sheet_printed_at IS NOT NULL AND (
                    EXISTS (SELECT 1 FROM om_orders o WHERE o.production_run_id = r.production_run_id AND o.updated_at > r.baker_sheet_printed_at)
                 OR EXISTS (SELECT 1 FROM om_order_lines ol JOIN om_orders o ON o.order_id = ol.order_id
                             WHERE o.production_run_id = r.production_run_id AND ol.updated_at > r.baker_sheet_printed_at)),
               'categories', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object('category', cat.category, 'total_quantity', cat.total, 'items', cat.items) ORDER BY cat.category)
                      FROM (
                        SELECT g.category, SUM(g.quantity) AS total,
                               jsonb_agg(jsonb_build_object('item_number', g.item_number, 'item_name', g.item_name, 'dough_type', g.dough_type,
                                                            'unit_of_sale', g.unit_of_sale, 'quantity', g.quantity, 'order_count', g.orders)
                                         ORDER BY g.dough_type NULLS LAST, g.item_name) AS items
                          FROM (
                            SELECT COALESCE(NULLIF(TRIM(i.category), ''), 'Uncategorised') AS category, i.item_number, COALESCE(i.item_name, MAX(ol.item_description)) AS item_name,
                                   i.dough_type, i.unit_of_sale, SUM(ol.quantity) AS quantity, COUNT(DISTINCT ol.order_id) AS orders
                              FROM om_order_lines ol
                              JOIN om_orders o ON o.order_id = ol.order_id AND o.tenant_id = ol.tenant_id
                              LEFT JOIN fnd_items i ON i.item_id = ol.item_id
                             WHERE o.production_run_id = r.production_run_id AND ol.quantity <> 0
                             GROUP BY i.item_id, i.category, i.item_number, i.item_name, i.dough_type, i.unit_of_sale
                          ) g
                         GROUP BY g.category
                      ) cat
               ), '[]'::jsonb)
           ) ORDER BY r.production_date, r.production_code), '[]'::jsonb)
      INTO v_runs
      FROM om_production_runs r
     WHERE r.tenant_id = p_tenant_id AND r.production_date BETWEEN p_from AND p_to
       AND (v_code IS NULL OR r.production_code = v_code);

    RETURN jsonb_build_object('runs', v_runs);
END;
$function$;

-- ===== functions/om_report_labels_get.sql =====
-- ============================================================
-- om_report_labels_get
-- Packing label rows (one label per order line) for the selected customers and production dates. Staff only.
-- The customer is the order's customer (a site's orders sit under its parent); department_event holds the site or event.
-- Returns { labels: [{ production_date, production_code, delivery_date, customer_name, department_event, order_number,
--   po_number, item_number, item_name, quantity, unit_of_sale, prep_options }] } ordered by customer, event, order, line.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_report_labels_get(p_tenant_id bigint, p_from date, p_to date, p_production_code text, p_customer_ids bigint[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_production_code)), '');
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can run reports';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;
    IF p_customer_ids IS NULL OR COALESCE(array_length(p_customer_ids, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one customer';
    END IF;

    RETURN jsonb_build_object('labels', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                   'production_date',  o.production_date,
                   'production_code',  o.production_code,
                   'delivery_date',    r.delivery_date,
                   'customer_name',    COALESCE(o.customer_name, c.customer_name),
                   'department_event', o.department_event,
                   'order_number',     o.order_number,
                   'po_number',        o.po_number,
                   'item_number',      i.item_number,
                   'item_name',        COALESCE(NULLIF(TRIM(ol.item_description), ''), i.item_name),
                   'quantity',         ol.quantity,
                   'unit_of_sale',     i.unit_of_sale,
                   'prep_options',     COALESCE((SELECT string_agg(COALESCE(e ->> 'label', e #>> '{}'), ', ')
                                                   FROM jsonb_array_elements(COALESCE(ol.prep_options, '[]'::jsonb)) e), '')
               ) ORDER BY COALESCE(o.customer_name, c.customer_name), o.production_date, o.department_event, o.order_number, ol.order_line_id)
          FROM om_orders o
          JOIN om_order_lines ol ON ol.order_id = o.order_id AND ol.tenant_id = o.tenant_id
          LEFT JOIN fnd_customers c ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
          LEFT JOIN fnd_items i ON i.item_id = ol.item_id
          LEFT JOIN om_production_runs r ON r.production_run_id = o.production_run_id
         WHERE o.tenant_id = p_tenant_id AND o.production_date BETWEEN p_from AND p_to
           AND (v_code IS NULL OR o.production_code = v_code)
           AND o.customer_id = ANY (p_customer_ids) AND ol.quantity > 0
    ), '[]'::jsonb));
END;
$function$;

-- ===== functions/om_report_packaging_issue.sql =====
-- ============================================================
-- om_report_packaging_issue
-- Prints the Packaging List: for the chosen invoice owners and runs in [p_from, p_to] (one code when given) it gives each
-- DRAFT invoice its number from the tenant sequence 'invoice_number' (status DRAFT -> OPEN, which locks the number),
-- stamps packaging_printed_at on the runs, and returns every DRAFT/OPEN invoice of those owners (OPEN ones are reprints
-- and keep their number). Staff only. Raises when nothing matches (process the run first).
-- Returns { invoices: [{ ar_transaction_id, document_number, customer_id, customer_name, customer_number, production_date,
--   production_code, delivery_date, amount, copies, orders: [{ order_number, department_event, customer_name, po_number,
--   order_total, lines: [{ line_number, source_type, item_description, quantity, unit_price, amount }] }] }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_report_packaging_issue(p_tenant_id bigint, p_from date, p_to date, p_production_code text, p_customer_ids bigint[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_inv  record;
    v_n    integer := 0;
    v_out  jsonb;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can print invoices';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;
    IF p_customer_ids IS NULL OR COALESCE(array_length(p_customer_ids, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one customer';
    END IF;

    FOR v_inv IN
        SELECT t.ar_transaction_id, t.transaction_date
          FROM ar_transactions t
          JOIN om_production_runs r ON r.production_run_id = t.production_run_id
          JOIN fnd_customers c ON c.customer_id = t.customer_id AND c.tenant_id = t.tenant_id
         WHERE t.tenant_id = p_tenant_id AND t.transaction_type = 'INV' AND t.status = 'DRAFT'
           AND t.customer_id = ANY (p_customer_ids)
           AND r.production_date BETWEEN p_from AND p_to AND (v_code IS NULL OR r.production_code = v_code)
         ORDER BY c.customer_name, r.production_date, r.production_code
    LOOP
        UPDATE ar_transactions
           SET document_number = bps.fnd_tenant_sequence_next(p_tenant_id, 'invoice_number', v_inv.transaction_date),
               status = 'OPEN'
         WHERE ar_transaction_id = v_inv.ar_transaction_id;
        v_n := v_n + 1;
    END LOOP;

    UPDATE om_production_runs r SET packaging_printed_at = now()
     WHERE r.tenant_id = p_tenant_id AND r.production_date BETWEEN p_from AND p_to AND (v_code IS NULL OR r.production_code = v_code)
       AND EXISTS (SELECT 1 FROM ar_transactions t WHERE t.production_run_id = r.production_run_id AND t.transaction_type = 'INV'
                      AND t.status IN ('DRAFT', 'OPEN') AND t.customer_id = ANY (p_customer_ids));

    SELECT COALESCE(jsonb_agg(inv.obj ORDER BY inv.customer_name, inv.production_date, inv.production_code), '[]'::jsonb)
      INTO v_out
      FROM (
        SELECT c.customer_name, r.production_date, r.production_code,
               jsonb_build_object(
                 'ar_transaction_id', t.ar_transaction_id, 'document_number', t.document_number,
                 'customer_id', c.customer_id, 'customer_name', c.customer_name, 'customer_number', c.customer_number,
                 'production_date', r.production_date, 'production_code', r.production_code, 'delivery_date', r.delivery_date,
                 'amount', t.amount, 'copies', GREATEST(c.invoice_copy_count, 1),
                 'orders', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                               'order_number', g.order_number, 'department_event', g.department_event, 'customer_name', g.customer_name,
                               'po_number', g.po_number, 'order_total', g.total, 'lines', g.lines)
                               ORDER BY g.department_event, g.order_number)
                      FROM (
                        SELECT l.snapshot_data ->> 'order_number' AS order_number, l.snapshot_data ->> 'department_event' AS department_event,
                               l.snapshot_data ->> 'customer_name' AS customer_name, l.snapshot_data ->> 'po_number' AS po_number,
                               SUM(l.amount) AS total,
                               jsonb_agg(jsonb_build_object('line_number', l.line_number, 'source_type', l.source_type,
                                          'item_description', l.item_description, 'quantity', l.quantity,
                                          'unit_price', l.unit_price, 'amount', l.amount) ORDER BY l.line_number) AS lines
                          FROM ar_transaction_lines l
                         WHERE l.ar_transaction_id = t.ar_transaction_id
                         GROUP BY l.snapshot_data ->> 'order_number', l.snapshot_data ->> 'department_event',
                                  l.snapshot_data ->> 'customer_name', l.snapshot_data ->> 'po_number'
                      ) g
                 ), '[]'::jsonb)
               ) AS obj
          FROM ar_transactions t
          JOIN om_production_runs r ON r.production_run_id = t.production_run_id
          JOIN fnd_customers c ON c.customer_id = t.customer_id AND c.tenant_id = t.tenant_id
         WHERE t.tenant_id = p_tenant_id AND t.transaction_type = 'INV' AND t.status = 'OPEN'
           AND t.customer_id = ANY (p_customer_ids)
           AND r.production_date BETWEEN p_from AND p_to AND (v_code IS NULL OR r.production_code = v_code)
      ) inv;

    IF jsonb_array_length(v_out) = 0 THEN
        RAISE EXCEPTION 'No invoices found for the selection. Process the run first.';
    END IF;
    RETURN jsonb_build_object('invoices', v_out, 'newly_numbered', v_n);
END;
$function$;

-- ===== functions/om_report_delivery_get.sql =====
-- ============================================================
-- om_report_delivery_get
-- Route Delivery Report: the driver's sheet. Own-fleet shipments (delivery method is_own_fleet, or none set) for runs
-- with production date in [p_from, p_to] (one code when given), grouped by delivery date and route, one stop per ship-to
-- customer with its address, the invoice numbers carried and the items. Staff only; does not stamp prints.
-- Returns { stops: [{ delivery_date, route, shipment_number, customer_name, customer_number, address, delivery_method,
--   invoice_numbers, items: [{ item_name, quantity }] }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_report_delivery_get(p_tenant_id bigint, p_from date, p_to date, p_production_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_production_code)), '');
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can run reports';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;

    RETURN jsonb_build_object('stops', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                   'delivery_date',   s.delivery_date,
                   'route',           s.route,
                   'shipment_number', s.shipment_number,
                   'customer_name',   c.customer_name,
                   'customer_number', c.customer_number,
                   'address',         bps.om_customer_ship_address(s.tenant_id, s.ship_to_customer_id),
                   'delivery_method', COALESCE(m.delivery_method_name, s.delivery_method_code),
                   'invoice_numbers', COALESCE((SELECT jsonb_agg(DISTINCT t.document_number)
                                                  FROM om_shipment_lines sl
                                                  JOIN ar_transaction_lines al ON al.shipment_line_id = sl.shipment_line_id
                                                  JOIN ar_transactions t ON t.ar_transaction_id = al.ar_transaction_id AND t.status <> 'CANCELLED'
                                                 WHERE sl.shipment_id = s.shipment_id AND t.document_number IS NOT NULL), '[]'::jsonb),
                   'items',           COALESCE((SELECT jsonb_agg(jsonb_build_object('item_name', x.item_name, 'quantity', x.quantity) ORDER BY x.item_name)
                                                  FROM (SELECT COALESCE(i.item_name, MAX(ol.item_description)) AS item_name, SUM(sl.quantity) AS quantity
                                                          FROM om_shipment_lines sl
                                                          JOIN om_order_lines ol ON ol.order_line_id = sl.order_line_id
                                                          LEFT JOIN fnd_items i ON i.item_id = ol.item_id
                                                         WHERE sl.shipment_id = s.shipment_id
                                                         GROUP BY i.item_id, i.item_name) x), '[]'::jsonb)
               ) ORDER BY s.delivery_date, COALESCE(s.route, ''), c.customer_name)
          FROM om_shipments s
          JOIN om_production_runs r ON r.production_run_id = s.production_run_id
          JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id AND c.tenant_id = s.tenant_id
          LEFT JOIN om_delivery_methods m ON m.tenant_id = s.tenant_id AND m.delivery_method_code = s.delivery_method_code
         WHERE s.tenant_id = p_tenant_id AND r.production_date BETWEEN p_from AND p_to
           AND (v_code IS NULL OR r.production_code = v_code)
           AND s.shipment_status <> 'CANCELLED'
           AND (s.delivery_method_code IS NULL OR COALESCE(m.is_own_fleet, FALSE))
    ), '[]'::jsonb));
END;
$function$;

-- ===== functions/om_production_runs_mark_printed.sql =====
-- ============================================================
-- om_production_runs_mark_printed
-- Stamps the print time of a report on the runs in [p_from, p_to] (one code when given): p_report is 'BAKER', 'LABELS' or
-- 'DELIVERY'. The Packaging List stamps itself inside om_report_packaging_issue. Staff only. Returns the runs stamped.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_runs_mark_printed(p_tenant_id bigint, p_from date, p_to date, p_production_code text, p_report text)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_rep  text := UPPER(TRIM(p_report));
    v_n    integer;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can record prints';
    END IF;
    IF v_rep NOT IN ('BAKER', 'LABELS', 'DELIVERY') THEN
        RAISE EXCEPTION 'Unknown report %', p_report;
    END IF;
    UPDATE om_production_runs r SET
        baker_sheet_printed_at = CASE WHEN v_rep = 'BAKER'    THEN now() ELSE baker_sheet_printed_at END,
        labels_printed_at      = CASE WHEN v_rep = 'LABELS'   THEN now() ELSE labels_printed_at END,
        delivery_printed_at    = CASE WHEN v_rep = 'DELIVERY' THEN now() ELSE delivery_printed_at END
     WHERE r.tenant_id = p_tenant_id AND r.production_date BETWEEN p_from AND p_to
       AND (v_code IS NULL OR r.production_code = v_code);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$function$;

-- ===== grants =====
GRANT EXECUTE ON FUNCTION bps.om_customer_ship_address(bigint, bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_report_customers_get(bigint, date, date, text, text) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_report_bakers_get(bigint, date, date, text) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_report_labels_get(bigint, date, date, text, bigint[]) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_report_packaging_issue(bigint, date, date, text, bigint[]) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_report_delivery_get(bigint, date, date, text) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_production_runs_mark_printed(bigint, date, date, text, text) TO authenticated, bps_dev, service_role;