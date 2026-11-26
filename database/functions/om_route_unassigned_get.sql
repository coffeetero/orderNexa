-- ============================================================
-- om_route_unassigned_get
-- Routes Maintenance › Unassigned: active own-fleet ship-to locations (accounts and departments) that have no stop on
-- any route for a day of week + production code, so nobody falls off a route. A department with no stop of its own is
-- covered by its nearest ancestor's stop (Process run stamps it with that stop). The delivery method follows
-- om_customer_delivery_method (own, else inherited, else the company's own-fleet default).
-- p_ordering_only (default true): only those with an order for this production code delivered on this day of week in the
-- last 8 weeks, or an active standing order for it.
-- One pass over the company's customer tree; fast for thousands of customers.
-- Returns { day_of_week, production_code, ordering_only,
--   customers: [{ customer_id, customer_number, customer_name, customer_type, account_name, last_order_date }] }
--   (most recent order first).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_route_unassigned_get(p_tenant_id bigint, p_dow text, p_code text, p_ordering_only boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me       bigint  := bps.om_route_check(p_tenant_id, 'R');
  v_code     text    := bps.om_route_slot_check(p_tenant_id, p_dow, p_code);
  v_dow      text    := upper(btrim(p_dow));
  v_days     constant text[] := ARRAY['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  v_after    integer;
  v_prod_dow text;
  v_default  text;
  v_list     jsonb;
BEGIN
  SELECT delivery_days_after INTO v_after FROM om_production_codes WHERE tenant_id = p_tenant_id AND production_code = v_code;
  -- standing orders are kept by production day: the production day whose delivery falls on v_dow
  v_prod_dow := v_days[((array_position(v_days, v_dow) - 1 - COALESCE(v_after, 0)) % 7 + 7) % 7 + 1];
  SELECT m.delivery_method_code INTO v_default FROM om_delivery_methods m
   WHERE m.tenant_id = p_tenant_id AND m.is_own_fleet AND m.is_active ORDER BY m.delivery_method_code LIMIT 1;

  WITH RECURSIVE tree AS (
    SELECT c.customer_id, c.customer_type, c.is_active, c.customer_number, c.customer_name, c.customer_name AS account_name,
           (SELECT m.delivery_method_code FROM om_delivery_methods m
             WHERE m.tenant_id = p_tenant_id AND m.delivery_method_code = c.delivery_method_code AND m.is_active) AS method,
           EXISTS (SELECT 1 FROM om_route_stops s WHERE s.tenant_id = p_tenant_id AND s.day_of_week = v_dow
                      AND s.production_code = v_code AND s.ship_to_customer_id = c.customer_id) AS has_stop,
           0 AS depth
      FROM fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_parent_id IS NULL
    UNION ALL
    SELECT c.customer_id, c.customer_type, c.is_active, c.customer_number, c.customer_name, tree.account_name,
           COALESCE((SELECT m.delivery_method_code FROM om_delivery_methods m
                      WHERE m.tenant_id = p_tenant_id AND m.delivery_method_code = c.delivery_method_code AND m.is_active), tree.method),
           tree.has_stop OR EXISTS (SELECT 1 FROM om_route_stops s WHERE s.tenant_id = p_tenant_id AND s.day_of_week = v_dow
                                       AND s.production_code = v_code AND s.ship_to_customer_id = c.customer_id),
           tree.depth + 1
      FROM fnd_customers c JOIN tree ON c.customer_parent_id = tree.customer_id
     WHERE c.tenant_id = p_tenant_id AND tree.depth < 10
  ), cand AS (
    SELECT t.*,
           (SELECT max(o.production_date) FROM om_orders o
             WHERE o.tenant_id = p_tenant_id AND o.customer_id = t.customer_id AND o.production_code = v_code) AS last_order_date
      FROM tree t
      LEFT JOIN om_delivery_methods m ON m.tenant_id = p_tenant_id AND m.delivery_method_code = COALESCE(t.method, v_default)
     WHERE t.is_active AND NOT t.has_stop AND upper(btrim(t.customer_type)) IN ('ACCOUNT', 'DEPARTMENT')
       AND COALESCE(m.is_own_fleet, COALESCE(t.method, v_default) IS NULL)
       AND (NOT COALESCE(p_ordering_only, true)
            OR EXISTS (SELECT 1 FROM om_orders o
                        WHERE o.tenant_id = p_tenant_id AND o.customer_id = t.customer_id AND o.production_code = v_code
                          AND o.production_date >= current_date - 56
                          AND bps.om_route_dow(o.production_date + COALESCE(v_after, 0)) = v_dow)
            OR EXISTS (SELECT 1 FROM om_standing_orders so
                        WHERE so.tenant_id = p_tenant_id AND so.customer_id = t.customer_id AND so.is_active
                          AND so.production_code = v_code AND so.production_dow = v_prod_dow AND so.quantity > 0
                          AND (so.effective_to IS NULL OR so.effective_to >= current_date)))
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'customer_id', customer_id, 'customer_number', customer_number, 'customer_name', customer_name,
           'customer_type', customer_type, 'account_name', CASE WHEN depth > 0 THEN account_name END,
           'last_order_date', last_order_date)
         ORDER BY last_order_date DESC NULLS LAST, upper(account_name), depth, upper(customer_name)), '[]'::jsonb)
    INTO v_list FROM cand;

  RETURN jsonb_build_object('day_of_week', v_dow, 'production_code', v_code, 'ordering_only', COALESCE(p_ordering_only, true),
                            'customers', v_list);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.om_route_unassigned_get(bigint, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_route_unassigned_get(bigint, text, text, boolean) TO authenticated, service_role, bps_dev;
