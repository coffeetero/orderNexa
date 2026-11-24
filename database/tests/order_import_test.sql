-- ============================================================
-- SQL tests for Import Orders: row checks, one order per cus no, replace on re-upload, production exclusion until approved,
-- approve / delete rules, row security. One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/order_import_test.sql
-- Assumes the Alpine Bakery migration: account FEATHERSTONE BAKING (15700) with departments 15702 and 15703, account AR&C (11200),
-- items priced in Featherstone's pricing book (the items on old invoice 546222), staff user 200000174045, customer user 200000174046.
-- Runs as the staff user with the claims the sign-in hook builds. Uses production date 2033-03-07 MORNING (no other orders).
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _v (k text PRIMARY KEY, v text);
GRANT ALL ON _t, _v TO PUBLIC;

-- test values: two priced items, one active item with no price for Featherstone
INSERT INTO _v SELECT 'item1', i.item_number FROM fnd_items i WHERE i.item_id IN (SELECT l.item_id FROM ar_transaction_lines l JOIN ar_transactions t USING (ar_transaction_id)
  WHERE t.tenant_id = 200000000002 AND t.document_number = '546222') ORDER BY i.item_number LIMIT 1;
INSERT INTO _v SELECT 'item2', i.item_number FROM fnd_items i WHERE i.item_id IN (SELECT l.item_id FROM ar_transaction_lines l JOIN ar_transactions t USING (ar_transaction_id)
  WHERE t.tenant_id = 200000000002 AND t.document_number = '546222') ORDER BY i.item_number DESC LIMIT 1;
INSERT INTO _v SELECT 'unpriced', i.item_number FROM fnd_items i WHERE i.tenant_id = 200000000002 AND i.is_active AND i.item_number IS NOT NULL
  AND NOT (bps.fnd_item_prices_map(200000000002, (SELECT customer_id FROM fnd_customers WHERE tenant_id = 200000000002 AND customer_number = '15700' AND customer_type = 'ACCOUNT'),
           DATE '2033-03-08', NULL) ? i.item_id::text) ORDER BY i.item_number LIMIT 1;
INSERT INTO _v SELECT 'account', customer_id::text FROM fnd_customers WHERE tenant_id = 200000000002 AND customer_number = '15700' AND customer_type = 'ACCOUNT';

SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b',
  'claims', jsonb_build_object('role', 'authenticated', 'sub', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b', 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) \g /dev/null
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  t bigint := 200000000002; acc bigint := (SELECT v FROM _v WHERE k = 'account')::bigint;
  i1 text := (SELECT v FROM _v WHERE k = 'item1'); i2 text := (SELECT v FROM _v WHERE k = 'item2'); np text := (SELECT v FROM _v WHERE k = 'unpriced');
  r jsonb; imp bigint; imp2 bigint; p jsonb; d boolean; n int; hand bigint;
  base jsonb := jsonb_build_object('customer_id', acc, 'production_date', '2033-03-07', 'production_code', 'MORNING', 'file_name', 'test.csv');
BEGIN
  -- a hand-entered order in the same slot must survive every import action
  hand := (bps.om_orders_save(t, NULL, NULL, jsonb_build_object('customer_id', acc, 'production_date', '2033-03-07', 'production_code', 'MORNING',
           'department_event', 'HAND', 'lines', jsonb_build_array(jsonb_build_object('item_id', (SELECT item_id FROM fnd_items WHERE tenant_id = t AND item_number = i1),
           'quantity', 1, 'unit_price', 1)))) ->> 'order_id')::bigint;

  -- 1) a file with good rows and every kind of problem
  r := bps.om_order_import_upload(t, base || jsonb_build_object('rows', jsonb_build_array(
         jsonb_build_object('cus_no', '15702', 'item_number', i1, 'item_desc', 'x', 'qty', '2'),
         jsonb_build_object('cus_no', '15702', 'item_number', i2, 'item_desc', (SELECT item_name FROM fnd_items WHERE tenant_id = t AND item_number = i2), 'qty', '3'),
         jsonb_build_object('cus_no', '15703', 'item_number', i1, 'item_desc', (SELECT item_name FROM fnd_items WHERE tenant_id = t AND item_number = i1), 'qty', '1.5'),
         jsonb_build_object('cus_no', '99999999', 'item_number', i1, 'item_desc', '', 'qty', '1'),
         jsonb_build_object('cus_no', '11200', 'item_number', i1, 'item_desc', '', 'qty', '1'),
         jsonb_build_object('cus_no', '15703', 'item_number', 'NOPE-1', 'item_desc', '', 'qty', '1'),
         jsonb_build_object('cus_no', '15702', 'item_number', i1, 'item_desc', '', 'qty', '0'),
         jsonb_build_object('cus_no', '15703', 'item_number', np, 'item_desc', '', 'qty', '1'))));
  imp := (r ->> 'order_import_id')::bigint;
  INSERT INTO _t VALUES ('upload keeps all 8 rows, 5 with errors, 1 warning', (r ->> 'row_count')::int = 8 AND (r ->> 'error_count')::int = 5 AND (r ->> 'warning_count')::int = 1);
  INSERT INTO _t VALUES ('import is ISSUES', r ->> 'import_status' = 'ISSUES');
  INSERT INTO _t VALUES ('one order per cus no from the good rows (15702: 2 lines, 15703: 1 line)', (r ->> 'order_count')::int = 2
     AND (SELECT count(*) FROM om_order_lines l JOIN om_orders o USING (order_id) WHERE o.order_import_id = imp) = 3);
  INSERT INTO _t VALUES ('unknown customer number is reported', EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'rows') x WHERE x ->> 'cus_no' = '99999999' AND x ->> 'issue' LIKE '%not found'));
  INSERT INTO _t VALUES ('a customer of another account is reported', EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'rows') x WHERE x ->> 'cus_no' = '11200' AND x ->> 'issue' LIKE '%another account'));
  INSERT INTO _t VALUES ('unknown item, zero quantity and missing price are errors',
     (SELECT count(*) FROM jsonb_array_elements(r -> 'rows') x WHERE x ->> 'severity' = 'ERROR' AND (x ->> 'issue' LIKE 'Item%not found' OR x ->> 'issue' LIKE 'Quantity%' OR x ->> 'issue' LIKE 'No price%')) = 3);
  INSERT INTO _t VALUES ('a different description is only a warning and the line is still imported',
     EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'rows') x WHERE x ->> 'severity' = 'WARNING' AND x ->> 'order_number' IS NOT NULL));
  INSERT INTO _t VALUES ('lines are priced from the pricing book (amount = qty x price)',
     (SELECT bool_and(l.extended_amount = round(l.quantity * l.unit_price, 2) AND l.unit_price > 0) FROM om_order_lines l JOIN om_orders o USING (order_id) WHERE o.order_import_id = imp));
  INSERT INTO _t VALUES ('orders are marked Import; 15702 (has a bad row) ISSUES, 15703 also ISSUES (unknown item, no price)',
     (SELECT bool_and(order_source = 'Import' AND import_status = 'ISSUES') FROM om_orders WHERE order_import_id = imp));
  INSERT INTO _t VALUES ('import total = sum of its orders', (r ->> 'total_amount')::numeric = (SELECT SUM(amount) FROM om_orders WHERE order_import_id = imp));

  BEGIN PERFORM bps.om_order_import_approve(t, imp); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('approve is refused while rows have errors', d);

  -- 2) production leaves unapproved imports out
  p := bps.om_production_runs_process(t, DATE '2033-03-07', DATE '2033-03-07', 'MORNING') -> 0;
  INSERT INTO _t VALUES ('process run counts only the hand order and reports 2 waiting for approval', (p ->> 'orders')::int = 1 AND (p ->> 'orders_waiting_approval')::int = 2);
  INSERT INTO _t VALUES ('the invoice holds only the hand order', (SELECT count(DISTINCT (l.snapshot_data ->> 'order_id')) FROM ar_transaction_lines l JOIN ar_transactions x USING (ar_transaction_id)
     WHERE x.production_run_id = (p ->> 'production_run_id')::bigint) = 1);
  INSERT INTO _t VALUES ('baker''s quantities leave imported orders out', (SELECT count(DISTINCT q.order_id) FROM om_run_item_quantities(t, (p ->> 'production_run_id')::bigint) q) = 1);
  INSERT INTO _t VALUES ('runs list shows the waiting orders', EXISTS (SELECT 1 FROM jsonb_array_elements(bps.om_production_runs_get(t, DATE '2033-03-07', DATE '2033-03-07')) x
     WHERE (x ->> 'orders_waiting_approval')::int = 2 AND (x ->> 'order_count')::int = 1));

  -- 3) a corrected file replaces the unapproved import
  r := bps.om_order_import_upload(t, base || jsonb_build_object('rows', jsonb_build_array(
         jsonb_build_object('cus_no', '15702', 'item_number', i1, 'item_desc', '', 'qty', '2'),
         jsonb_build_object('cus_no', '15703', 'item_number', i2, 'item_desc', '', 'qty', '4'))));
  imp2 := (r ->> 'order_import_id')::bigint;
  INSERT INTO _t VALUES ('re-upload replaces the unapproved import and its orders', NOT EXISTS (SELECT 1 FROM om_order_imports WHERE order_import_id = imp)
     AND (SELECT count(*) FROM om_orders WHERE order_import_id = imp) = 0 AND (r ->> 'order_count')::int = 2);
  INSERT INTO _t VALUES ('a clean file is IMPORTED (ready to approve)', r ->> 'import_status' = 'IMPORTED' AND (r ->> 'error_count')::int = 0);
  INSERT INTO _t VALUES ('the hand-entered order is untouched', EXISTS (SELECT 1 FROM om_orders WHERE order_id = hand AND order_import_id IS NULL));

  -- 4) approve, then production includes the orders
  r := bps.om_order_import_approve(t, imp2);
  INSERT INTO _t VALUES ('approve marks the import and its orders APPROVED and asks to reprocess the processed run',
     r ->> 'import_status' = 'APPROVED' AND (r ->> 'needs_reprocess')::boolean
     AND (SELECT bool_and(import_status = 'APPROVED') FROM om_orders WHERE order_import_id = imp2));
  p := bps.om_production_runs_process(t, DATE '2033-03-07', DATE '2033-03-07', 'MORNING') -> 0;
  INSERT INTO _t VALUES ('after approval the run has 3 orders, none waiting', (p ->> 'orders')::int = 3 AND (p ->> 'orders_waiting_approval')::int = 0);
  INSERT INTO _t VALUES ('one invoice for the account includes the imported orders',
     (SELECT x.amount FROM ar_transactions x WHERE x.production_run_id = (p ->> 'production_run_id')::bigint AND x.status <> 'CANCELLED')
       = (SELECT SUM(amount) FROM om_orders WHERE production_run_id = (p ->> 'production_run_id')::bigint));

  BEGIN PERFORM bps.om_order_import_delete(t, imp2); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('an approved import cannot be deleted', d);
  BEGIN PERFORM bps.om_order_import_upload(t, base || jsonb_build_object('rows', jsonb_build_array(jsonb_build_object('cus_no', '15702', 'item_number', i1, 'item_desc', '', 'qty', '1'))));
        d := EXISTS (SELECT 1 FROM om_order_imports WHERE order_import_id = imp2 AND import_status = 'APPROVED'); EXCEPTION WHEN OTHERS THEN d := false; END;
  INSERT INTO _t VALUES ('a new upload never replaces an approved import', d);

  -- 5) delete an unapproved import
  r := bps.om_order_import_upload(t, jsonb_build_object('customer_id', acc, 'production_date', '2033-03-07', 'production_code', 'LUNCH', 'rows',
         jsonb_build_array(jsonb_build_object('cus_no', '15702', 'item_number', i1, 'item_desc', '', 'qty', '1'))));
  n := (bps.om_order_import_delete(t, (r ->> 'order_import_id')::bigint) ->> 'deleted_orders')::int;
  INSERT INTO _t VALUES ('deleting an unapproved import removes it and its orders', n = 1 AND NOT EXISTS (SELECT 1 FROM om_order_imports WHERE order_import_id = (r ->> 'order_import_id')::bigint));

  -- 6) input checks
  BEGIN PERFORM bps.om_order_import_upload(t, base || jsonb_build_object('customer_id', (SELECT customer_id FROM fnd_customers WHERE tenant_id = t AND customer_number = '15702'), 'rows', '[{"cus_no":"15702"}]'::jsonb));
        d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('the picked customer must be an account', d);
  BEGIN PERFORM bps.om_order_import_upload(t, base || jsonb_build_object('rows', '[]'::jsonb)); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('an empty file is refused', d);
  INSERT INTO _t VALUES ('imports list shows the approved import', EXISTS (SELECT 1 FROM jsonb_array_elements(bps.om_order_imports_get(t, DATE '2033-03-01', DATE '2033-03-31')) x
     WHERE (x ->> 'order_import_id')::bigint = imp2));
END $$;

-- 7) a customer user cannot see imports
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', '006f6c23-5efa-4f31-b0f3-b36ad4d587e7',
  'claims', jsonb_build_object('role', 'authenticated', 'sub', '006f6c23-5efa-4f31-b0f3-b36ad4d587e7', 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE d boolean;
BEGIN
  INSERT INTO _t VALUES ('customer user sees no imports or import rows', (SELECT count(*) FROM om_order_imports) = 0 AND (SELECT count(*) FROM om_order_import_rows) = 0);
  BEGIN PERFORM bps.om_order_import_upload(200000000002, '{}'::jsonb); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('customer user cannot upload', d);
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % order-import tests failed', bad, total; END IF;
  RAISE NOTICE 'all % order-import tests passed', total;
END $$;
ROLLBACK;
