-- ============================================================
-- om_dashboard_metrics_get (Dashboard metric cards and Production Summary)
-- Each figure with the one it is compared to; change_pct is NULL when the comparison is zero.
--   revenue:   invoices dated this month to today vs the same days of last month
--   orders:    orders for production today vs yesterday
--   customers: accounts (top level) with an order for production in the last 30 days vs the 30 days before
--   units:     units ordered for production today vs yesterday
--   avg_order: average order amount, production this month to today vs the same days of last month
--   top_items: the 5 items with the most units for production today (pct = share of the largest)
-- "Today" is the company's own date (its time zone). SECURITY INVOKER: row security limits every figure to the
-- caller's company and customer scope. No new table or column.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_dashboard_metrics_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_today      date := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date;
    v_month      date;
    v_prev_month date;
    v_prev_to    date;   -- the same day of last month (or its last day)
    r            record;
    v_rev        record;
    v_cus        record;
    v_avg        record;
    v_top        jsonb;
BEGIN
    PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    v_month      := date_trunc('month', v_today)::date;
    v_prev_month := (v_month - interval '1 month')::date;
    v_prev_to    := LEAST((v_prev_month + (v_today - v_month))::date, (v_month - 1));

    SELECT COALESCE(sum(amount) FILTER (WHERE transaction_date >= v_month), 0)                           AS cur,
           COALESCE(sum(amount) FILTER (WHERE transaction_date BETWEEN v_prev_month AND v_prev_to), 0)  AS prev
      INTO v_rev
      FROM bps.ar_transactions
     WHERE tenant_id = p_tenant_id AND transaction_type = 'INV' AND status <> 'CANCELLED'
       AND transaction_date BETWEEN v_prev_month AND v_today;

    SELECT count(*) FILTER (WHERE production_date = v_today)                       AS orders_today,
           count(*) FILTER (WHERE production_date = v_today - 1)                   AS orders_yesterday,
           COALESCE(sum(quantity) FILTER (WHERE production_date = v_today), 0)     AS units_today,
           COALESCE(sum(quantity) FILTER (WHERE production_date = v_today - 1), 0) AS units_yesterday
      INTO r
      FROM bps.om_orders
     WHERE tenant_id = p_tenant_id AND production_date BETWEEN v_today - 1 AND v_today;

    SELECT count(DISTINCT COALESCE(c.top_customer_id, c.customer_id)) FILTER (WHERE o.production_date > v_today - 30) AS cur,
           count(DISTINCT COALESCE(c.top_customer_id, c.customer_id)) FILTER (WHERE o.production_date <= v_today - 30) AS prev
      INTO v_cus
      FROM bps.om_orders o JOIN bps.fnd_customers c ON c.customer_id = o.customer_id
     WHERE o.tenant_id = p_tenant_id AND o.production_date > v_today - 60 AND o.production_date <= v_today;

    SELECT avg(amount) FILTER (WHERE production_date >= v_month)                          AS cur,
           avg(amount) FILTER (WHERE production_date BETWEEN v_prev_month AND v_prev_to)  AS prev
      INTO v_avg
      FROM bps.om_orders
     WHERE tenant_id = p_tenant_id AND production_date BETWEEN v_prev_month AND v_today;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('item_description', t.item_description, 'quantity', t.qty,
                                                 'pct', round(100 * t.qty / NULLIF(t.top, 0)))
                              ORDER BY t.qty DESC), '[]'::jsonb)
      INTO v_top
      FROM (SELECT l.item_description, sum(l.quantity) AS qty, max(sum(l.quantity)) OVER () AS top
              FROM bps.om_orders o JOIN bps.om_order_lines l ON l.tenant_id = o.tenant_id AND l.order_id = o.order_id
             WHERE o.tenant_id = p_tenant_id AND o.production_date = v_today
             GROUP BY l.item_description
             ORDER BY qty DESC LIMIT 5) t;

    RETURN jsonb_build_object(
        'today', v_today,
        'revenue',   jsonb_build_object('value', v_rev.cur, 'previous', v_rev.prev, 'change_pct', round(100 * (v_rev.cur - v_rev.prev) / NULLIF(v_rev.prev, 0), 1)),
        'orders',    jsonb_build_object('value', r.orders_today, 'previous', r.orders_yesterday, 'change_pct', round(100.0 * (r.orders_today - r.orders_yesterday) / NULLIF(r.orders_yesterday, 0), 1)),
        'customers', jsonb_build_object('value', v_cus.cur, 'previous', v_cus.prev, 'change_pct', round(100.0 * (v_cus.cur - v_cus.prev) / NULLIF(v_cus.prev, 0), 1)),
        'units',     jsonb_build_object('value', r.units_today, 'previous', r.units_yesterday, 'change_pct', round(100 * (r.units_today - r.units_yesterday) / NULLIF(r.units_yesterday, 0), 1)),
        'avg_order', jsonb_build_object('value', round(COALESCE(v_avg.cur, 0), 2), 'previous', round(COALESCE(v_avg.prev, 0), 2), 'change_pct', round(100 * (v_avg.cur - v_avg.prev) / NULLIF(v_avg.prev, 0), 1)),
        'top_items', v_top);
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_dashboard_metrics_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_dashboard_metrics_get(bigint) TO authenticated, service_role, bps_dev;
