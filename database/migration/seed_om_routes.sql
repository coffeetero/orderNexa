-- ============================================================
-- SEED om_routes / om_route_stops FROM LEGACY route / route_stop (Alpine Bakery)
--
-- Source: bps.route (route_id, route_desc, route_order), bps.route_stop (route_id, route_dow MON..SUN,
--         route_prdctn_cd MORNING/LUNCH/DINNER, cus_id, route_stop_no). Temporary legacy tables, dropped before production.
-- Target: bps.om_routes (code = route_order, name = route_desc, sort_order = route_order, legacy_id = route_id),
--         bps.om_route_stops (cus_id -> fnd_customers.legacy_id; stops renumbered 1..n in legacy stop order).
-- Legacy route 0 (NOT ASSIGNED) means no route and is not loaded. A customer on two routes for the same day and code
-- (legacy data allows it) is kept on the route that comes first by route_order. Codes not in om_production_codes are
-- skipped. Re-runnable: routes are matched on legacy_id; the legacy routes' stops are reloaded.
-- Prerequisite: add_routes.sql, seed_fnd_customers.sql, production codes seeded.
-- ============================================================

SET search_path = bps, public;

DO $$
DECLARE
  v_tenant_id bigint;
  v_routes    integer;
  v_stops     integer;
  v_dupes     integer;
BEGIN
  SELECT tenant_id INTO v_tenant_id FROM bps.fnd_tenants WHERE tenant_name ILIKE 'Alpine Bakery%' ORDER BY tenant_id LIMIT 1;
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'Alpine Bakery tenant not found'; END IF;

  INSERT INTO bps.om_routes (tenant_id, route_code, route_name, sort_order, legacy_id)
  SELECT v_tenant_id, r.route_order::int::text, btrim(r.route_desc), r.route_order::int, r.route_id::int
    FROM bps.route r
   WHERE r.route_id <> 0
  ON CONFLICT (tenant_id, legacy_id) WHERE legacy_id IS NOT NULL
  DO UPDATE SET route_name = EXCLUDED.route_name, sort_order = EXCLUDED.sort_order;
  GET DIAGNOSTICS v_routes = ROW_COUNT;

  DELETE FROM bps.om_route_stops s
   USING bps.om_routes r
   WHERE r.route_id = s.route_id AND r.tenant_id = v_tenant_id AND r.legacy_id IS NOT NULL;

  SELECT count(*) - count(DISTINCT (route_dow, route_prdctn_cd, cus_id)) INTO v_dupes FROM bps.route_stop WHERE route_id <> 0;

  INSERT INTO bps.om_route_stops (tenant_id, route_id, day_of_week, production_code, ship_to_customer_id, stop_no)
  SELECT v_tenant_id, x.route_id, x.dow, x.code, x.customer_id,
         row_number() OVER (PARTITION BY x.route_id, x.dow, x.code ORDER BY x.legacy_stop_no, x.customer_id)
    FROM (
      SELECT DISTINCT ON (upper(btrim(rs.route_dow)), upper(btrim(rs.route_prdctn_cd)), c.customer_id)
             r.route_id, upper(btrim(rs.route_dow)) AS dow, upper(btrim(rs.route_prdctn_cd)) AS code, c.customer_id,
             rs.route_stop_no AS legacy_stop_no
        FROM bps.route_stop rs
        JOIN bps.om_routes r ON r.tenant_id = v_tenant_id AND r.legacy_id = rs.route_id::int
        JOIN bps.fnd_customers c ON c.tenant_id = v_tenant_id AND c.legacy_id = rs.cus_id::int
        JOIN bps.om_production_codes pc ON pc.tenant_id = v_tenant_id AND pc.production_code = upper(btrim(rs.route_prdctn_cd))
       WHERE rs.route_id <> 0 AND upper(btrim(rs.route_dow)) IN ('MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN')
         AND upper(btrim(c.customer_type)) IN ('ACCOUNT', 'DEPARTMENT')
       ORDER BY upper(btrim(rs.route_dow)), upper(btrim(rs.route_prdctn_cd)), c.customer_id, r.sort_order, rs.route_stop_no
    ) x;
  GET DIAGNOSTICS v_stops = ROW_COUNT;

  RAISE NOTICE 'seed_om_routes: % routes, % stops loaded (% legacy rows were a customer on a second route the same day and code)',
    v_routes, v_stops, v_dupes;
END $$;
