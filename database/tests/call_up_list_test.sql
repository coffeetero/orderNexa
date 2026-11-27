-- ============================================================
-- SQL tests for the Call Up List: call settings per standing order customer + day + time (om_standing_order_call_get /
-- _save), the day's list (om_call_up_list_get: one row per customer, all of that day's orders, not posted flag,
-- assigned clerks, inactive customers left out) and ticking Called (om_call_up_called_set). Staff only.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/call_up_list_test.sql
-- Assumes the Alpine Bakery seed (tenant 200000000002, staff user 200000174045, active items). 2031-07-07 is a Monday.
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t TO PUBLIC;
GRANT ALL ON _id TO PUBLIC;

DO $$
DECLARE a bigint; k bigint; x bigint; i1 bigint;
BEGIN
  SELECT item_id INTO i1 FROM fnd_items WHERE tenant_id = 200000000002 AND is_active ORDER BY item_id LIMIT 1;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, is_standing_order) VALUES (200000000002, 'ZZ CALL ACCOUNT', 'ACCOUNT', TRUE) RETURNING customer_id INTO a;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id, is_standing_order, customer_number) VALUES (200000000002, 'Zz Call Kitchen', 'DEPARTMENT', a, TRUE, 'ZZ9001') RETURNING customer_id INTO k;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, is_standing_order, is_active) VALUES (200000000002, 'ZZ CALL INACTIVE', 'ACCOUNT', TRUE, FALSE) RETURNING customer_id INTO x;
  INSERT INTO om_standing_orders (tenant_id, customer_id, production_dow, production_code, item_id, quantity) VALUES
    (200000000002, k, 'MON', 'MORNING', i1, 0), (200000000002, k, 'MON', 'LUNCH', i1, 2), (200000000002, x, 'MON', 'MORNING', i1, 1);
  INSERT INTO _id VALUES ('a', a), ('k', k), ('x', x);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

DO $$
DECLARE r jsonb; l jsonb; k bigint; x bigint; row jsonb;
BEGIN
  SELECT v INTO k FROM _id WHERE _id.k = 'k'; SELECT v INTO x FROM _id WHERE _id.k = 'x';
  r := om_standing_order_call_get(200000000002, k, 'MON', 'MORNING');
  INSERT INTO _t VALUES ('call get: off by default, staff users listed', r->>'is_call' = 'false' AND jsonb_array_length(r->'users') >= 1);

  r := om_standing_order_call_save(200000000002, k, ARRAY['MON', 'TUE'], 'MORNING', true, 200000174045);
  INSERT INTO _t VALUES ('call save: on and assigned, for each day given',
    r->>'is_call' = 'true' AND (r->>'assigned_user_id')::bigint = 200000174045
    AND (SELECT count(*) FROM om_standing_order_calls WHERE customer_id = k AND is_call) = 2);
  PERFORM om_standing_order_call_save(200000000002, x, ARRAY['MON'], 'MORNING', true, NULL);

  l := om_call_up_list_get(200000000002, '2031-07-07');
  row := (SELECT e FROM jsonb_array_elements(l) e WHERE (e->>'customer_id')::bigint = k);
  INSERT INTO _t VALUES ('list: the department is on Monday''s list, not posted, no orders, assigned clerk named',
    row IS NOT NULL AND (row->>'not_posted')::boolean AND jsonb_array_length(row->'orders') = 0
    AND jsonb_array_length(row->'assigned') = 1 AND row->>'called_at' IS NULL);
  INSERT INTO _t VALUES ('list: inactive customers are left out', NOT EXISTS (SELECT 1 FROM jsonb_array_elements(l) e WHERE (e->>'customer_id')::bigint = x));

  -- PM also ticked: still one row; after posting both times, both orders show
  PERFORM om_standing_order_call_save(200000000002, k, ARRAY['MON'], 'LUNCH', true, NULL);
  PERFORM om_standing_orders_post(200000000002, '2031-07-07', '2031-07-07', ARRAY['MORNING', 'LUNCH'], ARRAY[k]);
  l := om_call_up_list_get(200000000002, '2031-07-07');
  INSERT INTO _t VALUES ('list: one row per customer even with two times ticked',
    (SELECT count(*) FROM jsonb_array_elements(l) e WHERE (e->>'customer_id')::bigint = k) = 1);
  row := (SELECT e FROM jsonb_array_elements(l) e WHERE (e->>'customer_id')::bigint = k);
  INSERT INTO _t VALUES ('list: after posting, posted and both of the day''s orders (AM and PM) listed',
    NOT (row->>'not_posted')::boolean AND jsonb_array_length(row->'orders') = 2);

  -- Called
  r := om_call_up_called_set(200000000002, k, '2031-07-07', true);
  l := om_call_up_list_get(200000000002, '2031-07-07');
  row := (SELECT e FROM jsonb_array_elements(l) e WHERE (e->>'customer_id')::bigint = k);
  INSERT INTO _t VALUES ('called: ticked, with time and who', row->>'called_at' IS NOT NULL AND row->>'called_by' IS NOT NULL);
  PERFORM om_call_up_called_set(200000000002, k, '2031-07-07', false);
  l := om_call_up_list_get(200000000002, '2031-07-07');
  row := (SELECT e FROM jsonb_array_elements(l) e WHERE (e->>'customer_id')::bigint = k);
  INSERT INTO _t VALUES ('called: unticked again', row->>'called_at' IS NULL);
  INSERT INTO _t VALUES ('called: another day is separate',
    NOT EXISTS (SELECT 1 FROM om_call_up_called WHERE customer_id = k AND call_date <> '2031-07-07'));

  -- Wednesday: not ticked, not on the list
  l := om_call_up_list_get(200000000002, '2031-07-09');
  INSERT INTO _t VALUES ('list: a day without Call ticked does not list the customer',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(l) e WHERE (e->>'customer_id')::bigint = k));

  BEGIN
    PERFORM om_standing_order_call_save(200000000002, k, ARRAY['MON'], 'MORNING', true, -1);
    INSERT INTO _t VALUES ('call save: only staff of this company can be assigned', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _t VALUES ('call save: only staff of this company can be assigned', SQLERRM LIKE 'Calls can only be assigned%');
  END;
END $$;

SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002),
                    'restricted_tenant_ids', json_build_array(200000000002)))::text, true);
DO $$
BEGIN
  PERFORM om_call_up_list_get(200000000002, '2031-07-07');
  INSERT INTO _t VALUES ('customer users cannot see the call up list', FALSE);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO _t VALUES ('customer users cannot see the call up list', SQLERRM LIKE 'Only tenant staff%');
END $$;

RESET ROLE;
SELECT CASE WHEN COALESCE(ok, false) THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT COALESCE(ok, false)), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % call-up tests failed', bad, total; END IF;
  RAISE NOTICE 'all % call-up tests passed', total;
END $$;
ROLLBACK;
