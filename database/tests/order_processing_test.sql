-- ============================================================
-- SQL tests for Phase 2: order save customer rules, invoice owner, delivery method, Process run (shipments + invoice
-- drafts), reprocessing, staff-only access and numbering settings. One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/order_processing_test.sql
-- Assumes the Alpine Bakery seed (tenant 200000000002, item (SELECT item_id FROM bps.fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), seeded settings and sequences).
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
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

GRANT ALL ON _id TO PUBLIC;

-- ── Setup (trusted connection): an account, two departments (one invoiced), two sites ──
DO $$
DECLARE a bigint; d1 bigint; d2 bigint; s1 bigint; s2 bigint;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (200000000002, 'TEST ACCOUNT', 'ACCOUNT') RETURNING customer_id INTO a;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id, is_invoice_required) VALUES (200000000002, 'TEST DEPT INVOICED', 'DEPARTMENT', a, TRUE) RETURNING customer_id INTO d1;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id, is_invoice_required) VALUES (200000000002, 'TEST DEPT SHARED', 'DEPARTMENT', a, FALSE) RETURNING customer_id INTO d2;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id) VALUES (200000000002, 'Test Site One', 'SITE', d1) RETURNING customer_id INTO s1;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id) VALUES (200000000002, 'Test Site Two', 'SITE', a) RETURNING customer_id INTO s2;
  INSERT INTO _id VALUES ('a', a), ('d1', d1), ('d2', d2), ('s1', s1), ('s2', s2);

  INSERT INTO _t VALUES ('invoice owner: account owns itself', om_customer_invoice_owner(200000000002, a) = a);
  INSERT INTO _t VALUES ('invoice owner: invoiced department owns itself', om_customer_invoice_owner(200000000002, d1) = d1);
  INSERT INTO _t VALUES ('invoice owner: department without the flag rolls up to the account', om_customer_invoice_owner(200000000002, d2) = a);
  INSERT INTO _t VALUES ('invoice owner: site under invoiced department -> department', om_customer_invoice_owner(200000000002, s1) = d1);
  INSERT INTO _t VALUES ('invoice owner: site under account -> account', om_customer_invoice_owner(200000000002, s2) = a);
  INSERT INTO _t VALUES ('delivery method defaults to the tenant own-fleet method', om_customer_delivery_method(200000000002, s1) = 'OWN_TRUCK');
  UPDATE fnd_customers SET delivery_method_code = 'CARRIER' WHERE customer_id = d1;
  INSERT INTO _t VALUES ('delivery method inherited from the parent', om_customer_delivery_method(200000000002, s1) = 'CARRIER');
  UPDATE fnd_customers SET delivery_method_code = NULL WHERE customer_id = d1;
END $$;

-- ── Staff: order save rules ──────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

DO $$
DECLARE r jsonb; a bigint; d1 bigint; d2 bigint; s1 bigint; s2 bigint; o record;
BEGIN
  SELECT v INTO a FROM _id WHERE k='a'; SELECT v INTO d1 FROM _id WHERE k='d1'; SELECT v INTO d2 FROM _id WHERE k='d2';
  SELECT v INTO s1 FROM _id WHERE k='s1'; SELECT v INTO s2 FROM _id WHERE k='s2';
  -- O1: account, two lines (one discounted) and a delivery charge
  r := om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', a, 'production_date', '2031-05-10', 'production_code', 'MORNING',
        'delivery_amount', 4, 'lines', jsonb_build_array(
          jsonb_build_object('item_id', (SELECT item_id FROM bps.fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), 'item_description','Roll','quantity',2,'unit_price',5),
          jsonb_build_object('item_id', (SELECT item_id FROM bps.fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), 'item_description','Loaf','quantity',1,'unit_price',3,'unit_discount',1))));
  INSERT INTO _id VALUES ('o1', (r->>'order_id')::bigint);
  FOR o IN SELECT * FROM (VALUES ('o2', d1), ('o3', d2), ('o4', s1), ('o5', s2)) AS x(k, cid) LOOP
    r := om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', o.cid, 'production_date', '2031-05-10', 'production_code', 'MORNING',
          'lines', jsonb_build_array(jsonb_build_object('item_id', (SELECT item_id FROM bps.fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), 'item_description','Bun','quantity',1,'unit_price',10))));
    INSERT INTO _id VALUES (o.k, (r->>'order_id')::bigint);
  END LOOP;

  INSERT INTO _t VALUES ('account order keeps the account customer_id, event defaults to its name',
      (SELECT customer_id = a AND department_event = 'TEST ACCOUNT' FROM om_orders WHERE order_id = (SELECT v FROM _id WHERE k='o1')));
  INSERT INTO _t VALUES ('department order keeps its own customer_id, event defaults to its name',
      (SELECT customer_id = d1 AND department_event = 'TEST DEPT INVOICED' FROM om_orders WHERE order_id = (SELECT v FROM _id WHERE k='o2')));
  INSERT INTO _t VALUES ('site order is stored under the parent, event defaults to the site name',
      (SELECT customer_id = d1 AND department_event = 'TEST SITE ONE' FROM om_orders WHERE order_id = (SELECT v FROM _id WHERE k='o4')));
  INSERT INTO _t VALUES ('site under the account is stored under the account',
      (SELECT customer_id = a AND department_event = 'TEST SITE TWO' FROM om_orders WHERE order_id = (SELECT v FROM _id WHERE k='o5')));
  INSERT INTO _t VALUES ('every order has its own order number', (SELECT COUNT(DISTINCT order_number) = 5 FROM om_orders WHERE order_id IN (SELECT v FROM _id WHERE k LIKE 'o_')));
  r := om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', s1, 'production_date', '2031-05-10', 'production_code', 'MORNING',
        'department_event', 'Judy wedding', 'lines', '[]'::jsonb));
  INSERT INTO _t VALUES ('department/event can be overridden', (SELECT department_event = 'JUDY WEDDING' FROM om_orders WHERE order_id = (r->>'order_id')::bigint));
  PERFORM om_orders_save(200000000002, 'delete', (r->>'order_id')::bigint, NULL);
END $$;

-- ── Staff: Process run ───────────────────────────────────────────────────────
DO $$
DECLARE res jsonb; a bigint; d1 bigint; d2 bigint; inv_a record; inv_d record; n int; v_run bigint; ship_nums text; ship_nums2 text; ia bigint;
BEGIN
  SELECT v INTO a FROM _id WHERE k='a'; SELECT v INTO d1 FROM _id WHERE k='d1'; SELECT v INTO d2 FROM _id WHERE k='d2';
  res := om_production_runs_process(200000000002, DATE '2031-05-10', DATE '2031-05-10', 'morning');
  v_run := (res->0->>'production_run_id')::bigint;
  INSERT INTO _t VALUES ('process: one run processed with 5 orders, 2 invoices, 3 shipments',
      jsonb_array_length(res) = 1 AND (res->0->>'orders')::int = 5 AND (res->0->>'invoices')::int = 2 AND (res->0->>'shipments')::int = 3);
  INSERT INTO _t VALUES ('process: run is PROCESSED', (SELECT run_status = 'PROCESSED' AND processed_at IS NOT NULL FROM om_production_runs WHERE production_run_id = v_run));

  SELECT * INTO inv_a FROM ar_transactions WHERE production_run_id = v_run AND customer_id = a AND transaction_type = 'INV';
  SELECT * INTO inv_d FROM ar_transactions WHERE production_run_id = v_run AND customer_id = d1 AND transaction_type = 'INV';
  INSERT INTO _t VALUES ('invoice A is DRAFT without a number, total 36 (10+2+4 delivery + 10 + 10)', inv_a.status = 'DRAFT' AND inv_a.document_number IS NULL AND inv_a.amount = 36);
  INSERT INTO _t VALUES ('invoice D1 (department + its site) is DRAFT, total 20', inv_d.status = 'DRAFT' AND inv_d.amount = 20);
  INSERT INTO _t VALUES ('invoice A has 5 lines (3 order lines + delivery + 1 more order... )',
      (SELECT COUNT(*) FROM ar_transaction_lines WHERE ar_transaction_id = inv_a.ar_transaction_id) = 5);
  INSERT INTO _t VALUES ('invoice D1 has 2 lines', (SELECT COUNT(*) FROM ar_transaction_lines WHERE ar_transaction_id = inv_d.ar_transaction_id) = 2);
  INSERT INTO _t VALUES ('discounted line is net of discount (qty 1 at 2.00)',
      EXISTS (SELECT 1 FROM ar_transaction_lines WHERE ar_transaction_id = inv_a.ar_transaction_id AND item_description = 'Loaf' AND unit_price = 2 AND amount = 2));
  INSERT INTO _t VALUES ('delivery charge becomes a DELIVERY line of 4',
      EXISTS (SELECT 1 FROM ar_transaction_lines WHERE ar_transaction_id = inv_a.ar_transaction_id AND source_type = 'DELIVERY' AND amount = 4));
  INSERT INTO _t VALUES ('invoice lines carry order number and department/event',
      (SELECT COUNT(*) FROM ar_transaction_lines WHERE ar_transaction_id = inv_d.ar_transaction_id AND snapshot_data ->> 'order_number' IS NOT NULL AND snapshot_data ->> 'department_event' IN ('TEST DEPT INVOICED','TEST SITE ONE')) = 2);
  INSERT INTO _t VALUES ('every item line is linked to a shipment line',
      (SELECT COUNT(*) FROM ar_transaction_lines WHERE ar_transaction_id IN (inv_a.ar_transaction_id, inv_d.ar_transaction_id) AND source_type = 'ITEM' AND shipment_line_id IS NULL) = 0);
  INSERT INTO _t VALUES ('3 PLANNED shipments with numbers, one per ship-to customer',
      (SELECT COUNT(*) = 3 AND COUNT(DISTINCT ship_to_customer_id) = 3 AND bool_and(shipment_status = 'PLANNED' AND shipment_number LIKE 'SHP-%' AND delivery_method_code = 'OWN_TRUCK' AND delivery_date = DATE '2031-05-11')
         FROM om_shipments WHERE production_run_id = v_run));
  INSERT INTO _t VALUES ('shipment lines mirror order lines (6 lines)', (SELECT COUNT(*) FROM om_shipment_lines l JOIN om_shipments s USING (shipment_id) WHERE s.production_run_id = v_run) = 6);

  -- a zero-quantity order line is neither shipped nor billed
  PERFORM om_orders_save(200000000002, NULL, (SELECT v FROM _id WHERE k='o2'), jsonb_build_object('customer_id', d1, 'production_date', '2031-05-10', 'production_code', 'MORNING',
        'lines', jsonb_build_array(jsonb_build_object('item_id', (SELECT item_id FROM bps.fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), 'item_description','Bun','quantity',1,'unit_price',10),
                                   jsonb_build_object('item_id', (SELECT item_id FROM bps.fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), 'item_description','Zero','quantity',0,'unit_price',7))));
  PERFORM om_production_runs_process(200000000002, DATE '2031-05-10', DATE '2031-05-10', NULL);
  INSERT INTO _t VALUES ('zero-quantity lines are not billed or shipped',
      NOT EXISTS (SELECT 1 FROM ar_transaction_lines WHERE item_description = 'Zero') AND NOT EXISTS (SELECT 1 FROM om_shipment_lines sl JOIN om_order_lines ol USING (order_line_id) WHERE ol.item_description = 'Zero'));

  -- reprocess is idempotent: same invoices, same shipment numbers
  SELECT string_agg(shipment_number, ',' ORDER BY shipment_number) INTO ship_nums FROM om_shipments WHERE production_run_id = v_run;
  ia := inv_a.ar_transaction_id;
  PERFORM om_production_runs_process(200000000002, DATE '2031-05-10', DATE '2031-05-10', NULL);
  SELECT string_agg(shipment_number, ',' ORDER BY shipment_number) INTO ship_nums2 FROM om_shipments WHERE production_run_id = v_run;
  INSERT INTO _t VALUES ('reprocess keeps the same invoice rows', (SELECT ar_transaction_id FROM ar_transactions WHERE production_run_id = v_run AND customer_id = a AND transaction_type='INV') = ia
      AND (SELECT COUNT(*) FROM ar_transactions WHERE production_run_id = v_run AND transaction_type='INV') = 2);
  INSERT INTO _t VALUES ('reprocess keeps the same shipment numbers', ship_nums = ship_nums2);

  -- an order edit flows into the invoice
  PERFORM om_orders_save(200000000002, NULL, (SELECT v FROM _id WHERE k='o3'), jsonb_build_object('customer_id', d2, 'production_date', '2031-05-10', 'production_code', 'MORNING',
        'lines', jsonb_build_array(jsonb_build_object('item_id', (SELECT item_id FROM bps.fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), 'item_description','Bun','quantity',2,'unit_price',10))));
  PERFORM om_production_runs_process(200000000002, DATE '2031-05-10', DATE '2031-05-10', NULL);
  INSERT INTO _t VALUES ('order edit then reprocess updates the invoice total to 46', (SELECT amount FROM ar_transactions WHERE ar_transaction_id = ia) = 46);

  -- removing the orders of the invoiced department drops its draft invoice
  PERFORM om_orders_save(200000000002, 'delete', (SELECT v FROM _id WHERE k='o2'), NULL);
  PERFORM om_orders_save(200000000002, 'delete', (SELECT v FROM _id WHERE k='o4'), NULL);
  PERFORM om_production_runs_process(200000000002, DATE '2031-05-10', DATE '2031-05-10', NULL);
  INSERT INTO _t VALUES ('draft invoice with no orders left is deleted', NOT EXISTS (SELECT 1 FROM ar_transactions WHERE production_run_id = v_run AND customer_id = d1));
  INSERT INTO _t VALUES ('its shipment is removed too', (SELECT COUNT(*) FROM om_shipments WHERE production_run_id = v_run) = 2);

  -- a numbered (OPEN) invoice whose orders are gone is cancelled, not deleted
  UPDATE ar_transactions SET status = 'OPEN', document_number = 'TESTINV-1' WHERE ar_transaction_id = ia;
  PERFORM om_orders_save(200000000002, 'delete', (SELECT v FROM _id WHERE k='o1'), NULL);
  PERFORM om_orders_save(200000000002, 'delete', (SELECT v FROM _id WHERE k='o3'), NULL);
  PERFORM om_orders_save(200000000002, 'delete', (SELECT v FROM _id WHERE k='o5'), NULL);
  PERFORM om_production_runs_process(200000000002, DATE '2031-05-10', DATE '2031-05-10', NULL);
  INSERT INTO _t VALUES ('numbered invoice with no orders left is CANCELLED (kept)', (SELECT status FROM ar_transactions WHERE ar_transaction_id = ia) = 'CANCELLED');
END $$;

-- ── shipped runs cannot be reprocessed; closed runs neither ─────────────────
RESET ROLE;
DO $$
DECLARE v_run bigint; a bigint; d boolean;
BEGIN
  SELECT v INTO a FROM _id WHERE k='a';
  SELECT production_run_id INTO v_run FROM om_production_runs WHERE tenant_id = 200000000002 AND production_date = DATE '2031-05-10' AND production_code = 'MORNING';
  INSERT INTO om_shipments (tenant_id, production_run_id, ship_to_customer_id, shipment_number, delivery_date, shipment_status)
    VALUES (200000000002, v_run, a, 'TESTSHIP-1', DATE '2031-05-11', 'SHIPPED');
  BEGIN PERFORM om_production_run_process(200000000002, v_run); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a run with shipped deliveries cannot be processed again', d);
  DELETE FROM om_shipments WHERE shipment_number = 'TESTSHIP-1';
  UPDATE om_production_runs SET run_status = 'CLOSED' WHERE production_run_id = v_run;
  BEGIN PERFORM om_production_run_process(200000000002, v_run); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a closed run cannot be processed', d);
  UPDATE om_production_runs SET run_status = 'PROCESSED' WHERE production_run_id = v_run;
END $$;

-- ── Customer (restricted) callers and numbering settings ────────────────────
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', current_setting('t.cust_user')::bigint))::text, true);
DO $$
DECLARE d boolean; v_run bigint; j jsonb;
BEGIN
  SELECT production_run_id INTO v_run FROM om_production_runs WHERE tenant_id = 200000000002 AND production_date = DATE '2031-05-10' AND production_code = 'MORNING';
  BEGIN PERFORM om_production_run_process(200000000002, v_run); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot process a run', d);
  BEGIN PERFORM om_production_runs_process(200000000002, DATE '2031-05-10', DATE '2031-05-10', NULL); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot process runs by range', d);
  BEGIN PERFORM fnd_tenant_sequences_save(200000000002, '{"sequence_name":"invoice_number","mask":"X-####"}'::jsonb); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot change numbering', d);
  INSERT INTO _t VALUES ('a customer user sees no invoices of other customers', NOT EXISTS (SELECT 1 FROM ar_transactions WHERE customer_id <> ALL (fnd_scope_customer_ids())));
  INSERT INTO _t VALUES ('a customer user sees no shipments of other customers', (SELECT COUNT(*) FROM om_shipments) = 0);
END $$;

SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);
DO $$
DECLARE j jsonb; d boolean;
BEGIN
  j := fnd_tenant_sequences_get(200000000002);
  INSERT INTO _t VALUES ('numbering get returns the 4 sequences', jsonb_array_length(j) = 4 AND (j -> 1 ->> 'sequence_name') = 'invoice_number');
  PERFORM fnd_tenant_sequences_save(200000000002, '{"sequence_name":"invoice_number","mask":"INV-[YYYY]-#####","start_value":5000,"next_value":5000,"reset_period":"YEARLY"}'::jsonb);
  INSERT INTO _t VALUES ('staff can save the invoice numbering mask', (SELECT mask = 'INV-[YYYY]-#####' AND reset_period = 'YEARLY' FROM fnd_tenant_sequences WHERE tenant_id = 200000000002 AND sequence_name = 'invoice_number'));
  PERFORM fnd_tenant_sequences_save(200000000002, '{"sequence_name":"invoice_number","mask":"INV-######","start_value":1000,"next_value":10}'::jsonb);
  INSERT INTO _t VALUES ('next_value never goes backwards', (SELECT next_value >= 5000 FROM fnd_tenant_sequences WHERE tenant_id = 200000000002 AND sequence_name = 'invoice_number'));
  BEGIN PERFORM fnd_tenant_sequences_save(200000000002, '{"sequence_name":"invoice_number","mask":"NOHASH"}'::jsonb); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a mask without # is rejected', d);
  BEGIN PERFORM fnd_tenant_sequences_save(200000000002, '{"sequence_name":"bogus","mask":"#"}'::jsonb); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('an unknown sequence is rejected', d);
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % order-processing tests failed', bad, total; END IF;
  RAISE NOTICE 'all % order-processing tests passed', total;
END $$;
ROLLBACK;
