-- ============================================================
-- ar_credit_find
-- Enter Credits lookup: the orders matching an order number, an invoice number or a PO number (p_kind ORDER, INVOICE or PO;
-- case-insensitive for PO, exact otherwise), newest first, at most 50. Each match carries the account the order is
-- invoiced to and its production slot, so the screen can open that customer, date and time. Staff only.
-- Returns { matches: [{ order_id, order_number, department_event, account_id, account_name, account_number,
--   production_date, production_code, invoice_number, po_number }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_credit_find(p_tenant_id bigint, p_kind text, p_value text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_kind text := UPPER(TRIM(COALESCE(p_kind, '')));
    v_q    text := UPPER(TRIM(COALESCE(p_value, '')));
    v_ids  bigint[];
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can enter credits';
    END IF;
    IF v_kind NOT IN ('ORDER', 'INVOICE', 'PO') THEN
        RAISE EXCEPTION 'Search by ORDER, INVOICE or PO';
    END IF;
    IF v_q = '' THEN
        RAISE EXCEPTION 'Enter a number to search for';
    END IF;

    IF v_kind = 'ORDER' THEN
        SELECT array_agg(o.order_id) INTO v_ids FROM om_orders o WHERE o.tenant_id = p_tenant_id AND o.order_number IN (v_q, TRIM(p_value));
    ELSIF v_kind = 'INVOICE' THEN
        SELECT array_agg(DISTINCT l.order_id) INTO v_ids
          FROM ar_transactions t JOIN ar_transaction_lines l ON l.ar_transaction_id = t.ar_transaction_id
         WHERE t.tenant_id = p_tenant_id AND t.document_number IN (v_q, TRIM(p_value)) AND t.transaction_type = 'INV'
           AND t.status <> 'CANCELLED' AND l.order_id IS NOT NULL;
    ELSE
        SELECT array_agg(o.order_id) INTO v_ids FROM om_orders o
         WHERE o.tenant_id = p_tenant_id AND o.po_number IS NOT NULL AND UPPER(TRIM(o.po_number)) = v_q;
    END IF;

    RETURN jsonb_build_object('matches', COALESCE((
        SELECT jsonb_agg(m ORDER BY m->>'production_date' DESC, m->>'order_number')
          FROM (SELECT jsonb_build_object(
                         'order_id', o.order_id, 'order_number', o.order_number, 'department_event', o.department_event,
                         'account_id', a.customer_id, 'account_name', a.customer_name, 'account_number', a.customer_number,
                         'production_date', o.production_date, 'production_code', o.production_code,
                         'invoice_number', bps.om_order_invoice_get(p_tenant_id, o.order_id) ->> 'invoice_number',
                         'po_number', o.po_number) AS m
                  FROM om_orders o
                  JOIN fnd_customers a ON a.tenant_id = o.tenant_id AND a.customer_id = bps.om_customer_invoice_owner(p_tenant_id, o.customer_id)
                 WHERE o.tenant_id = p_tenant_id AND o.order_id = ANY (v_ids)
                 ORDER BY o.production_date DESC, o.order_number
                 LIMIT 50) x
    ), '[]'::jsonb));
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.ar_credit_find(bigint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_credit_find(bigint, text, text) TO authenticated, service_role;
