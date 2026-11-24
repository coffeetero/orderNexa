-- ============================================================
-- ar_statement_get
-- Open-item statement for an account as of a date, like the old BPS statement: every invoice, credit memo and unapplied
-- payment that still has an open amount, grouped by week (Monday to Sunday) with a subtotal per week.
-- total_due is the sum of the open items, so it always equals the aging total.
-- Returns { customer_id, customer_name, customer_number, as_of, weeks: [{ week_start, week_end, subtotal, items: [
--   { date, type, number, amount, open }] }], total_due, aging }.
-- ============================================================
DROP FUNCTION IF EXISTS bps.ar_statement_get(bigint, bigint, date, date);

CREATE OR REPLACE FUNCTION bps.ar_statement_get(p_tenant_id bigint, p_account_id bigint, p_as_of date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_cust record; v_weeks jsonb; v_total numeric; v_aging jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  SELECT customer_id, customer_name, customer_number INTO v_cust FROM bps.fnd_customers
   WHERE tenant_id = p_tenant_id AND customer_id = p_account_id AND upper(btrim(customer_type)) = 'ACCOUNT';
  IF NOT FOUND THEN RAISE EXCEPTION 'Account not found'; END IF;

  WITH items AS (
    SELECT i.*, date_trunc('week', i.transaction_date)::date AS week_start
      FROM bps.ar_report_open_items(p_tenant_id, ARRAY[p_account_id], p_as_of) i
     WHERE i.open_amount <> 0
  ), weeks AS (
    SELECT week_start, SUM(open_amount) AS subtotal,
           jsonb_agg(jsonb_build_object('date', transaction_date, 'type', transaction_type, 'number', document_number,
                                        'amount', amount, 'open', open_amount) ORDER BY transaction_date, document_number) AS items
      FROM items GROUP BY week_start
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('week_start', week_start, 'week_end', week_start + 6, 'subtotal', subtotal, 'items', items)
                            ORDER BY week_start), '[]'::jsonb),
         COALESCE(SUM(subtotal), 0)
    INTO v_weeks, v_total FROM weeks;

  SELECT (bps.ar_aging_get(p_tenant_id, ARRAY[p_account_id], p_as_of) -> 'totals') INTO v_aging;
  RETURN jsonb_build_object('customer_id', v_cust.customer_id, 'customer_name', v_cust.customer_name, 'customer_number', v_cust.customer_number,
    'as_of', p_as_of, 'weeks', v_weeks, 'total_due', v_total, 'aging', v_aging);
END $function$
;
REVOKE EXECUTE ON FUNCTION bps.ar_statement_get(bigint, bigint, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_statement_get(bigint, bigint, date) TO authenticated, service_role, bps_dev;
