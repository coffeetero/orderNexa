-- ============================================================
-- ar_report_open_items
-- Open invoices, credit memos and unapplied payments per account as of a date, with paid and open amounts.
-- Feeds statements, aging and open balances, so all three give the same total.
-- An invoice counts at its amount once it is issued (not DRAFT or CANCELLED).
-- A payment shows as a credit (negative amount) for the part not applied to an invoice; its ar_transaction_id is NULL.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_report_open_items(p_tenant_id bigint, p_account_ids bigint[], p_as_of date)
 RETURNS TABLE(account_id bigint, ar_transaction_id bigint, document_number text, transaction_type text, transaction_date date, due_date date, amount numeric, paid numeric, open_amount numeric, days_past_due integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
  WITH RECURSIVE tree(account_id, customer_id) AS (
    SELECT c.customer_id, c.customer_id FROM bps.fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
    UNION ALL
    SELECT tree.account_id, c.customer_id FROM bps.fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ), docs AS (
    SELECT tree.account_id, t.ar_transaction_id, t.document_number, t.transaction_type, t.transaction_date,
           COALESCE(t.due_date, t.transaction_date) AS due_date,
           t.amount AS amount,
           CASE t.transaction_type WHEN 'INV' THEN COALESCE((SELECT SUM(pa.applied_amount) FROM bps.ar_payment_applications pa
                 WHERE pa.tenant_id = p_tenant_id AND pa.ar_transaction_id = t.ar_transaction_id AND pa.applied_at::date <= p_as_of), 0) ELSE 0 END AS paid
      FROM bps.ar_transactions t JOIN tree ON tree.customer_id = t.customer_id
     WHERE t.tenant_id = p_tenant_id AND t.status NOT IN ('DRAFT','CANCELLED') AND t.transaction_type IN ('INV','CM') AND t.transaction_date <= p_as_of
    UNION ALL
    SELECT tree.account_id, NULL::bigint, COALESCE(p.payment_number, p.reference_number, 'Payment'), 'PMT', p.payment_date, p.payment_date,
           -p.amount,
           -COALESCE((SELECT SUM(pa.applied_amount) FROM bps.ar_payment_applications pa
                 WHERE pa.tenant_id = p_tenant_id AND pa.ar_payment_id = p.ar_payment_id AND pa.applied_at::date <= p_as_of), 0)
      FROM bps.ar_payments p JOIN tree ON tree.customer_id = p.customer_id
     WHERE p.tenant_id = p_tenant_id AND p.payment_date <= p_as_of
  )
  SELECT d.account_id, d.ar_transaction_id, d.document_number, d.transaction_type, d.transaction_date, d.due_date, d.amount, d.paid,
         d.amount - d.paid, (p_as_of - d.due_date)
    FROM docs d
$function$
;
REVOKE EXECUTE ON FUNCTION bps.ar_report_open_items(bigint,bigint[],date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_report_open_items(bigint,bigint[],date) TO authenticated, service_role, bps_dev;
