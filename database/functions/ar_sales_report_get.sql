-- ============================================================
-- ar_sales_report_get
-- Sales by account and item over a date range.
-- An invoice counts at its amount once it is issued (not DRAFT or CANCELLED).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_sales_report_get(p_tenant_id bigint, p_account_ids bigint[], p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_rows jsonb; v_tot jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF p_from > p_to THEN RAISE EXCEPTION 'The from date is after the to date'; END IF;
  WITH RECURSIVE tree(account_id, customer_id) AS (
    SELECT c.customer_id, c.customer_id FROM bps.fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
    UNION ALL
    SELECT tree.account_id, c.customer_id FROM bps.fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ), docs AS (
    SELECT tree.account_id, t.ar_transaction_id, t.transaction_type,
           t.amount AS amt
      FROM bps.ar_transactions t JOIN tree ON tree.customer_id = t.customer_id
     WHERE t.tenant_id = p_tenant_id AND t.status NOT IN ('DRAFT','CANCELLED') AND t.transaction_type IN ('INV','CM')
       AND t.transaction_date BETWEEN p_from AND p_to
  ), items AS (
    SELECT d.account_id, COALESCE(NULLIF(btrim(l.item_description), ''), 'Item') AS item, SUM(l.quantity) AS qty, SUM(l.amount) AS amt
      FROM docs d JOIN bps.ar_transaction_lines l ON l.ar_transaction_id = d.ar_transaction_id
     WHERE d.transaction_type = 'INV' AND l.source_type = 'ITEM' GROUP BY d.account_id, 2
  ), per AS (
    SELECT c.customer_id, c.customer_name, c.customer_number,
      COALESCE(SUM(d.amt) FILTER (WHERE d.transaction_type = 'INV'), 0) AS invoiced,
      COALESCE(SUM(d.amt) FILTER (WHERE d.transaction_type = 'CM'), 0) AS credits,
      COALESCE(SUM(d.amt), 0) AS net,
      COALESCE((SELECT jsonb_agg(jsonb_build_object('item', i.item, 'quantity', i.qty, 'amount', i.amt) ORDER BY i.amt DESC)
                  FROM items i WHERE i.account_id = c.customer_id), '[]'::jsonb) AS items
      FROM bps.fnd_customers c LEFT JOIN docs d ON d.account_id = c.customer_id
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
     GROUP BY c.customer_id, c.customer_name, c.customer_number)
  SELECT COALESCE(jsonb_agg(to_jsonb(per) ORDER BY per.net DESC, per.customer_name), '[]'::jsonb),
         jsonb_build_object('invoiced', COALESCE(SUM(invoiced),0), 'credits', COALESCE(SUM(credits),0), 'net', COALESCE(SUM(net),0))
    INTO v_rows, v_tot FROM per;
  RETURN jsonb_build_object('from', p_from, 'to', p_to, 'accounts', v_rows, 'totals', v_tot);
END $function$
;
REVOKE EXECUTE ON FUNCTION bps.ar_sales_report_get(bigint,bigint[],date,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_sales_report_get(bigint,bigint[],date,date) TO authenticated, service_role, bps_dev;
