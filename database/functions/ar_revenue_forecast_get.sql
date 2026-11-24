-- ============================================================
-- ar_revenue_forecast_get
-- Revenue forecast from the recent invoice history.
-- An invoice counts at its amount once it is issued (not DRAFT or CANCELLED).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_revenue_forecast_get(p_tenant_id bigint, p_account_ids bigint[], p_as_of date, p_lookback_weeks integer, p_horizon_weeks integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_from date; v_mid date; v_rows jsonb; v_tot jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF p_lookback_weeks NOT BETWEEN 2 AND 104 OR p_horizon_weeks NOT BETWEEN 1 AND 52 THEN RAISE EXCEPTION 'Look-back must be 2-104 weeks and horizon 1-52 weeks'; END IF;
  v_from := p_as_of - (p_lookback_weeks * 7) + 1;
  v_mid  := v_from + ((p_lookback_weeks / 2) * 7);
  WITH RECURSIVE tree(account_id, customer_id) AS (
    SELECT c.customer_id, c.customer_id FROM bps.fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
    UNION ALL
    SELECT tree.account_id, c.customer_id FROM bps.fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND upper(btrim(c.customer_type)) <> 'ACCOUNT'
  ), docs AS (
    SELECT tree.account_id, t.transaction_date,
           t.amount AS amt
      FROM bps.ar_transactions t JOIN tree ON tree.customer_id = t.customer_id
     WHERE t.tenant_id = p_tenant_id AND t.status NOT IN ('DRAFT','CANCELLED') AND t.transaction_type IN ('INV','CM')
       AND t.transaction_date BETWEEN v_from AND p_as_of
  ), per AS (
    SELECT c.customer_id, c.customer_name, c.customer_number,
      COALESCE(SUM(d.amt), 0) AS history_total,
      ROUND(COALESCE(SUM(d.amt), 0) / p_lookback_weeks, 2) AS weekly_average,
      ROUND(COALESCE(SUM(d.amt), 0) / p_lookback_weeks * p_horizon_weeks, 2) AS projected_total,
      COALESCE(SUM(d.amt) FILTER (WHERE d.transaction_date < v_mid), 0) AS first_half,
      COALESCE(SUM(d.amt) FILTER (WHERE d.transaction_date >= v_mid), 0) AS second_half
      FROM bps.fnd_customers c LEFT JOIN docs d ON d.account_id = c.customer_id
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = ANY(p_account_ids) AND upper(btrim(c.customer_type)) = 'ACCOUNT'
     GROUP BY c.customer_id, c.customer_name, c.customer_number)
  SELECT COALESCE(jsonb_agg(to_jsonb(per) ORDER BY per.projected_total DESC, per.customer_name), '[]'::jsonb),
         jsonb_build_object('history_total', COALESCE(SUM(history_total),0), 'weekly_average', COALESCE(SUM(weekly_average),0), 'projected_total', COALESCE(SUM(projected_total),0))
    INTO v_rows, v_tot FROM per;
  RETURN jsonb_build_object('as_of', p_as_of, 'history_from', v_from, 'lookback_weeks', p_lookback_weeks, 'horizon_weeks', p_horizon_weeks, 'accounts', v_rows, 'totals', v_tot);
END $function$
;
REVOKE EXECUTE ON FUNCTION bps.ar_revenue_forecast_get(bigint,bigint[],date,integer,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_revenue_forecast_get(bigint,bigint[],date,integer,integer) TO authenticated, service_role, bps_dev;
