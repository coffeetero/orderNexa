-- ============================================================
-- ar_report_open_items
-- Open invoices, credit memos and unapplied payments per account as of a date, with paid and open amounts.
-- Feeds statements, aging and open balances, so all three give the same total.
-- An invoice counts at its amount once it is issued (not DRAFT or CANCELLED).
-- A payment shows as a credit (negative amount) for the part not applied to an invoice; its ar_transaction_id is NULL.
-- Unapplied (reversed) applications count until the day they were reversed; a voided payment until the day it was voided.
-- Credit applications (ar_credit_applications) pay the invoice and use up the credit memo.
--
-- Two ways to the same answer:
--   ar_report_open_items_full  works through every document since the first one (any date; returns settled documents too, at 0 open)
--   ar_report_open_items       for today or later reads bps.ar_open_items, kept current by triggers, and returns only documents with
--                              something open; for an earlier date it calls the full calculation. Callers use open items only.
-- The health check ar_open_items_drift compares the two.
-- ar_payment_id is set on payment rows (ar_transaction_id is NULL there).
-- ============================================================
-- the result gained ar_payment_id: a changed result type needs the functions dropped first (nothing depends on them)
DROP FUNCTION IF EXISTS bps.ar_report_open_items(bigint, bigint[], date);
DROP FUNCTION IF EXISTS bps.ar_report_open_items_full(bigint, bigint[], date);
CREATE OR REPLACE FUNCTION bps.ar_report_open_items_full(p_tenant_id bigint, p_account_ids bigint[], p_as_of date)
 RETURNS TABLE(account_id bigint, ar_transaction_id bigint, document_number text, transaction_type text, transaction_date date, due_date date, amount numeric, paid numeric, open_amount numeric, days_past_due integer, ar_payment_id bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
  WITH RECURSIVE zone AS (
    -- unapply and void times are real timestamps: their day is the tenant's day
    SELECT COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC') AS tz
  ), tree(account_id, customer_id) AS (
    SELECT c.customer_id, c.customer_id FROM bps.fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
    UNION ALL
    SELECT tree.account_id, c.customer_id FROM bps.fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ), docs AS (
    SELECT tree.account_id, t.ar_transaction_id, t.document_number, t.transaction_type, t.transaction_date,
           COALESCE(t.due_date, t.transaction_date) AS due_date,
           t.amount AS amount,
           -- applications count on credit memos too: the old BPS applied credits to invoices through $0 payments
           COALESCE((SELECT SUM(pa.applied_amount) FROM bps.ar_payment_applications pa
                 WHERE pa.tenant_id = p_tenant_id AND pa.ar_transaction_id = t.ar_transaction_id AND pa.applied_at::date <= p_as_of
                   AND (pa.reversed_at IS NULL OR (pa.reversed_at AT TIME ZONE (SELECT tz FROM zone))::date > p_as_of)), 0)
           -- credit applications: paid on the invoice, used (negative paid) on the credit
           + COALESCE((SELECT SUM(ca.applied_amount) FROM bps.ar_credit_applications ca
                 WHERE ca.tenant_id = p_tenant_id AND ca.ar_transaction_id = t.ar_transaction_id
                   AND ca.applied_at::date <= p_as_of AND (ca.reversed_at IS NULL OR (ca.reversed_at AT TIME ZONE (SELECT tz FROM zone))::date > p_as_of)), 0)
           - COALESCE((SELECT SUM(ca.applied_amount) FROM bps.ar_credit_applications ca
                 WHERE ca.tenant_id = p_tenant_id AND ca.credit_ar_transaction_id = t.ar_transaction_id
                   AND ca.applied_at::date <= p_as_of AND (ca.reversed_at IS NULL OR (ca.reversed_at AT TIME ZONE (SELECT tz FROM zone))::date > p_as_of)), 0)
           -- an allowance counts as paid from the day it was given
           + CASE WHEN t.allowance_amount <> 0 AND (t.allowance_at IS NULL OR (t.allowance_at AT TIME ZONE (SELECT tz FROM zone))::date <= p_as_of)
                  THEN t.allowance_amount ELSE 0 END AS paid,
           NULL::bigint AS ar_payment_id
      FROM bps.ar_transactions t JOIN tree ON tree.customer_id = t.customer_id
     WHERE t.tenant_id = p_tenant_id AND t.status NOT IN ('DRAFT','CANCELLED') AND t.transaction_type IN ('INV','CM') AND t.transaction_date <= p_as_of
    UNION ALL
    SELECT tree.account_id, NULL::bigint, COALESCE(p.payment_number, p.reference_number, 'Payment'), 'PMT', p.payment_date, p.payment_date,
           -p.amount,
           -COALESCE((SELECT SUM(pa.applied_amount) FROM bps.ar_payment_applications pa
                 WHERE pa.tenant_id = p_tenant_id AND pa.ar_payment_id = p.ar_payment_id AND pa.applied_at::date <= p_as_of
                   AND (pa.reversed_at IS NULL OR (pa.reversed_at AT TIME ZONE (SELECT tz FROM zone))::date > p_as_of)), 0),
           p.ar_payment_id
      FROM bps.ar_payments p JOIN tree ON tree.customer_id = p.customer_id
     WHERE p.tenant_id = p_tenant_id AND p.payment_date <= p_as_of AND (p.voided_at IS NULL OR (p.voided_at AT TIME ZONE (SELECT tz FROM zone))::date > p_as_of)
  )
  SELECT d.account_id, d.ar_transaction_id, d.document_number, d.transaction_type, d.transaction_date, d.due_date, d.amount, d.paid,
         d.amount - d.paid, (p_as_of - d.due_date), d.ar_payment_id
    FROM docs d
$function$
;
REVOKE EXECUTE ON FUNCTION bps.ar_report_open_items_full(bigint,bigint[],date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_report_open_items_full(bigint,bigint[],date) TO authenticated, service_role, bps_dev;

CREATE OR REPLACE FUNCTION bps.ar_report_open_items(p_tenant_id bigint, p_account_ids bigint[], p_as_of date)
 RETURNS TABLE(account_id bigint, ar_transaction_id bigint, document_number text, transaction_type text, transaction_date date, due_date date, amount numeric, paid numeric, open_amount numeric, days_past_due integer, ar_payment_id bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  IF p_as_of < (now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC'))::date THEN
    RETURN QUERY SELECT * FROM bps.ar_report_open_items_full(p_tenant_id, p_account_ids, p_as_of);
    RETURN;
  END IF;
  RETURN QUERY
  WITH RECURSIVE tree(account_id, customer_id) AS (
    SELECT c.customer_id, c.customer_id FROM bps.fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
    UNION ALL
    SELECT tree.account_id, c.customer_id FROM bps.fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ), docs AS (
    SELECT tree.account_id, t.ar_transaction_id, t.document_number, t.transaction_type, t.transaction_date,
           COALESCE(t.due_date, t.transaction_date) AS due_date, t.amount, o.open_amount, NULL::bigint AS ar_payment_id
      FROM bps.ar_open_items o JOIN tree ON tree.customer_id = o.customer_id
      JOIN bps.ar_transactions t ON t.ar_transaction_id = o.ar_transaction_id
     WHERE o.tenant_id = p_tenant_id AND t.transaction_date <= p_as_of
    UNION ALL
    SELECT tree.account_id, NULL::bigint, COALESCE(p.payment_number, p.reference_number, 'Payment'), 'PMT', p.payment_date, p.payment_date,
           -p.amount, o.open_amount, p.ar_payment_id
      FROM bps.ar_open_items o JOIN tree ON tree.customer_id = o.customer_id
      JOIN bps.ar_payments p ON p.ar_payment_id = o.ar_payment_id
     WHERE o.tenant_id = p_tenant_id AND p.payment_date <= p_as_of
  )
  SELECT d.account_id, d.ar_transaction_id, d.document_number, d.transaction_type, d.transaction_date, d.due_date, d.amount,
         d.amount - d.open_amount, d.open_amount, (p_as_of - d.due_date), d.ar_payment_id
    FROM docs d;
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.ar_report_open_items(bigint,bigint[],date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_report_open_items(bigint,bigint[],date) TO authenticated, service_role, bps_dev;
