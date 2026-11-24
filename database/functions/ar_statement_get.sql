-- ============================================================
-- ar_statement_get
-- Open-item statement for an account as of a date, like the old BPS statement: every invoice that still has money owing,
-- grouped by week (Monday to Sunday) with a subtotal per week. With p_include_credits, credit memos, over-applied invoices
-- and unapplied payments are listed too, and total_due then equals the aging total.
-- customer_number_display applies the company's customer number mask (fnd_tenants.customer_number_mask).
-- Returns { customer_id, customer_name, customer_number, customer_number_display, address_lines, as_of, include_credits,
--   weeks: [{ week_start, week_end, subtotal, items: [{ date, type, number, amount, open }] }], total_due, aging }.
-- ============================================================
DROP FUNCTION IF EXISTS bps.ar_statement_get(bigint, bigint, date, date);
DROP FUNCTION IF EXISTS bps.ar_statement_get(bigint, bigint, date);

CREATE OR REPLACE FUNCTION bps.ar_statement_get(p_tenant_id bigint, p_account_id bigint, p_as_of date, p_include_credits boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_cust record; v_weeks jsonb; v_total numeric; v_aging jsonb; v_address text;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  SELECT c.customer_id, c.customer_name, c.customer_number, bps.fnd_customer_number_format(t.customer_number_mask, c.customer_number) AS number_display
    INTO v_cust FROM bps.fnd_customers c JOIN bps.fnd_tenants t ON t.tenant_id = c.tenant_id
   WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_account_id AND upper(btrim(c.customer_type)) = 'ACCOUNT';
  IF NOT FOUND THEN RAISE EXCEPTION 'Account not found'; END IF;

  -- billing address: the account's ADDRESS labelled Billing, else its primary address
  SELECT cp.value INTO v_address
    FROM bps.fnd_contacts k JOIN bps.fnd_contact_points cp ON cp.contact_id = k.contact_id
   WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.entity_id = p_account_id
     AND cp.type = 'ADDRESS' AND cp.is_active
   ORDER BY (cp.label = 'Billing') DESC, cp.is_primary DESC, cp.sequence
   LIMIT 1;

  WITH items AS (
    SELECT i.*, date_trunc('week', i.transaction_date)::date AS week_start
      FROM bps.ar_report_open_items(p_tenant_id, ARRAY[p_account_id], p_as_of) i
     WHERE i.open_amount > 0 OR (p_include_credits AND i.open_amount < 0)
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
    'customer_number_display', v_cust.number_display,
    'address_lines', COALESCE((SELECT jsonb_agg(l) FROM regexp_split_to_table(btrim(v_address), '\s*\n\s*') l WHERE l <> ''), '[]'::jsonb),
    'as_of', p_as_of, 'include_credits', p_include_credits, 'weeks', v_weeks, 'total_due', v_total, 'aging', v_aging);
END $function$
;
REVOKE EXECUTE ON FUNCTION bps.ar_statement_get(bigint, bigint, date, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_statement_get(bigint, bigint, date, boolean) TO authenticated, service_role, bps_dev;
