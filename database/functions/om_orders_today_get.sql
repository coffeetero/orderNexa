-- ============================================================
-- om_orders_today_get (Dashboard: Today's Orders)
-- Orders whose production date is the company's own "today" (its time zone): the count, the total, and the first p_limit orders.
-- Each order carries line_count (its order lines) and status, the furthest stage it has reached:
--   INVOICED       a line of it is on an invoice that is not cancelled
--   SHIPPED        shipped_at is set
--   IN_PRODUCTION  it is on a production run
--   OPEN           none of these
-- SECURITY INVOKER: row security limits it to the caller's company, areas and customer scope (a caller who cannot see invoices sees
-- SHIPPED at most). No new table or column.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_orders_today_get(p_tenant_id bigint, p_limit integer DEFAULT 8)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_today date := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN (WITH o AS (
      SELECT order_id, order_number, customer_name, production_code, quantity, amount, po_number, production_run_id, shipped_at
        FROM bps.om_orders WHERE tenant_id = p_tenant_id AND production_date = v_today)
    SELECT jsonb_build_object('today', v_today, 'order_count', (SELECT count(*) FROM o), 'total_amount', COALESCE((SELECT sum(amount) FROM o), 0),
      'orders', COALESCE((SELECT jsonb_agg(to_jsonb(y) ORDER BY y.production_code, y.order_number)
                            FROM (SELECT x.order_id, x.order_number, x.customer_name, x.production_code, x.quantity, x.amount, x.po_number,
                                         (SELECT count(*) FROM bps.om_order_lines l WHERE l.tenant_id = p_tenant_id AND l.order_id = x.order_id) AS line_count,
                                         CASE WHEN EXISTS (SELECT 1 FROM bps.ar_transaction_lines tl
                                                             JOIN bps.ar_transactions t ON t.tenant_id = tl.tenant_id AND t.ar_transaction_id = tl.ar_transaction_id
                                                            WHERE tl.tenant_id = p_tenant_id AND tl.order_id = x.order_id
                                                              AND t.transaction_type = 'INV' AND t.status <> 'CANCELLED') THEN 'INVOICED'
                                              WHEN x.shipped_at IS NOT NULL THEN 'SHIPPED'
                                              WHEN x.production_run_id IS NOT NULL THEN 'IN_PRODUCTION'
                                              ELSE 'OPEN' END AS status
                                    FROM (SELECT * FROM o ORDER BY production_code, order_number LIMIT GREATEST(p_limit, 1)) x) y), '[]'::jsonb)));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_orders_today_get(bigint, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_orders_today_get(bigint, integer) TO authenticated, service_role, bps_dev;
