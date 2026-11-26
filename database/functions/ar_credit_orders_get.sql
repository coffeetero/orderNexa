-- ============================================================
-- ar_credit_orders_get
-- Enter Credits: the orders of one account customer (and of its departments and sites invoiced to it) for a production
-- date and code, each with its invoice and the invoice lines that can be credited. Staff only.
--   status: NONE (not on an invoice), DRAFT (run processed, not yet numbered), or the invoice status (OPEN, PARTIAL, CLOSED).
--   Only orders on an issued invoice (not DRAFT or NONE) carry lines; a line's credited_quantity is the invoice line's
--   quantity_credited (earlier credit memos, not cancelled) and remaining_quantity = quantity - credited_quantity. item_description falls back to the item's
--   name for imported lines that only say 'INVOICE'.
-- Returns { orders: [{ order_id, order_date, order_number, department_event, po_number, customer_name, amount, invoice_id, invoice_number, status,
--   credited_amount, lines: [{ ar_transaction_line_id, source_type, item_description, quantity, unit_price, amount,
--   credited_quantity, remaining_quantity }] }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_credit_orders_get(p_tenant_id bigint, p_customer_id bigint, p_production_date date, p_production_code text)
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
        RAISE EXCEPTION 'Only tenant staff can enter credits';
    END IF;
    IF p_customer_id IS NULL OR p_production_date IS NULL OR v_code IS NULL THEN
        RAISE EXCEPTION 'Customer, production date and production time are required';
    END IF;

    RETURN jsonb_build_object('orders', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                   'order_id', o.order_id, 'order_date', o.order_date, 'order_number', o.order_number, 'department_event', o.department_event, 'po_number', o.po_number,
                   'customer_name', CASE WHEN o.customer_id = p_customer_id THEN NULL ELSE o.customer_name END,
                   'amount', o.amount,
                   'invoice_id', inv.ar_transaction_id,
                   'invoice_number', CASE WHEN inv.status = 'DRAFT' THEN NULL ELSE inv.document_number END,
                   'status', COALESCE(inv.status, 'NONE'),
                   'credited_amount', COALESCE((SELECT -SUM(cl.amount) FROM ar_transaction_lines cl
                                                  JOIN ar_transactions ct ON ct.ar_transaction_id = cl.ar_transaction_id
                                                 WHERE ct.tenant_id = p_tenant_id AND ct.transaction_type = 'CM' AND ct.status <> 'CANCELLED'
                                                   AND ct.applies_to_ar_transaction_id = inv.ar_transaction_id
                                                   AND (cl.snapshot_data ->> 'credits_line_id')::bigint IN
                                                       (SELECT il.ar_transaction_line_id FROM ar_transaction_lines il
                                                         WHERE il.ar_transaction_id = inv.ar_transaction_id AND il.order_id = o.order_id)), 0),
                   'lines', CASE WHEN inv.status IS NULL OR inv.status = 'DRAFT' THEN '[]'::jsonb ELSE COALESCE((
                       SELECT jsonb_agg(jsonb_build_object(
                                  'ar_transaction_line_id', x.ar_transaction_line_id, 'source_type', x.source_type,
                                  'item_description', x.item_name, 'quantity', x.quantity, 'unit_price', x.unit_price,
                                  'amount', x.amount, 'credited_quantity', x.credited, 'remaining_quantity', x.quantity - x.credited)
                                  ORDER BY x.line_number)
                         FROM (SELECT l.*,
                                      -- imported invoice lines say just 'INVOICE': show the item's name
                                      CASE WHEN COALESCE(UPPER(TRIM(l.item_description)), 'INVOICE') IN ('INVOICE', '')
                                           THEN COALESCE((SELECT i.item_name FROM fnd_items i WHERE i.item_id = l.item_id), l.item_description)
                                           ELSE l.item_description END AS item_name,
                                      l.quantity_credited AS credited
                                 FROM ar_transaction_lines l
                                WHERE l.tenant_id = p_tenant_id AND l.ar_transaction_id = inv.ar_transaction_id AND l.order_id = o.order_id) x
                   ), '[]'::jsonb) END
               ) ORDER BY o.order_number)
          FROM om_orders o
          LEFT JOIN LATERAL (
                SELECT t.ar_transaction_id, t.document_number, t.status
                  FROM ar_transaction_lines l
                  JOIN ar_transactions t ON t.ar_transaction_id = l.ar_transaction_id
                 WHERE l.tenant_id = p_tenant_id AND l.order_id = o.order_id AND t.transaction_type = 'INV' AND t.status <> 'CANCELLED'
                 ORDER BY (t.status = 'DRAFT'), t.ar_transaction_id DESC
                 LIMIT 1) inv ON TRUE
         WHERE o.tenant_id = p_tenant_id AND o.production_date = p_production_date AND o.production_code = v_code
           AND COALESCE(o.import_status, 'APPROVED') = 'APPROVED'
           AND bps.om_customer_invoice_owner(p_tenant_id, o.customer_id) = p_customer_id
    ), '[]'::jsonb));
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.ar_credit_orders_get(bigint, bigint, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_credit_orders_get(bigint, bigint, date, text) TO authenticated, service_role;
