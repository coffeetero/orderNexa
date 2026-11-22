-- ============================================================
-- ar_document_lookup
-- Finds invoices by invoice number or by an order number on them (case-insensitive, exact), for the person on the phone
-- ("the kitchen was short 2 breads"). Staff only.
-- Returns { invoices: [{ ar_transaction_id, document_number, status, customer_name, delivery_date, amount, recognized_amount,
--   credited_amount, lines: [{ ar_transaction_line_id, source_type, order_number, department_event, item_description, quantity,
--   unit_price, amount, shipped_quantity, credited_quantity }], credits: [{ document_number, amount, reason }] }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_document_lookup(p_tenant_id bigint, p_search text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_q text := UPPER(TRIM(COALESCE(p_search, '')));
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can look up documents';
    END IF;
    IF v_q = '' THEN
        RAISE EXCEPTION 'Enter an invoice number or an order number';
    END IF;

    RETURN jsonb_build_object('invoices', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                   'ar_transaction_id', t.ar_transaction_id, 'document_number', t.document_number, 'status', t.status,
                   'customer_name', c.customer_name, 'delivery_date', t.transaction_date, 'amount', t.amount,
                   'recognized_amount', bps.ar_invoice_recognized_amount(t.ar_transaction_id),
                   'credited_amount', COALESCE((SELECT -SUM(ct.amount) FROM ar_transactions ct WHERE ct.applies_to_ar_transaction_id = t.ar_transaction_id AND ct.status <> 'CANCELLED'), 0),
                   'lines', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                'ar_transaction_line_id', l.ar_transaction_line_id, 'source_type', l.source_type,
                                'order_number', l.snapshot_data ->> 'order_number', 'department_event', l.snapshot_data ->> 'department_event',
                                'item_description', l.item_description, 'quantity', l.quantity, 'unit_price', l.unit_price, 'amount', l.amount,
                                'shipped_quantity', sl.shipped_quantity,
                                'credited_quantity', COALESCE((SELECT SUM(cl.quantity) FROM ar_transaction_lines cl
                                                                 JOIN ar_transactions ct ON ct.ar_transaction_id = cl.ar_transaction_id AND ct.status <> 'CANCELLED'
                                                                WHERE ct.applies_to_ar_transaction_id = t.ar_transaction_id
                                                                  AND (cl.snapshot_data ->> 'credits_line_id')::bigint = l.ar_transaction_line_id), 0))
                                ORDER BY l.line_number)
                              FROM ar_transaction_lines l LEFT JOIN om_shipment_lines sl ON sl.shipment_line_id = l.shipment_line_id
                             WHERE l.ar_transaction_id = t.ar_transaction_id), '[]'::jsonb),
                   'credits', COALESCE((SELECT jsonb_agg(jsonb_build_object('document_number', ct.document_number, 'amount', ct.amount,
                                'reason', (SELECT cl.snapshot_data ->> 'reason' FROM ar_transaction_lines cl WHERE cl.ar_transaction_id = ct.ar_transaction_id LIMIT 1))
                                ORDER BY ct.document_number)
                              FROM ar_transactions ct WHERE ct.applies_to_ar_transaction_id = t.ar_transaction_id AND ct.status <> 'CANCELLED'), '[]'::jsonb)
               ) ORDER BY t.document_number)
          FROM ar_transactions t
          JOIN fnd_customers c ON c.customer_id = t.customer_id AND c.tenant_id = t.tenant_id
         WHERE t.tenant_id = p_tenant_id AND t.transaction_type = 'INV' AND t.status NOT IN ('DRAFT', 'CANCELLED')
           AND (UPPER(t.document_number) = v_q
                OR EXISTS (SELECT 1 FROM ar_transaction_lines ol WHERE ol.ar_transaction_id = t.ar_transaction_id AND UPPER(ol.snapshot_data ->> 'order_number') = v_q))
    ), '[]'::jsonb));
END;
$function$;
