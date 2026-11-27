-- ============================================================
-- om_report_packaging_issue
-- Prints the Packaging List: for the chosen invoice owners and runs in [p_from, p_to] (one code when given) it stamps
-- packaging_printed_at on the runs and printed_at on the invoices, and returns every DRAFT/OPEN invoice of those owners.
-- Printing never numbers an invoice (Post Orders to AR does, om_invoices_post_to_ar): a DRAFT prints with no number.
-- Staff only. Raises when nothing matches (post the orders to production first).
-- Returns { invoices: [{ ar_transaction_id, document_number (null for a DRAFT), status, customer_id, customer_name, customer_number, production_date,
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

    UPDATE om_production_runs r SET packaging_printed_at = now()
     WHERE r.tenant_id = p_tenant_id AND r.production_date BETWEEN p_from AND p_to AND (v_code IS NULL OR r.production_code = v_code)
       AND EXISTS (SELECT 1 FROM ar_transactions t WHERE t.production_run_id = r.production_run_id AND t.transaction_type = 'INV'
                      AND t.status IN ('DRAFT', 'OPEN') AND t.customer_id = ANY (p_customer_ids));

    SELECT COALESCE(jsonb_agg(inv.obj ORDER BY inv.customer_name, inv.production_date, inv.production_code), '[]'::jsonb)
      INTO v_out
      FROM (
        SELECT c.customer_name, r.production_date, r.production_code,
               jsonb_build_object(
                 'ar_transaction_id', t.ar_transaction_id, 'document_number', t.document_number, 'status', t.status,
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
         WHERE t.tenant_id = p_tenant_id AND t.transaction_type = 'INV' AND t.status IN ('DRAFT', 'OPEN')
           AND t.customer_id = ANY (p_customer_ids)
           AND r.production_date BETWEEN p_from AND p_to AND (v_code IS NULL OR r.production_code = v_code)
      ) inv;

    IF jsonb_array_length(v_out) = 0 THEN
        RAISE EXCEPTION 'No invoices found for the selection. Post the orders to production first.';
    END IF;
    UPDATE ar_transactions SET printed_at = now()
     WHERE tenant_id = p_tenant_id
       AND ar_transaction_id IN (SELECT (x ->> 'ar_transaction_id')::bigint FROM jsonb_array_elements(v_out) x);
    RETURN jsonb_build_object('invoices', v_out, 'newly_numbered', 0);
END;
$function$;
