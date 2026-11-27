-- ============================================================
-- SQL tests for posting standing orders (om_standing_orders_post, om_post_standing_orders_list): one order per
-- department, re-posting only adds missing items and never changes existing lines, a renamed department/event is still
-- found, date ranges, orders posted to AR and deleted orders are left alone, staff only.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/standing_orders_test.sql
-- Assumes the Alpine Bakery seed (tenant 200000000002, staff user 200000174045, active items).
-- 2031-05-12 is a Monday.
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t TO PUBLIC;
GRANT ALL ON _id TO PUBLIC;

-- ── Setup (trusted): an account with two departments and their standing orders ──
DO $$
DECLARE a bigint; k bigint; b bigint; i1 bigint; i2 bigint; i3 bigint; i4 bigint;
BEGIN
  SELECT item_id INTO i1 FROM fnd_items WHERE tenant_id = 200000000002 AND is_active ORDER BY item_id LIMIT 1;
  SELECT item_id INTO i2 FROM fnd_items WHERE tenant_id = 200000000002 AND is_active ORDER BY item_id OFFSET 1 LIMIT 1;
  SELECT item_id INTO i3 FROM fnd_items WHERE tenant_id = 200000000002 AND is_active ORDER BY item_id OFFSET 2 LIMIT 1;
  SELECT item_id INTO i4 FROM fnd_items WHERE tenant_id = 200000000002 AND is_active ORDER BY item_id OFFSET 3 LIMIT 1;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, is_standing_order) VALUES (200000000002, 'ZZ SO ACCOUNT', 'ACCOUNT', TRUE) RETURNING customer_id INTO a;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id, is_standing_order) VALUES (200000000002, 'Zz Kitchen', 'DEPARTMENT', a, TRUE) RETURNING customer_id INTO k;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id, is_standing_order) VALUES (200000000002, 'Zz Bar', 'DEPARTMENT', a, TRUE) RETURNING customer_id INTO b;
  INSERT INTO om_standing_orders (tenant_id, customer_id, production_dow, production_code, item_id, quantity) VALUES
    (200000000002, k, 'MON', 'MORNING', i1, 7),
    (200000000002, k, 'MON', 'MORNING', i2, 0),
    (200000000002, k, 'MON', 'MORNING', i3, 2),
    (200000000002, k, 'WED', 'MORNING', i1, 5),
    (200000000002, b, 'MON', 'MORNING', i1, 3);
  INSERT INTO _id VALUES ('a', a), ('k', k), ('b', b), ('i1', i1), ('i2', i2), ('i3', i3), ('i4', i4);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

DO $$
DECLARE r jsonb; l jsonb; a bigint; k bigint; b bigint; i1 bigint; i2 bigint; i3 bigint; o bigint;
BEGIN
  SELECT v INTO a FROM _id WHERE _id.k='a'; SELECT v INTO k FROM _id WHERE _id.k='k'; SELECT v INTO b FROM _id WHERE _id.k='b';
  SELECT v INTO i1 FROM _id WHERE _id.k='i1'; SELECT v INTO i2 FROM _id WHERE _id.k='i2'; SELECT v INTO i3 FROM _id WHERE _id.k='i3';

  l := om_post_standing_orders_list(200000000002, '2031-05-12', '2031-05-12', ARRAY['MORNING']);
  INSERT INTO _t VALUES ('list: both departments are NEW',
    (SELECT count(*) FROM jsonb_array_elements(l) x WHERE (x->>'customer_id')::bigint IN (k, b) AND x->>'status' = 'NEW') = 2);

  -- Post the kitchen only
  r := om_standing_orders_post(200000000002, '2031-05-12', '2031-05-12', ARRAY['MORNING'], ARRAY[k], '2031-05-10');
  INSERT INTO _t VALUES ('post: kitchen POSTED with 3 lines', r->>'posted' = '1' AND (r->'results'->0->>'lines_added')::int = 3);
  SELECT order_id INTO o FROM om_orders WHERE tenant_id = 200000000002 AND customer_id = a AND production_date = '2031-05-12';
  PERFORM set_config('t.o', o::text, false);
  INSERT INTO _t VALUES ('post: the order is under the account with the department as event',
    (SELECT department_event = 'ZZ KITCHEN' FROM om_orders WHERE order_id = o));
  INSERT INTO _t VALUES ('post: 0-quantity reminder lines are posted, none is a sample',
    (SELECT count(*) FILTER (WHERE quantity = 0) = 1 AND NOT bool_or(is_sample) FROM om_order_lines WHERE order_id = o));
  INSERT INTO _t VALUES ('post: lines are priced and the order totals are set',
    (SELECT o2.quantity = 9 FROM om_orders o2 WHERE o2.order_id = o));

  l := om_post_standing_orders_list(200000000002, '2031-05-12', '2031-05-12', ARRAY['MORNING']);
  INSERT INTO _t VALUES ('list: kitchen POSTED, bar still NEW (one department does not block the other)',
    (SELECT x->>'status' FROM jsonb_array_elements(l) x WHERE (x->>'customer_id')::bigint = k) = 'POSTED'
    AND (SELECT x->>'status' FROM jsonb_array_elements(l) x WHERE (x->>'customer_id')::bigint = b) = 'NEW');

  -- Post again: nothing changes, no -01 copy
  r := om_standing_orders_post(200000000002, '2031-05-12', '2031-05-12', ARRAY['MORNING'], NULL, '2031-05-10');
  INSERT INTO _t VALUES ('re-post: kitchen UP_TO_DATE, bar POSTED',
    (SELECT x->>'status' FROM jsonb_array_elements(r->'results') x WHERE (x->>'customer_id')::bigint = k) = 'UP_TO_DATE'
    AND (SELECT x->>'status' FROM jsonb_array_elements(r->'results') x WHERE (x->>'customer_id')::bigint = b) = 'POSTED');
  INSERT INTO _t VALUES ('re-post: no duplicate kitchen order',
    (SELECT count(*) FROM om_orders WHERE customer_id = a AND production_date = '2031-05-12' AND department_event LIKE 'ZZ KITCHEN%') = 1);
  INSERT INTO _t VALUES ('re-post: bar has its own order',
    (SELECT count(*) FROM om_orders WHERE customer_id = a AND production_date = '2031-05-12' AND department_event = 'ZZ BAR') = 1);
  INSERT INTO _t VALUES ('log: re-post counted',
    (SELECT post_count FROM om_standing_order_postings WHERE customer_id = k AND production_date = '2031-05-12') = 2);
END $$;

-- The clerk changes the order: 7 -> 0 on item 1, 2 -> 20 on item 3, renames the event; a new item joins the standing order
RESET ROLE;
DO $$
DECLARE o bigint := current_setting('t.o')::bigint; k bigint; i1 bigint; i3 bigint; i4 bigint;
BEGIN
  SELECT v INTO k FROM _id WHERE _id.k='k'; SELECT v INTO i1 FROM _id WHERE _id.k='i1'; SELECT v INTO i3 FROM _id WHERE _id.k='i3'; SELECT v INTO i4 FROM _id WHERE _id.k='i4';
  UPDATE om_order_lines SET quantity = 0 WHERE order_id = o AND item_id = i1;
  UPDATE om_order_lines SET quantity = 20 WHERE order_id = o AND item_id = i3;
  UPDATE om_orders SET department_event = 'LUNCHEON' WHERE order_id = o;
  INSERT INTO om_standing_orders (tenant_id, customer_id, production_dow, production_code, item_id, quantity) VALUES (200000000002, k, 'MON', 'MORNING', i4, 4);
END $$;
SET LOCAL ROLE authenticated;

DO $$
DECLARE r jsonb; o bigint := current_setting('t.o')::bigint; a bigint; k bigint; i1 bigint; i3 bigint; i4 bigint;
BEGIN
  SELECT v INTO a FROM _id WHERE _id.k='a'; SELECT v INTO k FROM _id WHERE _id.k='k';
  SELECT v INTO i1 FROM _id WHERE _id.k='i1'; SELECT v INTO i3 FROM _id WHERE _id.k='i3'; SELECT v INTO i4 FROM _id WHERE _id.k='i4';
  r := om_standing_orders_post(200000000002, '2031-05-12', '2031-05-12', ARRAY['MORNING'], ARRAY[k], '2031-05-10');
  INSERT INTO _t VALUES ('renamed order: found and only the new item is ADDED',
    r->'results'->0->>'status' = 'ADDED' AND (r->'results'->0->>'order_id')::bigint = o AND (r->'results'->0->>'lines_added')::int = 1);
  INSERT INTO _t VALUES ('renamed order: no new kitchen order created',
    (SELECT count(*) FROM om_orders WHERE customer_id = a AND production_date = '2031-05-12' AND department_event LIKE 'ZZ KITCHEN%') = 0);
  INSERT INTO _t VALUES ('existing lines are never changed (0 stays 0, 20 stays 20)',
    (SELECT quantity FROM om_order_lines WHERE order_id = o AND item_id = i1) = 0
    AND (SELECT quantity FROM om_order_lines WHERE order_id = o AND item_id = i3) = 20);
  INSERT INTO _t VALUES ('totals recomputed after adding (0 + 0 + 20 + 4)',
    (SELECT quantity FROM om_orders WHERE order_id = o) = 24
    AND (SELECT amount FROM om_orders WHERE order_id = o) = (SELECT sum(extended_amount) FROM om_order_lines WHERE order_id = o));
  INSERT INTO _t VALUES ('the added line has the standing order quantity',
    (SELECT quantity FROM om_order_lines WHERE order_id = o AND item_id = i4) = 4);

  -- Date range Monday..Wednesday: Wednesday has its own standing order, Tuesday has none
  r := om_standing_orders_post(200000000002, '2031-05-12', '2031-05-14', ARRAY['MORNING'], ARRAY[k], '2031-05-10');
  INSERT INTO _t VALUES ('range: Monday up to date, Wednesday POSTED, no Tuesday row',
    jsonb_array_length(r->'results') = 2
    AND (SELECT x->>'status' FROM jsonb_array_elements(r->'results') x WHERE x->>'production_date' = '2031-05-14') = 'POSTED'
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'results') x WHERE x->>'production_date' = '2031-05-13'));
  INSERT INTO _t VALUES ('range: Wednesday order has the Wednesday line only',
    (SELECT count(*) FROM om_order_lines ol JOIN om_orders o2 ON o2.order_id = ol.order_id
      WHERE o2.customer_id = a AND o2.production_date = '2031-05-14') = 1);
END $$;

-- The Monday kitchen order goes on a numbered invoice; the Wednesday order is deleted
RESET ROLE;
DO $$
DECLARE o bigint := current_setting('t.o')::bigint; a bigint; t bigint;
BEGIN
  SELECT v INTO a FROM _id WHERE _id.k='a';
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status)
  VALUES (200000000002, a, 'INV', 'ZZ-TEST-1', '2031-05-12', 0, 'OPEN') RETURNING ar_transaction_id INTO t;
  INSERT INTO ar_transaction_lines (tenant_id, ar_transaction_id, line_number, quantity, unit_price, amount, order_id)
  VALUES (200000000002, t, 1, 1, 0, 0, o);
  DELETE FROM om_orders WHERE customer_id = a AND production_date = '2031-05-14';
  INSERT INTO om_standing_orders (tenant_id, customer_id, production_dow, production_code, item_id, quantity)
  SELECT 200000000002, (SELECT v FROM _id WHERE _id.k='k'), 'MON', 'MORNING', item_id, 1
    FROM fnd_items WHERE tenant_id = 200000000002 AND is_active ORDER BY item_id OFFSET 4 LIMIT 1;
END $$;
SET LOCAL ROLE authenticated;

DO $$
DECLARE r jsonb; l jsonb; o bigint := current_setting('t.o')::bigint; k bigint; n int;
BEGIN
  SELECT v INTO k FROM _id WHERE _id.k='k';
  SELECT count(*) INTO n FROM om_order_lines WHERE order_id = o;
  r := om_standing_orders_post(200000000002, '2031-05-12', '2031-05-14', ARRAY['MORNING'], ARRAY[k], '2031-05-10');
  INSERT INTO _t VALUES ('posted to AR: left alone even with a new standing order item',
    (SELECT x->>'status' FROM jsonb_array_elements(r->'results') x WHERE x->>'production_date' = '2031-05-12') = 'POSTED_TO_AR'
    AND (SELECT count(*) FROM om_order_lines WHERE order_id = o) = n);
  INSERT INTO _t VALUES ('deleted order: left alone',
    (SELECT x->>'status' FROM jsonb_array_elements(r->'results') x WHERE x->>'production_date' = '2031-05-14') = 'ORDER_DELETED');
  l := om_post_standing_orders_list(200000000002, '2031-05-12', '2031-05-14', ARRAY['MORNING']);
  INSERT INTO _t VALUES ('list shows POSTED_TO_AR and ORDER_DELETED',
    (SELECT x->>'status' FROM jsonb_array_elements(l) x WHERE (x->>'customer_id')::bigint = k AND x->>'production_date' = '2031-05-12') = 'POSTED_TO_AR'
    AND (SELECT x->>'status' FROM jsonb_array_elements(l) x WHERE (x->>'customer_id')::bigint = k AND x->>'production_date' = '2031-05-14') = 'ORDER_DELETED');
  BEGIN
    PERFORM om_standing_orders_post(200000000002, '2031-05-01', '2031-05-31', ARRAY['MORNING']);
    INSERT INTO _t VALUES ('range over 14 days is refused', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _t VALUES ('range over 14 days is refused', SQLERRM LIKE '%at most 14 days%');
  END;
END $$;

-- Order Entry: an order filled in from the standing order (saved with from_standing_order) under another event name is
-- what posting finds later; the sample flag is saved
DO $$
DECLARE r jsonb; o bigint; b bigint; i1 bigint; i2 bigint;
BEGIN
  SELECT v INTO b FROM _id WHERE _id.k='b'; SELECT v INTO i1 FROM _id WHERE _id.k='i1'; SELECT v INTO i2 FROM _id WHERE _id.k='i2';
  r := om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', b, 'production_date', '2031-05-19', 'production_code', 'MORNING',
        'department_event', 'BAR PARTY', 'from_standing_order', true, 'lines', jsonb_build_array(
          jsonb_build_object('item_id', i1, 'item_description', 'x', 'quantity', 3, 'unit_price', 1),
          jsonb_build_object('item_id', i2, 'item_description', 'y', 'quantity', 2, 'unit_price', 0, 'is_sample', true))));
  o := (r->>'order_id')::bigint;
  INSERT INTO _t VALUES ('order save: sample flag saved', (SELECT is_sample FROM om_order_lines WHERE order_id = o AND item_id = i2)
    AND NOT (SELECT is_sample FROM om_order_lines WHERE order_id = o AND item_id = i1));
  INSERT INTO _t VALUES ('order save: filled-in order recorded for posting', (SELECT order_id FROM om_standing_order_postings WHERE customer_id = b AND production_date = '2031-05-19') = o);
  r := om_standing_orders_post(200000000002, '2031-05-19', '2031-05-19', ARRAY['MORNING'], ARRAY[b]);
  INSERT INTO _t VALUES ('posting finds the filled-in order: UP_TO_DATE, no second order',
    r->'results'->0->>'status' = 'UP_TO_DATE' AND (r->'results'->0->>'order_id')::bigint = o
    AND (SELECT count(*) FROM om_orders WHERE production_date = '2031-05-19' AND customer_id = (SELECT v FROM _id WHERE _id.k='a')) = 1);
  INSERT INTO _t VALUES ('order get returns the sample flag',
    (SELECT bool_or((l->>'is_sample')::boolean) FROM jsonb_array_elements(om_orders_get_v2(p_tenant_id => 200000000002, p_order_id => o, p_return_headers_only => false)->'lines') l));
END $$;

-- A customer-side user (restricted tenant) cannot post
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002),
                    'restricted_tenant_ids', json_build_array(200000000002)))::text, true);
DO $$
BEGIN
  PERFORM om_standing_orders_post(200000000002, '2031-05-12', '2031-05-12', ARRAY['MORNING']);
  INSERT INTO _t VALUES ('customer users cannot post', FALSE);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO _t VALUES ('customer users cannot post', SQLERRM LIKE 'Only tenant staff%');
END $$;

RESET ROLE;
SELECT CASE WHEN COALESCE(ok, false) THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT COALESCE(ok, false)), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % standing-order tests failed', bad, total; END IF;
  RAISE NOTICE 'all % standing-order tests passed', total;
END $$;
ROLLBACK;
