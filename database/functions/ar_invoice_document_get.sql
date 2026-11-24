-- ============================================================
-- ar_invoice_document_get
-- The invoice as printed: header, customer, lines and the invoice amount.
-- An invoice counts at its amount once it is issued (not DRAFT or CANCELLED).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_invoice_document_get(p_tenant_id bigint, p_ar_transaction_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE t bps.ar_transactions; c bps.fnd_customers; v_lines jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  SELECT * INTO t FROM bps.ar_transactions WHERE tenant_id = p_tenant_id AND ar_transaction_id = p_ar_transaction_id AND transaction_type = 'INV';
  IF NOT FOUND THEN RAISE EXCEPTION 'Invoice not found'; END IF;
  SELECT * INTO c FROM bps.fnd_customers WHERE customer_id = COALESCE((SELECT top_customer_id FROM bps.fnd_customers WHERE customer_id = t.customer_id), t.customer_id);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('line', l.line_number, 'description', l.item_description, 'quantity', l.quantity, 'unit_price', l.unit_price, 'amount', l.amount) ORDER BY l.line_number), '[]'::jsonb)
    INTO v_lines FROM bps.ar_transaction_lines l WHERE l.ar_transaction_id = t.ar_transaction_id;
  RETURN jsonb_build_object('ar_transaction_id', t.ar_transaction_id, 'document_number', t.document_number, 'transaction_date', t.transaction_date,
    'due_date', t.due_date, 'status', t.status, 'customer_id', c.customer_id, 'customer_name', c.customer_name, 'customer_number', c.customer_number,
    'billed_customer_id', t.customer_id, 'amount', t.amount, 'lines', v_lines,
    'company_name', (SELECT tenant_name FROM bps.fnd_tenants WHERE tenant_id = p_tenant_id));
END $function$
;
REVOKE EXECUTE ON FUNCTION bps.ar_invoice_document_get(bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_invoice_document_get(bigint,bigint) TO authenticated, service_role, bps_dev;
