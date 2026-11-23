-- ============================================================
-- SQL tests for production runs, cutoffs, customer extra minutes, delivery charge, RLS. One transaction, ROLLED BACK;
-- local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/order_runs_test.sql
-- Assumes the Alpine Bakery seed: tenant 200000000002, parent customer (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102) with department child (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 104),
-- item (SELECT item_id FROM bps.fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), and the seeded production-code settings (16:00, 1 day before, delivery +1 day).
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
GRANT ALL ON _t TO PUBLIC;

-- A customer-side user attached to account (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102) (Customer Administrator role), used for the customer-restricted claims below.
DO $$
DECLARE u bigint;
BEGIN
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz test customer user', 'CUSTOMER_USER') RETURNING user_id INTO u;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (200000000002, u);
  INSERT INTO fnd_user_customers (tenant_id, user_id, customer_id) VALUES (200000000002, u, (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102));
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id)
    SELECT 200000000002, u, role_id FROM fnd_roles WHERE tenant_id = 200000000002 AND role_name = 'Customer Administrator' AND owner_customer_id IS NULL;
  PERFORM set_config('t.cust_user', u::text, false);
END $$;


-- ── Part A: pure functions as a trusted connection (no JWT claims) ───────────
DO $$
DECLARE v_c timestamptz; v_id1 bigint; v_id2 bigint; v_run om_production_runs%ROWTYPE; v_raised boolean;
BEGIN
  v_c := om_production_cutoff_calc(200000000002, DATE '2030-03-15', 'morning');
  INSERT INTO _t VALUES ('cutoff = day before at 16:00 tenant time (EDT -> 20:00 UTC)', v_c = TIMESTAMPTZ '2030-03-14 16:00:00-04');
  v_c := om_production_cutoff_calc(200000000002, DATE '2030-12-15', 'MORNING');
  INSERT INTO _t VALUES ('cutoff honours winter time (EST -> 21:00 UTC)', v_c = TIMESTAMPTZ '2030-12-14 16:00:00-05');
  INSERT INTO _t VALUES ('cutoff NULL for unknown code', om_production_cutoff_calc(200000000002, DATE '2030-03-15', 'NOPE') IS NULL);

  v_id1 := om_production_run_get_or_create(200000000002, DATE '2030-03-15', 'MORNING');
  v_id2 := om_production_run_get_or_create(200000000002, DATE '2030-03-15', ' morning ');
  INSERT INTO _t VALUES ('get_or_create is idempotent and normalises the code', v_id1 IS NOT NULL AND v_id1 = v_id2);
  SELECT * INTO v_run FROM om_production_runs WHERE production_run_id = v_id1;
  INSERT INTO _t VALUES ('new run: delivery = production + 1, status OPEN, cutoff stored',
      v_run.delivery_date = DATE '2030-03-16' AND v_run.run_status = 'OPEN' AND v_run.cutoff_at = TIMESTAMPTZ '2030-03-14 16:00:00-04');
  INSERT INTO _t VALUES ('get_or_create returns NULL without a code', om_production_run_get_or_create(200000000002, DATE '2030-03-15', NULL) IS NULL);
  BEGIN PERFORM om_production_run_get_or_create(200000000002, DATE '2030-03-15', 'NOPE'); v_raised := false;
  EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  INSERT INTO _t VALUES ('get_or_create raises for a code without settings', v_raised);

  UPDATE fnd_customers SET cutoff_extra_minutes = NULL WHERE customer_id IN ((SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102), (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 104));
  INSERT INTO _t VALUES ('extra minutes default 0', om_customer_cutoff_extra_minutes(200000000002, (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 104)) = 0);
  UPDATE fnd_customers SET cutoff_extra_minutes = 60 WHERE customer_id = (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102);
  INSERT INTO _t VALUES ('extra minutes inherited from parent', om_customer_cutoff_extra_minutes(200000000002, (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 104)) = 60);
  UPDATE fnd_customers SET cutoff_extra_minutes = 15 WHERE customer_id = (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 104);
  INSERT INTO _t VALUES ('own extra minutes override the parent', om_customer_cutoff_extra_minutes(200000000002, (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 104)) = 15);
  UPDATE fnd_customers SET cutoff_extra_minutes = NULL WHERE customer_id = (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 104);
  BEGIN UPDATE fnd_customers SET cutoff_extra_minutes = -5 WHERE customer_id = (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 104); v_raised := false;
  EXCEPTION WHEN check_violation THEN v_raised := true; END;
  INSERT INTO _t VALUES ('negative extra minutes rejected', v_raised);
END $$;

-- ── Part B: staff caller (not restricted) ────────────────────────────────────
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

DO $$
DECLARE r jsonb; v_id bigint; v_raised boolean; g jsonb;
BEGIN
  r := om_orders_save(200000000002, NULL, NULL, jsonb_build_object(
        'customer_id', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102), 'order_date', '2030-03-10', 'production_date', '2030-03-15',
        'production_code', 'MORNING', 'delivery_amount', 12.5,
        'lines', jsonb_build_array(jsonb_build_object('item_id', (SELECT item_id FROM bps.fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), 'item_description','t','quantity',2,'unit_price',5))));
  v_id := (r->>'order_id')::bigint;
  INSERT INTO _t VALUES ('staff save sets production_run_id',
      (SELECT production_run_id FROM om_orders WHERE order_id = v_id) = (SELECT production_run_id FROM om_production_runs WHERE tenant_id=200000000002 AND production_date=DATE '2030-03-15' AND production_code='MORNING'));
  INSERT INTO _t VALUES ('staff save stores delivery_charge', (SELECT delivery_charge FROM om_orders WHERE order_id = v_id) = 12.5);
  g := om_orders_get_v2(200000000002, v_id, NULL, NULL, NULL, NULL, true, true, false);
  INSERT INTO _t VALUES ('get_v2 returns delivery_amount and run id', (g->>'delivery_amount')::numeric = 12.5 AND g->>'production_run_id' IS NOT NULL);
  BEGIN PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 118), 'production_date','2030-03-15','production_code','MORNING','delivery_amount', -1,'lines','[]'::jsonb)); v_raised := false;
  EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  INSERT INTO _t VALUES ('negative delivery_charge rejected', v_raised);
  r := om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 118), 'production_date','2030-03-16','lines','[]'::jsonb));
  INSERT INTO _t VALUES ('order without a production code gets no run, charge 0',
      (SELECT production_run_id IS NULL AND delivery_charge = 0 FROM om_orders WHERE order_id = (r->>'order_id')::bigint));
  PERFORM set_config('t.order_id', v_id::text, true);
  -- staff change a run's cutoff; settings writable
  UPDATE om_production_runs SET cutoff_at = cutoff_at + interval '1 hour' WHERE tenant_id=200000000002 AND production_date=DATE '2030-03-15';
  INSERT INTO _t VALUES ('staff can edit a run cutoff', FOUND);
  PERFORM om_production_codes_save(200000000002, '{"production_code":"MORNING","cutoff_time":"15:30","cutoff_days_before":1,"delivery_days_after":1,"is_active":true}'::jsonb);
  INSERT INTO _t VALUES ('staff can save production code settings', (SELECT cutoff_time FROM om_production_codes WHERE tenant_id=200000000002 AND production_code='MORNING') = TIME '15:30');
  PERFORM om_production_codes_save(200000000002, '{"production_code":"MORNING","cutoff_time":"16:00","cutoff_days_before":1,"delivery_days_after":1,"is_active":true}'::jsonb);
END $$;

-- ── Part C: restricted (customer) caller ─────────────────────────────────────
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', current_setting('t.cust_user')::bigint))::text, true);

DO $$
DECLARE r jsonb; v_raised boolean; n int; v_order bigint := current_setting('t.order_id')::bigint; v_info jsonb;
BEGIN
  r := om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102), 'production_date', '2030-04-20',
        'production_code', 'LUNCH', 'lines', '[]'::jsonb));
  INSERT INTO _t VALUES ('customer can order before cutoff (far-future run)', (r->>'success')::boolean);
  v_info := om_production_cutoff_get(200000000002, DATE '2030-04-20', 'LUNCH', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102));
  INSERT INTO _t VALUES ('cutoff_get reports open before cutoff', (v_info->>'is_open')::boolean AND v_info->>'production_run_id' IS NOT NULL);

  -- customers cannot write runs or settings
  UPDATE om_production_runs SET cutoff_at = cutoff_at + interval '1 day' WHERE tenant_id = 200000000002;
  GET DIAGNOSTICS n = ROW_COUNT;
  INSERT INTO _t VALUES ('customer cannot edit run cutoffs (RLS)', n = 0);
  BEGIN PERFORM om_production_codes_save(200000000002, '{"production_code":"LUNCH","cutoff_time":"23:00"}'::jsonb); v_raised := false;
  EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  INSERT INTO _t VALUES ('customer cannot change production code settings', v_raised);
  BEGIN INSERT INTO om_delivery_methods (tenant_id, delivery_method_code, delivery_method_name) VALUES (200000000002,'X','x'); v_raised := false;
  EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  INSERT INTO _t VALUES ('customer cannot add delivery methods', v_raised);
  INSERT INTO _t VALUES ('customer can read delivery methods', (SELECT count(*) FROM om_delivery_methods) >= 4);
END $$;

-- pass the cutoff: put the 2030-03-15 run 2 hours in the past (as a trusted connection)
RESET ROLE;
UPDATE om_production_runs SET cutoff_at = now() - interval '2 hours'
 WHERE tenant_id = 200000000002 AND production_date = DATE '2030-03-15' AND production_code = 'MORNING';
SET LOCAL ROLE authenticated;

DO $$
DECLARE v_raised boolean; v_order bigint := current_setting('t.order_id')::bigint; v_info jsonb; r jsonb; v_msg text;
BEGIN
  v_info := om_production_cutoff_get(200000000002, DATE '2030-03-15', 'MORNING', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102));
  INSERT INTO _t VALUES ('cutoff_get reports closed after cutoff (parent has 60 extra: 2h ago + 1h = closed)', NOT (v_info->>'is_open')::boolean);
  BEGIN PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 118), 'production_date','2030-03-15','production_code','MORNING','lines','[]'::jsonb)); v_raised := false;
  EXCEPTION WHEN OTHERS THEN v_raised := true; v_msg := SQLERRM; END;
  INSERT INTO _t VALUES ('customer cannot add an order after cutoff (no extra minutes)', v_raised AND v_msg LIKE '%closed%');
  BEGIN PERFORM om_orders_save(200000000002, NULL, v_order, jsonb_build_object('customer_id', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102), 'production_date','2030-03-15','production_code','MORNING','lines','[]'::jsonb)); v_raised := false;
  EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  INSERT INTO _t VALUES ('customer cannot change an order after cutoff', v_raised);
  BEGIN PERFORM om_orders_save(200000000002, 'delete', v_order, NULL); v_raised := false;
  EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  INSERT INTO _t VALUES ('customer cannot delete an order after cutoff', v_raised);
  BEGIN PERFORM om_orders_save(200000000002, NULL, v_order, jsonb_build_object('customer_id', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102), 'production_date','2030-04-21','production_code','LUNCH','lines','[]'::jsonb)); v_raised := false;
  EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  INSERT INTO _t VALUES ('customer cannot move a closed order to an open run', v_raised);
END $$;

RESET ROLE;
UPDATE fnd_customers SET cutoff_extra_minutes = 180 WHERE customer_id = (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102);   -- ordering allowed 3h past cutoff
SET LOCAL ROLE authenticated;
DO $$
DECLARE v_info jsonb; v_raised boolean; r jsonb;
BEGIN
  v_info := om_production_cutoff_get(200000000002, DATE '2030-03-15', 'MORNING', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 104));
  INSERT INTO _t VALUES ('extra minutes (inherited 180) reopen ordering for a department', (v_info->>'is_open')::boolean AND (v_info->>'extra_minutes')::int = 180);
  BEGIN r := om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 104), 'production_date','2030-03-15','production_code','MORNING','lines','[]'::jsonb)); v_raised := false;
  EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  INSERT INTO _t VALUES ('customer with extra minutes can still save', NOT v_raised);
END $$;

-- staff are never blocked
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);
DO $$
DECLARE v_raised boolean; v_order bigint := current_setting('t.order_id')::bigint;
BEGIN
  BEGIN PERFORM om_orders_save(200000000002, NULL, v_order, jsonb_build_object('customer_id', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102), 'production_date','2030-03-15','production_code','MORNING','delivery_amount', 9,'lines','[]'::jsonb)); v_raised := false;
  EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  INSERT INTO _t VALUES ('staff can still change an order after cutoff', NOT v_raised);
  INSERT INTO _t VALUES ('staff update keeps delivery_charge when payload has delivery_amount', (SELECT delivery_charge FROM om_orders WHERE order_id = v_order) = 9);
END $$;

-- ── Regression: claims carry allowed_tenant_ids only (no tenant_id); tenant time zone must still resolve ──
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', current_setting('t.cust_user')::bigint))::text, true);
DO $$
DECLARE v_info jsonb; v_raised boolean;
BEGIN
  v_info := om_production_cutoff_get(200000000002, DATE '2020-01-15', 'MORNING', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102));
  INSERT INTO _t VALUES ('cutoff_get resolves a run that does not exist yet (tenant time zone readable)', v_info->>'cutoff_at' IS NOT NULL AND v_info->>'time_zone' = 'America/New_York');
  INSERT INTO _t VALUES ('a past date with no run yet is closed to customers', NOT (v_info->>'is_open')::boolean);
  BEGIN PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', (SELECT customer_id FROM bps.fnd_customers WHERE tenant_id = 200000000002 AND legacy_id = 102), 'production_date','2020-01-15','production_code','MORNING','lines','[]'::jsonb)); v_raised := false;
  EXCEPTION WHEN OTHERS THEN v_raised := true; END;
  INSERT INTO _t VALUES ('customer cannot place the first order of a run that is already past its cutoff', v_raised);
  INSERT INTO _t VALUES ('time zone helper hides other tenants', bps.fnd_tenant_time_zone(999) IS NULL);
  INSERT INTO _t VALUES ('report defaults load for staff and customers', om_report_defaults_get(200000000002) -> 'from_date' IS NOT NULL
      AND jsonb_array_length(om_report_defaults_get(200000000002) -> 'production_codes') = 5);
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % order-run tests failed', bad, total; END IF;
  RAISE NOTICE 'all % order-run tests passed', total;
END $$;
ROLLBACK;
