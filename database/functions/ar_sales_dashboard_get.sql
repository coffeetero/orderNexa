-- ============================================================
-- ar_sales_dashboard_get
-- Dashboard sales charts: year to date (Jan 1 to the tenant's today) against the same days of last year.
-- Sales = issued invoices less credit memos (ar_transactions INV + CM, not DRAFT or CANCELLED), by document date.
-- A document counts for the account it belongs to: its own customer if that is an account, else the account above it.
--
-- p_account_id: NULL = all accounts; else the monthly figures for that account only (segments and items stay company-wide).
-- Returns {
--   as_of, last_as_of (same day last year), year, last_year,
--   months:   [{ month (1-12), this, last }]                  Jan .. the as-of month
--   totals:   { this, last }                                  for the months above (all accounts or the one asked for)
--   accounts: [{ customer_id, customer_name, this }]          accounts with sales in either period, this year's first (the picker)
--   segments: [{ code, label, this, last }]                   every segment with sales, Unassigned (code null) last
--   items:    [{ item_id, name, this, last, other }]          top 7 items by this year's sales, then one 'All others' row
-- }
-- Staff only.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_sales_dashboard_get(p_tenant_id bigint, p_account_id bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date;
  v_from  date;
  v_last  date;
  v_lfrom date;
  v_res   jsonb;
BEGIN
  IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
    RAISE EXCEPTION 'Only tenant staff can see sales figures';
  END IF;
  v_from  := date_trunc('year', v_today)::date;
  v_last  := (v_today - interval '1 year')::date;
  v_lfrom := date_trunc('year', v_last)::date;

  WITH RECURSIVE tree(account_id, customer_id) AS (
    SELECT c.customer_id, c.customer_id FROM fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) = 'ACCOUNT'
    UNION ALL
    SELECT tree.account_id, c.customer_id FROM fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ), docs AS (
    SELECT t.ar_transaction_id, t.transaction_type, t.amount, tree.account_id,
           extract(month FROM t.transaction_date)::int AS month,
           (t.transaction_date >= v_from) AS is_this
      FROM ar_transactions t JOIN tree ON tree.customer_id = t.customer_id
     WHERE t.tenant_id = p_tenant_id AND t.status NOT IN ('DRAFT', 'CANCELLED') AND t.transaction_type IN ('INV', 'CM')
       AND (t.transaction_date BETWEEN v_from AND v_today OR t.transaction_date BETWEEN v_lfrom AND v_last)
  ), lines AS (
    -- credit memo lines reduce sales whatever sign they were stored with
    SELECT d.is_this, l.item_id, CASE WHEN d.transaction_type = 'CM' THEN -abs(l.amount) ELSE l.amount END AS amount
      FROM docs d JOIN ar_transaction_lines l ON l.ar_transaction_id = d.ar_transaction_id
     WHERE l.item_id IS NOT NULL
  ), item_tot AS (
    SELECT item_id, sum(amount) FILTER (WHERE is_this) AS this, sum(amount) FILTER (WHERE NOT is_this) AS last
      FROM lines GROUP BY item_id
  ), item_rank AS (
    SELECT it.*, row_number() OVER (ORDER BY COALESCE(it.this, 0) DESC, it.item_id) AS rn FROM item_tot it
  ), seg AS (
    SELECT a.segment_code AS code,
           sum(d.amount) FILTER (WHERE d.is_this) AS this, sum(d.amount) FILTER (WHERE NOT d.is_this) AS last
      FROM docs d JOIN fnd_customers a ON a.customer_id = d.account_id
     GROUP BY a.segment_code
  )
  SELECT jsonb_build_object(
    'as_of', v_today, 'last_as_of', v_last,
    'year', extract(year FROM v_today)::int, 'last_year', extract(year FROM v_last)::int,
    'months', (SELECT jsonb_agg(jsonb_build_object('month', m,
                        'this', COALESCE((SELECT sum(amount) FROM docs WHERE month = m AND is_this AND (p_account_id IS NULL OR account_id = p_account_id)), 0),
                        'last', COALESCE((SELECT sum(amount) FROM docs WHERE month = m AND NOT is_this AND (p_account_id IS NULL OR account_id = p_account_id)), 0))
                      ORDER BY m)
                 FROM generate_series(1, extract(month FROM v_today)::int) m),
    'totals', jsonb_build_object(
                'this', COALESCE((SELECT sum(amount) FROM docs WHERE is_this AND (p_account_id IS NULL OR account_id = p_account_id)), 0),
                'last', COALESCE((SELECT sum(amount) FROM docs WHERE NOT is_this AND (p_account_id IS NULL OR account_id = p_account_id)), 0)),
    'accounts', COALESCE((SELECT jsonb_agg(jsonb_build_object('customer_id', x.account_id, 'customer_name', c.customer_name, 'this', x.this)
                                           ORDER BY x.this DESC, c.customer_name)
                            FROM (SELECT account_id, COALESCE(sum(amount) FILTER (WHERE is_this), 0) AS this FROM docs GROUP BY account_id
                                  HAVING sum(abs(amount)) <> 0) x
                            JOIN fnd_customers c ON c.customer_id = x.account_id), '[]'::jsonb),
    'segments', COALESCE((SELECT jsonb_agg(jsonb_build_object('code', s.code,
                                    'label', COALESCE((SELECT vv.label FROM fnd_valueset_values vv JOIN fnd_valuesets vs ON vs.valueset_id = vv.valueset_id
                                                        WHERE vs.tenant_id = p_tenant_id AND vs.valueset_code = 'CUSTOMERSEGMENT' AND vv.value = s.code),
                                                      s.code, 'Unassigned'),
                                    'this', COALESCE(s.this, 0), 'last', COALESCE(s.last, 0))
                                  ORDER BY (s.code IS NULL), COALESCE(s.this, 0) DESC)
                            FROM seg s WHERE COALESCE(s.this, 0) <> 0 OR COALESCE(s.last, 0) <> 0), '[]'::jsonb),
    'items', COALESCE((SELECT jsonb_agg(r ORDER BY ord)
                         FROM (SELECT jsonb_build_object('item_id', ir.item_id, 'name', COALESCE(i.item_name, 'Item ' || ir.item_id),
                                        'this', COALESCE(ir.this, 0), 'last', COALESCE(ir.last, 0), 'other', false) AS r, ir.rn AS ord
                                 FROM item_rank ir LEFT JOIN fnd_items i ON i.item_id = ir.item_id
                                WHERE ir.rn <= 7
                               UNION ALL
                               SELECT jsonb_build_object('item_id', NULL, 'name', 'All others',
                                        'this', COALESCE(sum(ir.this), 0), 'last', COALESCE(sum(ir.last), 0), 'other', true), 8
                                 FROM item_rank ir WHERE ir.rn > 7 HAVING count(*) > 0) q), '[]'::jsonb)
  ) INTO v_res;
  RETURN v_res;
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.ar_sales_dashboard_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_sales_dashboard_get(bigint, bigint) TO authenticated, service_role, bps_dev;
