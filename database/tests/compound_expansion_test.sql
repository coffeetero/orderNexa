-- ============================================================
-- SQL tests for compound item expansion in production reports (om_run_item_quantities, Baker's Report).
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q < database/tests/compound_expansion_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t, _id TO PUBLIC;

DO $$
DECLARE acc bigint; s1 bigint; s2 bigint; bk bigint; empty_bk bigint;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, is_active) VALUES (200000000002, 'zz Expansion Account', 'ACCOUNT', true) RETURNING customer_id INTO acc;
  INSERT INTO fnd_items (tenant_id, item_number, item_name, category, unit_of_sale) VALUES (200000000002, 'zz-S1', 'zz Small Breads', 'ZZCAT', 'PCS') RETURNING item_id INTO s1;
  INSERT INTO fnd_items (tenant_id, item_number, item_name, category, unit_of_sale) VALUES (200000000002, 'zz-S2', 'zz Small Baguettes', 'ZZCAT', 'PCS') RETURNING item_id INTO s2;
  INSERT INTO fnd_items (tenant_id, item_number, item_name, category, unit_of_sale, is_compound) VALUES (200000000002, 'zz-BK', 'zz Gift Basket', 'ZZBASKET', 'PCS', true) RETURNING item_id INTO bk;
  INSERT INTO fnd_items (tenant_id, item_number, item_name, category, unit_of_sale, is_compound) VALUES (200000000002, 'zz-EMPTY', 'zz Empty Basket', 'ZZBASKET', 'PCS', true) RETURNING item_id INTO empty_bk;
  INSERT INTO fnd_item_bom (tenant_id, parent_item_id, item_id, quantity) VALUES (200000000002, bk, s1, 2), (200000000002, bk, s2, 3);
  INSERT INTO _id VALUES ('acc', acc), ('s1', s1), ('s2', s2), ('bk', bk), ('ebk', empty_bk);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

DO $$
DECLARE acc bigint; s1 bigint; s2 bigint; bk bigint; ebk bigint; r jsonb; run jsonb; it jsonb;
BEGIN
  SELECT v INTO acc FROM _id WHERE k='acc'; SELECT v INTO s1 FROM _id WHERE k='s1'; SELECT v INTO s2 FROM _id WHERE k='s2';
  SELECT v INTO bk FROM _id WHERE k='bk'; SELECT v INTO ebk FROM _id WHERE k='ebk';
  -- order 1: 2 baskets + 1 small bread; order 2: 4 small baguettes; order 3: 1 empty basket
  PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', acc, 'production_date', '2033-05-05', 'production_code', 'MORNING', 'department_event', 'ONE',
     'lines', jsonb_build_array(jsonb_build_object('item_id', bk, 'item_description', 'Basket', 'quantity', 2, 'unit_price', 30),
                                jsonb_build_object('item_id', s1, 'item_description', 'Bread', 'quantity', 1, 'unit_price', 1))));
  PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', acc, 'production_date', '2033-05-05', 'production_code', 'MORNING', 'department_event', 'TWO',
     'lines', jsonb_build_array(jsonb_build_object('item_id', s2, 'item_description', 'Baguette', 'quantity', 4, 'unit_price', 2))));
  PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', acc, 'production_date', '2033-05-05', 'production_code', 'MORNING', 'department_event', 'THREE',
     'lines', jsonb_build_array(jsonb_build_object('item_id', ebk, 'item_description', 'Empty', 'quantity', 1, 'unit_price', 5))));

  r := om_report_bakers_get(200000000002, DATE '2033-05-05', DATE '2033-05-05', NULL);
  run := r -> 'runs' -> 0;
  SELECT x INTO it FROM jsonb_array_elements(run -> 'categories') c, jsonb_array_elements(c -> 'items') x WHERE x ->> 'item_number' = 'zz-S1';
  INSERT INTO _t VALUES ('a basket is expanded: small breads = 2 baskets x 2 + 1 ordered alone = 5', (it ->> 'quantity')::numeric = 5);
  INSERT INTO _t VALUES ('in_compounds shows how much of the quantity comes from baskets (4 of 5)', (it ->> 'in_compounds')::numeric = 4);
  SELECT x INTO it FROM jsonb_array_elements(run -> 'categories') c, jsonb_array_elements(c -> 'items') x WHERE x ->> 'item_number' = 'zz-S2';
  INSERT INTO _t VALUES ('small baguettes = 2 baskets x 3 + 4 ordered alone = 10 (6 from baskets)', (it ->> 'quantity')::numeric = 10 AND (it ->> 'in_compounds')::numeric = 6);
  INSERT INTO _t VALUES ('the run total counts the items to bake (5 + 10), not the baskets', (run ->> 'total_quantity')::numeric = 15);
  INSERT INTO _t VALUES ('the basket itself is not in any category', NOT EXISTS (SELECT 1 FROM jsonb_array_elements(run -> 'categories') c, jsonb_array_elements(c -> 'items') x WHERE x ->> 'item_number' IN ('zz-BK', 'zz-EMPTY')));
  INSERT INTO _t VALUES ('baskets to assemble are listed with quantity and orders', EXISTS (SELECT 1 FROM jsonb_array_elements(run -> 'compounds') x WHERE x ->> 'item_number' = 'zz-BK' AND (x ->> 'quantity')::numeric = 2 AND (x ->> 'order_count')::int = 1));
  INSERT INTO _t VALUES ('a basket with no components is still listed to assemble', EXISTS (SELECT 1 FROM jsonb_array_elements(run -> 'compounds') x WHERE x ->> 'item_number' = 'zz-EMPTY'));
  INSERT INTO _t VALUES ('the run still counts all 3 orders', (run ->> 'order_count')::int = 3);
  RESET ROLE;
END $$;

SELECT name, CASE WHEN ok THEN 'ok' ELSE 'FAIL' END AS result FROM _t WHERE NOT ok;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM _t;
ROLLBACK;
