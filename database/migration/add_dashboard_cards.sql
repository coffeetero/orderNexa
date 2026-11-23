-- =====================================================================================
-- Dashboard cards with real data: AR Aging, Customer Accounts (balance and over 90 days) and Today's Orders.
-- No new table or column. SECURITY INVOKER: row security limits both to the caller's company, areas and customer scope.
-- Apply after add_documents_and_reports.sql.
-- =====================================================================================
SET search_path = bps, public;

-- The company's "today" (its own time zone) and its production run date: orders whose production date is today.
CREATE OR REPLACE FUNCTION bps.om_orders_today_get(p_tenant_id bigint, p_limit integer DEFAULT 8) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_today date := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN (WITH o AS (
      SELECT order_id, order_number, customer_name, production_code, quantity, amount, po_number
        FROM bps.om_orders WHERE tenant_id = p_tenant_id AND production_date = v_today)
    SELECT jsonb_build_object('today', v_today, 'order_count', (SELECT count(*) FROM o), 'total_amount', COALESCE((SELECT sum(amount) FROM o), 0),
      'orders', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.production_code, x.order_number)
                            FROM (SELECT * FROM o ORDER BY production_code, order_number LIMIT GREATEST(p_limit, 1)) x), '[]'::jsonb)));
END $$;

-- Aging buckets for every active account that has an invoice up to today, and the p_limit accounts owing the most.
CREATE OR REPLACE FUNCTION bps.ar_dashboard_get(p_tenant_id bigint, p_limit integer DEFAULT 8) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_today date := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date; v_ids bigint[]; v_aging jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  SELECT COALESCE(array_agg((e ->> 'customer_id')::bigint), '{}'::bigint[]) INTO v_ids
    FROM jsonb_array_elements(bps.fnd_report_accounts_get(p_tenant_id, true, NULL, v_today)) e;
  v_aging := bps.ar_aging_get(p_tenant_id, v_ids, v_today);
  RETURN jsonb_build_object('as_of', v_today, 'totals', v_aging -> 'totals',
    'accounts', COALESCE((SELECT jsonb_agg(jsonb_build_object('customer_id', a ->> 'customer_id', 'customer_name', a ->> 'customer_name',
                  'total', a -> 'total', 'd90_plus', a -> 'd90_plus') ORDER BY (a ->> 'total')::numeric DESC, a ->> 'customer_name')
            FROM (SELECT a FROM jsonb_array_elements(v_aging -> 'accounts') a WHERE (a ->> 'total')::numeric <> 0
                   ORDER BY (a ->> 'total')::numeric DESC, a ->> 'customer_name' LIMIT GREATEST(p_limit, 1)) s), '[]'::jsonb));
END $$;

REVOKE EXECUTE ON FUNCTION bps.om_orders_today_get(bigint, integer), bps.ar_dashboard_get(bigint, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION bps.om_orders_today_get(bigint, integer), bps.ar_dashboard_get(bigint, integer) TO authenticated, service_role, bps_dev;
