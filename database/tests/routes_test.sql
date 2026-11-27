-- ============================================================
-- SQL tests for Routes Maintenance: route CRUD, stop add / move / remove with renumbering, one route per ship-to per
-- day + code, copy a day, unassigned, date changes, route sheet, route stamping in Process run, Route Delivery Report
-- order, customer profile view and access. One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/routes_test.sql
-- Assumes the Alpine Bakery seed (tenant 200000000002, staff user 200000174045, item legacy 11608, production code MORNING,
-- delivery methods OWN_TRUCK / CARRIER). Run date: production 2033-05-10 MORNING, delivered 2033-05-11.
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t, _id TO PUBLIC;

-- ── Setup (trusted): accounts A, B, C (carrier), E (inactive), F, G; site D under A; department S under A ──
DO $$
DECLARE a bigint; b bigint; c bigint; d bigint; e bigint; f bigint; g bigint; s bigint; u bigint;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_number) VALUES (200000000002, 'ZR ACCOUNT A', 'ACCOUNT', 'ZR01') RETURNING customer_id INTO a;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_number) VALUES (200000000002, 'ZR ACCOUNT B', 'ACCOUNT', 'ZR02') RETURNING customer_id INTO b;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_number, delivery_method_code) VALUES (200000000002, 'ZR ACCOUNT C', 'ACCOUNT', 'ZR03', 'CARRIER') RETURNING customer_id INTO c;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_number, customer_parent_id) VALUES (200000000002, 'ZR SITE D', 'SITE', 'ZR04', a) RETURNING customer_id INTO d;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_number, is_active) VALUES (200000000002, 'ZR ACCOUNT E', 'ACCOUNT', 'ZR05', false) RETURNING customer_id INTO e;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_number) VALUES (200000000002, 'ZR ACCOUNT F', 'ACCOUNT', 'ZR06') RETURNING customer_id INTO f;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_number) VALUES (200000000002, 'ZR ACCOUNT G', 'ACCOUNT', 'ZR07') RETURNING customer_id INTO g;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_number, customer_parent_id) VALUES (200000000002, 'ZR DEPT S', 'DEPARTMENT', 'ZR08', a) RETURNING customer_id INTO s;
  INSERT INTO _id VALUES ('a', a), ('b', b), ('c', c), ('d', d), ('e', e), ('f', f), ('g', g), ('s', s);
  -- a customer-side user, for the access check
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zr customer user', 'CUSTOMER_USER') RETURNING user_id INTO u;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (200000000002, u);
  INSERT INTO fnd_user_customers (tenant_id, user_id, customer_id) VALUES (200000000002, u, a);
  INSERT INTO _id VALUES ('cust_user', u);
  INSERT INTO _t VALUES ('area delivery.routes exists and the company administrator has it',
    EXISTS (SELECT 1 FROM fnd_role_area_access x JOIN fnd_roles r ON r.role_id = x.role_id
             WHERE x.tenant_id = 200000000002 AND x.area_key = 'delivery.routes' AND r.role_name = 'Company Administrator' AND x.can_write));
  INSERT INTO _t VALUES ('om_route_dow is not locale dependent', om_route_dow(DATE '2033-05-11') = 'WED' AND om_route_dow(DATE '2033-05-15') = 'SUN');
END $$;

-- ── Staff ─────────────────────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

-- Route CRUD
DO $$
DECLARE r jsonb; r1 bigint; r2 bigint; ok boolean;
BEGIN
  r := om_route_save(200000000002, jsonb_build_object('route_code', 'ZT1', 'route_name', 'Test north', 'sort_order', 900,
                                                      'default_driver_user_id', 200000174045, 'start_time', '05:30', 'notes', 'Truck 2'));
  r1 := (r->>'route_id')::bigint;
  INSERT INTO _t VALUES ('route: created with driver and start time', r->>'start_time' = '05:30' AND (r->>'default_driver_user_id')::bigint = 200000174045);
  r := om_route_save(200000000002, jsonb_build_object('route_code', 'ZT2', 'route_name', 'Test south', 'sort_order', 901));
  r2 := (r->>'route_id')::bigint;
  INSERT INTO _id VALUES ('r1', r1), ('r2', r2);
  BEGIN PERFORM om_route_save(200000000002, jsonb_build_object('route_code', 'zt1', 'route_name', 'Dup')); ok := false;
  EXCEPTION WHEN raise_exception THEN ok := true; END;
  INSERT INTO _t VALUES ('route: code is unique in any case', ok);
  BEGIN PERFORM om_route_save(200000000002, jsonb_build_object('route_code', 'ZT9', 'route_name', 'X', 'default_driver_user_id', (SELECT v FROM _id WHERE k = 'cust_user'))); ok := false;
  EXCEPTION WHEN raise_exception THEN ok := true; END;
  INSERT INTO _t VALUES ('route: driver must be a staff user', ok);
  r := om_route_save(200000000002, jsonb_build_object('route_id', r2, 'route_code', 'ZT2', 'route_name', 'Test south renamed', 'sort_order', 901, 'start_time', ''));
  INSERT INTO _t VALUES ('route: update renames, blank start time is none', r->>'route_name' = 'Test south renamed' AND r->>'start_time' IS NULL);
  r := om_route_save(200000000002, jsonb_build_object('route_code', 'ZT3', 'route_name', 'Goes last'));
  INSERT INTO _t VALUES ('route: new route without sort order goes last', (r->>'sort_order')::int > 901);
  INSERT INTO _id VALUES ('r3', (r->>'route_id')::bigint);
  r := om_routes_get(200000000002, 'morning');
  INSERT INTO _t VALUES ('routes get: production codes, staff and routes in sort order',
    r->>'production_code' = 'MORNING' AND jsonb_array_length(r->'production_codes') >= 1 AND jsonb_array_length(r->'staff') >= 1
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'routes') x WHERE (x->>'route_id')::bigint = r1 AND x->'counts'->>'WED' = '0' AND x->>'driver_name' IS NOT NULL));
END $$;

-- Stops: add, one route per ship-to, move, renumber, window, remove
DO $$
DECLARE r jsonb; r1 bigint := (SELECT v FROM _id WHERE k = 'r1'); r2 bigint := (SELECT v FROM _id WHERE k = 'r2'); ok boolean; nums text;
BEGIN
  PERFORM om_route_stop_add(200000000002, r1, 'WED', 'MORNING', (SELECT v FROM _id WHERE k = 'a'));
  PERFORM om_route_stop_add(200000000002, r1, 'wed', 'morning', (SELECT v FROM _id WHERE k = 'g'));
  r := om_route_stop_add(200000000002, r2, 'WED', 'MORNING', (SELECT v FROM _id WHERE k = 'b'));
  INSERT INTO _t VALUES ('stops: added at the end', (r->>'stop_no')::int = 1);
  BEGIN PERFORM om_route_stop_add(200000000002, r1, 'WED', 'MORNING', (SELECT v FROM _id WHERE k = 'b')); ok := false;
  EXCEPTION WHEN raise_exception THEN ok := true; END;
  INSERT INTO _t VALUES ('stops: a ship-to on another route the same day is refused without move', ok);
  r := om_route_stop_add(200000000002, r1, 'WED', 'MORNING', (SELECT v FROM _id WHERE k = 'b'), 1, true);
  INSERT INTO _t VALUES ('stops: move takes it off the other route, inserted at stop 1',
    (r->>'stop_no')::int = 1 AND (r->'moved_from'->>'route_id')::bigint = r2 AND NOT EXISTS (SELECT 1 FROM om_route_stops WHERE route_id = r2));
  SELECT string_agg(c.customer_number || '=' || s.stop_no, ',' ORDER BY s.stop_no) INTO nums
    FROM om_route_stops s JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id WHERE s.route_id = r1 AND s.day_of_week = 'WED';
  INSERT INTO _t VALUES ('stops: later stops move down (B=1, A=2, G=3)', nums = 'ZR02=1,ZR01=2,ZR07=3');
  r := om_route_stop_move(200000000002, (SELECT route_stop_id FROM om_route_stops WHERE route_id = r1 AND ship_to_customer_id = (SELECT v FROM _id WHERE k = 'g')), 1);
  SELECT string_agg(c.customer_number || '=' || s.stop_no, ',' ORDER BY s.stop_no) INTO nums
    FROM om_route_stops s JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id WHERE s.route_id = r1 AND s.day_of_week = 'WED';
  INSERT INTO _t VALUES ('move: G to stop 1 renumbers (G=1, B=2, A=3)', nums = 'ZR07=1,ZR02=2,ZR01=3');
  PERFORM om_route_stop_move(200000000002, (SELECT route_stop_id FROM om_route_stops WHERE route_id = r1 AND ship_to_customer_id = (SELECT v FROM _id WHERE k = 'g')), 99);
  SELECT string_agg(c.customer_number || '=' || s.stop_no, ',' ORDER BY s.stop_no) INTO nums
    FROM om_route_stops s JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id WHERE s.route_id = r1 AND s.day_of_week = 'WED';
  INSERT INTO _t VALUES ('move: past the end goes last (B=1, A=2, G=3)', nums = 'ZR02=1,ZR01=2,ZR07=3');
  r := om_route_stop_save(200000000002, (SELECT route_stop_id FROM om_route_stops WHERE route_id = r1 AND ship_to_customer_id = (SELECT v FROM _id WHERE k = 'a')),
                          jsonb_build_object('window_from', '06:00', 'window_to', '07:30', 'driver_notes', ' Dock B '));
  INSERT INTO _t VALUES ('stop save: window and notes', r->>'window_from' = '06:00' AND r->>'window_to' = '07:30' AND r->>'driver_notes' = 'Dock B');
  BEGIN PERFORM om_route_stop_save(200000000002, (r->>'route_stop_id')::bigint, jsonb_build_object('window_to', '05:00')); ok := false;
  EXCEPTION WHEN raise_exception THEN ok := true; END;
  INSERT INTO _t VALUES ('stop save: a window ending before it starts is refused', ok);
  BEGIN PERFORM om_route_stop_add(200000000002, r1, 'WED', 'MORNING', (SELECT v FROM _id WHERE k = 's')); ok := false;
  EXCEPTION WHEN raise_exception THEN ok := true; END;
  INSERT INTO _t VALUES ('stops: a department cannot be a stop', ok);
  BEGIN PERFORM om_route_stop_add(200000000002, r1, 'WED', 'MORNING', (SELECT v FROM _id WHERE k = 'e')); ok := false;
  EXCEPTION WHEN raise_exception THEN ok := true; END;
  INSERT INTO _t VALUES ('stops: an inactive customer cannot be added', ok);
  BEGIN PERFORM om_route_stop_add(200000000002, r1, 'XYZ', 'MORNING', (SELECT v FROM _id WHERE k = 'f')); ok := false;
  EXCEPTION WHEN raise_exception THEN ok := true; END;
  INSERT INTO _t VALUES ('stops: a bad day of week is refused', ok);
  -- remove F after adding it: renumbered
  PERFORM om_route_stop_add(200000000002, r1, 'WED', 'MORNING', (SELECT v FROM _id WHERE k = 'f'), 2);
  r := om_route_stop_delete(200000000002, (SELECT route_stop_id FROM om_route_stops WHERE route_id = r1 AND ship_to_customer_id = (SELECT v FROM _id WHERE k = 'f')));
  SELECT string_agg(c.customer_number || '=' || s.stop_no, ',' ORDER BY s.stop_no) INTO nums
    FROM om_route_stops s JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id WHERE s.route_id = r1 AND s.day_of_week = 'WED';
  INSERT INTO _t VALUES ('remove: the route is renumbered', (r->>'stops')::int = 3 AND nums = 'ZR02=1,ZR01=2,ZR07=3');
  r := om_route_stops_get(200000000002, r1, 'WED', 'MORNING');
  INSERT INTO _t VALUES ('stops get: stop order, numbers and day assignments',
    jsonb_array_length(r->'stops') = 3 AND r->'stops'->0->>'customer_number' = 'ZR02' AND r->'stops'->1->>'driver_notes' = 'Dock B'
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'day_assignments') x WHERE (x->>'customer_id')::bigint = (SELECT v FROM _id WHERE k = 'g') AND x->>'route_code' = 'ZT1'));
  r := om_routes_get(200000000002, 'MORNING');
  INSERT INTO _t VALUES ('routes get: stop count for the day', EXISTS (SELECT 1 FROM jsonb_array_elements(r->'routes') x WHERE (x->>'route_id')::bigint = r1 AND x->'counts'->>'WED' = '3'));
END $$;

-- Copy a day
DO $$
DECLARE r jsonb; r1 bigint := (SELECT v FROM _id WHERE k = 'r1'); r2 bigint := (SELECT v FROM _id WHERE k = 'r2'); nums text;
BEGIN
  -- THU already has F on route 1, and G is on route 2 on THU
  PERFORM om_route_stop_add(200000000002, r1, 'THU', 'MORNING', (SELECT v FROM _id WHERE k = 'f'));
  PERFORM om_route_stop_add(200000000002, r2, 'THU', 'MORNING', (SELECT v FROM _id WHERE k = 'g'));
  r := om_route_stops_copy(200000000002, r1, 'WED', 'MORNING', jsonb_build_array(jsonb_build_object('day_of_week', 'THU', 'production_code', 'MORNING'),
                                                                                 jsonb_build_object('day_of_week', 'WED', 'production_code', 'MORNING')), 'MERGE');
  SELECT string_agg(c.customer_number || '=' || s.stop_no, ',' ORDER BY s.stop_no) INTO nums
    FROM om_route_stops s JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id WHERE s.route_id = r1 AND s.day_of_week = 'THU';
  INSERT INTO _t VALUES ('copy merge: keeps the target stop, adds missing ones at the end, source itself ignored',
    (r->>'targets')::int = 1 AND (r->>'copied')::int = 2 AND nums = 'ZR06=1,ZR02=2,ZR01=3');
  INSERT INTO _t VALUES ('copy: a ship-to on another route that day is skipped and reported',
    jsonb_array_length(r->'skipped') = 1 AND r->'skipped'->0->>'customer_name' = 'ZR ACCOUNT G' AND r->'skipped'->0->>'route_code' = 'ZT2');
  INSERT INTO _t VALUES ('copy: windows and notes come along',
    (SELECT driver_notes = 'Dock B' AND window_from = '06:00' FROM om_route_stops WHERE route_id = r1 AND day_of_week = 'THU' AND ship_to_customer_id = (SELECT v FROM _id WHERE k = 'a')));
  r := om_route_stops_copy(200000000002, r1, 'WED', 'MORNING', jsonb_build_array(jsonb_build_object('day_of_week', 'THU', 'production_code', 'MORNING'),
                                                                                 jsonb_build_object('day_of_week', 'FRI', 'production_code', 'MORNING')), 'replace');
  SELECT string_agg(c.customer_number || '=' || s.stop_no, ',' ORDER BY s.stop_no) INTO nums
    FROM om_route_stops s JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id WHERE s.route_id = r1 AND s.day_of_week = 'THU';
  INSERT INTO _t VALUES ('copy replace: target gets exactly the source (less skipped)', (r->>'targets')::int = 2 AND nums = 'ZR02=1,ZR01=2');
  INSERT INTO _t VALUES ('copy replace: an empty target day gets all stops',
    (SELECT count(*) FROM om_route_stops WHERE route_id = r1 AND day_of_week = 'FRI') = 3);
END $$;

-- Unassigned
DO $$
DECLARE r jsonb; ids bigint[];
BEGIN
  r := om_route_unassigned_get(200000000002, 'WED', 'MORNING', false);
  SELECT array_agg((x->>'customer_id')::bigint) INTO ids FROM jsonb_array_elements(r->'customers') x;
  INSERT INTO _t VALUES ('unassigned: account with no stop is listed', (SELECT v FROM _id WHERE k = 'f') = ANY (ids));
  INSERT INTO _t VALUES ('unassigned: stops, the site riding with its account, carrier, inactive and department are not',
    NOT ((SELECT v FROM _id WHERE k = 'a') = ANY (ids)) AND NOT ((SELECT v FROM _id WHERE k = 'd') = ANY (ids))
    AND NOT ((SELECT v FROM _id WHERE k = 'c') = ANY (ids)) AND NOT ((SELECT v FROM _id WHERE k = 'e') = ANY (ids))
    AND NOT ((SELECT v FROM _id WHERE k = 's') = ANY (ids)));
  r := om_route_unassigned_get(200000000002, 'WED', 'MORNING', true);
  INSERT INTO _t VALUES ('unassigned: ordering only leaves out F (no orders)',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'customers') x WHERE (x->>'customer_id')::bigint = (SELECT v FROM _id WHERE k = 'f')));
END $$;
-- an order for F delivered on a Wednesday (production Tue 2033-05-03 + 1 day) puts it on the ordering-only list
DO $$
DECLARE r jsonb;
BEGIN
  PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', (SELECT v FROM _id WHERE k = 'f'), 'production_date', to_char(current_date - 7 * 1 - (extract(isodow FROM current_date)::int - 2), 'YYYY-MM-DD'),
          'production_code', 'MORNING', 'lines', jsonb_build_array(jsonb_build_object('item_id', (SELECT item_id FROM fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), 'item_description', 'Bun', 'quantity', 1, 'unit_price', 1))));
  r := om_route_unassigned_get(200000000002, 'WED', 'MORNING', true);
  INSERT INTO _t VALUES ('unassigned: ordering only lists F once it orders for Wednesday delivery',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r->'customers') x WHERE (x->>'customer_id')::bigint = (SELECT v FROM _id WHERE k = 'f') AND x->>'last_order_date' IS NOT NULL));
  r := om_route_unassigned_get(200000000002, 'THU', 'MORNING', true);
  INSERT INTO _t VALUES ('unassigned: ... but not for Thursday',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'customers') x WHERE (x->>'customer_id')::bigint = (SELECT v FROM _id WHERE k = 'f')));
END $$;

-- Date changes and the route sheet (delivery Wed 2033-05-11): A moves to route 2 stop 1, B is skipped
DO $$
DECLARE r jsonb; r1 bigint := (SELECT v FROM _id WHERE k = 'r1'); r2 bigint := (SELECT v FROM _id WHERE k = 'r2'); ok boolean;
BEGIN
  PERFORM om_route_exception_save(200000000002, jsonb_build_object('exception_date', '2033-05-11', 'production_code', 'MORNING',
          'customer_id', (SELECT v FROM _id WHERE k = 'a'), 'kind', 'ROUTE', 'route_id', r2, 'stop_no', 1));
  PERFORM om_route_exception_save(200000000002, jsonb_build_object('exception_date', '2033-05-11', 'production_code', 'MORNING',
          'customer_id', (SELECT v FROM _id WHERE k = 'b'), 'kind', 'ROUTE', 'route_id', r2, 'stop_no', 2));
  r := om_route_exception_save(200000000002, jsonb_build_object('exception_date', '2033-05-11', 'production_code', 'MORNING',
          'customer_id', (SELECT v FROM _id WHERE k = 'b'), 'kind', 'SKIP', 'notes', 'Closed'));
  INSERT INTO _t VALUES ('date change: saving again for the same ship-to and date replaces it',
    (SELECT count(*) FROM om_route_stop_exceptions WHERE ship_to_customer_id = (SELECT v FROM _id WHERE k = 'b')) = 1
    AND (SELECT route_id IS NULL FROM om_route_stop_exceptions WHERE exception_id = (r->>'exception_id')::bigint));
  BEGIN PERFORM om_route_exception_save(200000000002, jsonb_build_object('exception_date', '2033-05-11', 'production_code', 'MORNING',
          'customer_id', (SELECT v FROM _id WHERE k = 'g'), 'kind', 'ROUTE')); ok := false;
  EXCEPTION WHEN raise_exception THEN ok := true; END;
  INSERT INTO _t VALUES ('date change: a route change needs a route', ok);
  r := om_route_exceptions_get(200000000002, '2033-05-01', '2033-05-31', NULL);
  INSERT INTO _t VALUES ('date changes list: kinds and the usual stop',
    jsonb_array_length(r->'changes') = 2
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'changes') x WHERE x->>'customer_number' = 'ZR01' AND x->>'kind' = 'ROUTE' AND x->>'route_code' = 'ZT2' AND x->>'usual_route_code' = 'ZT1' AND x->>'day_of_week' = 'WED')
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'changes') x WHERE x->>'customer_number' = 'ZR02' AND x->>'kind' = 'SKIP'));
  r := om_route_sheet_get(200000000002, NULL, 'MORNING', r2, '2033-05-11');
  INSERT INTO _t VALUES ('sheet for a date: route 2 has A at stop 1 with its usual window',
    r->>'day_of_week' = 'WED' AND jsonb_array_length(r->'routes'->0->'stops') = 1 AND r->'routes'->0->'stops'->0->>'customer_number' = 'ZR01'
    AND (r->'routes'->0->'stops'->0->>'is_change')::boolean AND r->'routes'->0->'stops'->0->>'window_from' = '06:00');
  r := om_route_sheet_get(200000000002, NULL, 'MORNING', r1, '2033-05-11');
  INSERT INTO _t VALUES ('sheet for a date: route 1 without the moved and skipped stops (G=1)',
    jsonb_array_length(r->'routes'->0->'stops') = 1 AND r->'routes'->0->'stops'->0->>'customer_number' = 'ZR07' AND (r->'routes'->0->'stops'->0->>'stop_no')::int = 1);
  r := om_route_sheet_get(200000000002, 'WED', 'MORNING', NULL, NULL);
  INSERT INTO _t VALUES ('sheet for a weekday: every active route with stops, in sort order, driver and start time',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r->'routes') x WHERE x->>'route_code' = 'ZT1' AND jsonb_array_length(x->'stops') = 3 AND x->>'start_time' = '05:30')
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'routes') x WHERE x->>'route_code' = 'ZT3'));
  r := om_customer_routes_get(200000000002, (SELECT v FROM _id WHERE k = 'd'));
  INSERT INTO _t VALUES ('customer profile: a site shows the stops it follows from its account',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r->'stops') x WHERE x->>'day_of_week' = 'WED' AND x->>'route_code' = 'ZT1' AND x->>'stop_no' = '2' AND x->>'inherited_from' = 'ZR ACCOUNT A'));
  r := om_customer_routes_get(200000000002, (SELECT v FROM _id WHERE k = 'b'));
  INSERT INTO _t VALUES ('customer profile: own stops and upcoming date changes',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r->'stops') x WHERE x->>'route_code' = 'ZT1' AND x->>'inherited_from' IS NULL)
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'changes') x WHERE x->>'kind' = 'SKIP' AND x->>'exception_date' = '2033-05-11'));
END $$;

-- Process run stamps routes; the Route Delivery Report orders by route sort order then stop number
DO $$
DECLARE r jsonb; o record; v_run bigint; lst text; n int;
BEGIN
  FOR o IN SELECT k FROM unnest(ARRAY['a', 'd', 'b', 'c', 'g']) k LOOP
    PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', (SELECT v FROM _id WHERE k = o.k), 'production_date', '2033-05-10', 'production_code', 'MORNING',
            'lines', jsonb_build_array(jsonb_build_object('item_id', (SELECT item_id FROM fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), 'item_description', 'Bun', 'quantity', 1, 'unit_price', 1))));
  END LOOP;
  r := om_production_runs_process(200000000002, DATE '2033-05-10', DATE '2033-05-10', 'MORNING');
  v_run := (r->0->>'production_run_id')::bigint;
  INSERT INTO _t VALUES ('process: run delivers on Wednesday 2033-05-11', (SELECT delivery_date = DATE '2033-05-11' FROM om_production_runs WHERE production_run_id = v_run));
  SELECT string_agg(c.customer_number || ':' || COALESCE(rt.route_code, '-') || '/' || COALESCE(s.route_stop_no::text, '-') || '/' || COALESCE(s.route, '-'), ',' ORDER BY c.customer_number)
    INTO lst
    FROM om_shipments s JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id LEFT JOIN om_routes rt ON rt.route_id = s.route_id
   WHERE s.production_run_id = v_run AND c.customer_number LIKE 'ZR%';
  INSERT INTO _t VALUES ('stamp: A moved to ZT2/1 for the date, B skipped, C carrier none, D rides with A, G on ZT1/1 (renumbered for the date)',
    lst = 'ZR01:ZT2/1/Test south renamed,ZR02:-/-/-,ZR03:-/-/-,ZR04:ZT2/1/Test south renamed,ZR07:ZT1/1/Test north');
  IF lst IS DISTINCT FROM 'ZR01:ZT2/1/Test south renamed,ZR02:-/-/-,ZR03:-/-/-,ZR04:ZT2/1/Test south renamed,ZR07:ZT1/1/Test north' THEN RAISE NOTICE 'stamp got %', lst; END IF;

  r := om_report_delivery_get(200000000002, DATE '2033-05-10', DATE '2033-05-10', 'MORNING');
  SELECT string_agg(x->>'customer_number', ',' ORDER BY ord) INTO lst
    FROM jsonb_array_elements(r->'stops') WITH ORDINALITY AS t(x, ord) WHERE x->>'customer_number' LIKE 'ZR%';
  INSERT INTO _t VALUES ('report: route sort order, stop number, unrouted last; carrier left off', lst = 'ZR07,ZR01,ZR04,ZR02');
  INSERT INTO _t VALUES ('report: stops carry route code, name and stop number',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r->'stops') x WHERE x->>'customer_number' = 'ZR07' AND x->>'route_code' = 'ZT1' AND x->>'route_name' = 'Test north' AND x->>'stop_no' = '1'));

  -- drop the date changes and reprocess: weekly stops (B=1, A=2, G=3 on ZT1)
  DELETE FROM om_route_stop_exceptions WHERE tenant_id = 200000000002 AND exception_date = DATE '2033-05-11';
  PERFORM om_production_runs_process(200000000002, DATE '2033-05-10', DATE '2033-05-10', 'MORNING');
  SELECT string_agg(c.customer_number || ':' || COALESCE(rt.route_code, '-') || '/' || COALESCE(s.route_stop_no::text, '-'), ',' ORDER BY c.customer_number)
    INTO lst
    FROM om_shipments s JOIN fnd_customers c ON c.customer_id = s.ship_to_customer_id LEFT JOIN om_routes rt ON rt.route_id = s.route_id
   WHERE s.production_run_id = v_run AND c.customer_number LIKE 'ZR%';
  INSERT INTO _t VALUES ('reprocess: weekly stops are stamped again (date change removed)', lst = 'ZR01:ZT1/2,ZR02:ZT1/1,ZR03:-/-,ZR04:ZT1/2,ZR07:ZT1/3');

  -- a site with its own stop wins over its account's
  PERFORM om_route_stop_add(200000000002, (SELECT v FROM _id WHERE k = 'r2'), 'WED', 'MORNING', (SELECT v FROM _id WHERE k = 'd'));
  PERFORM om_production_runs_process(200000000002, DATE '2033-05-10', DATE '2033-05-10', 'MORNING');
  INSERT INTO _t VALUES ('stamp: a site''s own stop wins over its account''s',
    (SELECT rt.route_code = 'ZT2' AND s.route_stop_no = 1 FROM om_shipments s JOIN om_routes rt ON rt.route_id = s.route_id
      WHERE s.production_run_id = v_run AND s.ship_to_customer_id = (SELECT v FROM _id WHERE k = 'd')));

  -- an inactive route stamps nothing
  UPDATE om_routes SET is_active = false WHERE route_id = (SELECT v FROM _id WHERE k = 'r2');
  PERFORM om_production_runs_process(200000000002, DATE '2033-05-10', DATE '2033-05-10', 'MORNING');
  INSERT INTO _t VALUES ('stamp: a stop on an inactive route does not count (D rides with A again)',
    (SELECT rt.route_code = 'ZT1' FROM om_shipments s JOIN om_routes rt ON rt.route_id = s.route_id
      WHERE s.production_run_id = v_run AND s.ship_to_customer_id = (SELECT v FROM _id WHERE k = 'd')));

  -- a hand-typed route on an unrouted shipment survives reprocessing
  UPDATE om_shipments SET route = 'Van 9' WHERE production_run_id = v_run AND ship_to_customer_id = (SELECT v FROM _id WHERE k = 'c');
  PERFORM om_production_runs_process(200000000002, DATE '2033-05-10', DATE '2033-05-10', 'MORNING');
  INSERT INTO _t VALUES ('stamp: a typed route on a shipment without a stamped route is kept',
    (SELECT route = 'Van 9' FROM om_shipments WHERE production_run_id = v_run AND ship_to_customer_id = (SELECT v FROM _id WHERE k = 'c')));
  PERFORM set_config('t.run', v_run::text, false);
END $$;

-- Route delete keeps the stamped name on shipments
DO $$
DECLARE r jsonb;
BEGIN
  r := om_route_delete(200000000002, (SELECT v FROM _id WHERE k = 'r1'));
  INSERT INTO _t VALUES ('delete: removes the route and its stops', (r->>'stops_removed')::int > 0
    AND NOT EXISTS (SELECT 1 FROM om_route_stops WHERE route_id = (SELECT v FROM _id WHERE k = 'r1')));
  INSERT INTO _t VALUES ('delete: stamped shipments keep the route name, lose the link',
    (SELECT route = 'Test north' AND route_id IS NULL FROM om_shipments
      WHERE production_run_id = current_setting('t.run')::bigint AND ship_to_customer_id = (SELECT v FROM _id WHERE k = 'g')));
END $$;

-- Access: a customer user cannot use Routes Maintenance or the customer view
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', (SELECT v FROM _id WHERE k = 'cust_user')))::text, true);
DO $$
DECLARE ok boolean; ok2 boolean; ok3 boolean;
BEGIN
  BEGIN PERFORM om_routes_get(200000000002, NULL); ok := false; EXCEPTION WHEN OTHERS THEN ok := true; END;
  BEGIN PERFORM om_route_save(200000000002, jsonb_build_object('route_code', 'ZZ', 'route_name', 'ZZ')); ok2 := false; EXCEPTION WHEN OTHERS THEN ok2 := true; END;
  BEGIN PERFORM om_customer_routes_get(200000000002, (SELECT v FROM _id WHERE k = 'a')); ok3 := false; EXCEPTION WHEN OTHERS THEN ok3 := true; END;
  INSERT INTO _t VALUES ('access: a customer user is refused', ok AND ok2 AND ok3);
  INSERT INTO _t VALUES ('access: a customer user reads no route rows', NOT EXISTS (SELECT 1 FROM om_routes) AND NOT EXISTS (SELECT 1 FROM om_route_stops));
END $$;
-- other tenant id
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);
DO $$
DECLARE ok boolean;
BEGIN
  BEGIN PERFORM om_routes_get(200000000003, NULL); ok := false; EXCEPTION WHEN OTHERS THEN ok := true; END;
  INSERT INTO _t VALUES ('access: another company id is refused', ok);
END $$;
RESET ROLE;

SELECT name, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END FROM _t ORDER BY name;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM _t WHERE ok IS NOT TRUE) THEN RAISE EXCEPTION 'routes_test failed'; END IF; END $$;
ROLLBACK;
