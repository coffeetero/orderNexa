-- ============================================================
-- ar_payment_open_items_get
-- What a payment from this customer can be applied to: open invoices and available credits (credit memos and negative
-- invoices) of the customer and everything beneath it that is not itself an ACCOUNT (the same tree as the AR reports),
-- plus its earlier payments that still have unapplied cash. Oldest first.
-- Returns { invoices: [{ ar_transaction_id, document_number, customer_name, transaction_date, due_date, amount, open, allowance, allowance_reason }],
--           credits:  [{ ar_transaction_id, document_number, transaction_type, customer_name, transaction_date, amount, available }],
--           unapplied_payments: [{ ar_payment_id, payment_number, payment_date, payment_method, reference_number, amount, unapplied }] }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_payment_open_items_get(p_tenant_id bigint, p_customer_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('financials.payments', 'R') THEN RAISE EXCEPTION 'You do not have access to payments'; END IF;

  WITH RECURSIVE tree AS (
    SELECT c.customer_id FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
    UNION ALL
    SELECT c.customer_id FROM fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ), docs AS (
    -- open documents from ar_open_items (kept current by triggers; open = amount less payments, credits and allowance), so a
    -- big account with 25,000 invoices answers from its few open ones
    SELECT t.ar_transaction_id, t.document_number, t.transaction_type, t.transaction_date, t.due_date, t.amount, c.customer_name,
           o.open_amount AS open, t.allowance_amount, t.allowance_reason
      FROM ar_open_items o JOIN tree ON tree.customer_id = o.customer_id
      JOIN ar_transactions t ON t.ar_transaction_id = o.ar_transaction_id
      JOIN fnd_customers c ON c.customer_id = t.customer_id
     WHERE o.tenant_id = p_tenant_id
  ), pays AS (
    SELECT p.ar_payment_id, p.payment_number, p.payment_date, p.payment_method, p.reference_number, p.amount,
           p.amount - COALESCE((SELECT SUM(pa.applied_amount) FROM ar_payment_applications pa
                                 WHERE pa.tenant_id = p_tenant_id AND pa.ar_payment_id = p.ar_payment_id AND pa.reversed_at IS NULL), 0)
           - p.settled_amount AS unapplied
      FROM ar_payments p JOIN tree ON tree.customer_id = p.customer_id
     WHERE p.tenant_id = p_tenant_id AND p.voided_at IS NULL
  )
  SELECT jsonb_build_object(
    'invoices', COALESCE((SELECT jsonb_agg(jsonb_build_object('ar_transaction_id', d.ar_transaction_id, 'document_number', d.document_number,
                    'customer_name', d.customer_name, 'transaction_date', d.transaction_date, 'due_date', d.due_date, 'amount', d.amount, 'open', d.open,
                    'allowance', d.allowance_amount, 'allowance_reason', d.allowance_reason)
                    ORDER BY COALESCE(d.due_date, d.transaction_date), d.transaction_date, d.document_number)
                  FROM docs d WHERE d.transaction_type = 'INV' AND d.amount > 0 AND d.open > 0), '[]'::jsonb),
    'credits', COALESCE((SELECT jsonb_agg(jsonb_build_object('ar_transaction_id', d.ar_transaction_id, 'document_number', d.document_number,
                    'transaction_type', d.transaction_type, 'customer_name', d.customer_name, 'transaction_date', d.transaction_date,
                    'amount', d.amount, 'available', -d.open)
                    ORDER BY d.transaction_date, d.document_number)
                  FROM docs d WHERE (d.transaction_type = 'CM' OR d.amount < 0) AND d.open < 0), '[]'::jsonb),
    'unapplied_payments', COALESCE((SELECT jsonb_agg(jsonb_build_object('ar_payment_id', p.ar_payment_id, 'payment_number', p.payment_number,
                    'payment_date', p.payment_date, 'payment_method', p.payment_method, 'reference_number', p.reference_number,
                    'amount', p.amount, 'unapplied', p.unapplied) ORDER BY p.payment_date, p.ar_payment_id)
                  FROM pays p WHERE p.unapplied > 0), '[]'::jsonb))
    INTO v_result;
  RETURN v_result;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.ar_payment_open_items_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_payment_open_items_get(bigint, bigint) TO authenticated, service_role, bps_dev;
