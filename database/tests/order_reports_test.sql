-- ============================================================
-- SQL tests for Phase 3 report data: customer pick lists, Baker's Report, labels, Packaging List (invoice numbering and
-- locking), Route Delivery Report and print stamps. One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/order_reports_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t TO PUBLIC;
GRANT ALL ON _id TO PUBLIC;

DO $$
DECLARE a bigint; d1 bigint; d2 bigint; s1 bigint;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, invoice_copy_count) VALUES (200000000002, 'RPT ACCOUNT', 'ACCOUNT', 2) RETURNING customer_id INTO a;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id, is_invoice_required) VALUES (200000000002, 'RPT DEPT INVOICED', 'DEPARTMENT', a, TRUE) RETURNING customer_id INTO d1;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id) VALUES (200000000002, 'RPT DEPT SHARED', 'DEPARTMENT', a) RETURNING customer_id INTO d2;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id) VALUES (200000000002, 'Rpt Site', 'SITE', d1) RETURNING customer_id INTO s1;
  INSERT INTO _id VALUES ('a', a), ('d1', d1), ('d2', d2), ('s1', s1);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('allowed_tenant_ids', json_build_array(200000000002), 'restricted_tenant_ids', json_build_array()))::text, true);

DO $$
DECLARE a bigint; d1 bigint; d2 bigint; s1 bigint; r jsonb; cat_name text;
BEGIN
  SELECT v INTO a FROM _id WHERE k='a'; SELECT v INTO d1 FROM _id WHERE k='d1'; SELECT v INTO d2 FROM _id WHERE k='d2'; SELECT v INTO s1 FROM _id WHERE k='s1';
  -- account: 2 lines (qty 2 + qty 1) + delivery 4; invoiced department; shared department; site under the invoiced department
  PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', a, 'production_date', '2032-03-10', 'production_code', 'MORNING', 'delivery_amount', 4,
     'lines', jsonb_build_array(jsonb_build_object('item_id', 200000001619, 'item_description','Roll','quantity',2,'unit_price',5,'prep_options', jsonb_build_array('Sliced')),
                                jsonb_build_object('item_id', 200000001619, 'item_description','Loaf','quantity',1,'unit_price',3))));
  PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', d1, 'production_date', '2032-03-10', 'production_code', 'MORNING',
     'lines', jsonb_build_array(jsonb_build_object('item_id', 200000001619, 'item_description','Bun','quantity',4,'unit_price',10))));
  PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', d2, 'production_date', '2032-03-10', 'production_code', 'MORNING',
     'lines', jsonb_build_array(jsonb_build_object('item_id', 200000001619, 'item_description','Bun','quantity',1,'unit_price',10))));
  PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', s1, 'production_date', '2032-03-10', 'production_code', 'MORNING',
     'lines', jsonb_build_array(jsonb_build_object('item_id', 200000001619, 'item_description','Bun','quantity',1,'unit_price',10))));

  -- before processing: order basis works, invoice basis is empty
  r := om_report_customers_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', 'MORNING', 'ORDER');
  INSERT INTO _t VALUES ('order basis lists the customers with orders (account, 2 departments; the site is under its department)',
      jsonb_array_length(r) = 3 AND EXISTS (SELECT 1 FROM jsonb_array_elements(r) e WHERE (e->>'customer_id')::bigint = d1 AND (e->>'document_count')::int = 2));
  INSERT INTO _t VALUES ('invoice basis is empty before the run is processed', jsonb_array_length(om_report_customers_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, 'INVOICE')) = 0);

  -- Baker's report
  r := om_report_bakers_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL);
  INSERT INTO _t VALUES ('bakers: one run with 4 orders and total quantity 9', jsonb_array_length(r->'runs') = 1 AND (r->'runs'->0->>'order_count')::int = 4 AND (r->'runs'->0->>'total_quantity')::numeric = 9);
  INSERT INTO _t VALUES ('bakers: category totals add up to the run total',
      (SELECT SUM((c->>'total_quantity')::numeric) FROM jsonb_array_elements(r->'runs'->0->'categories') c) = 9);
  INSERT INTO _t VALUES ('bakers: not flagged changed before any print', NOT (r->'runs'->0->>'changed_since_print')::boolean AND r->'runs'->0->>'last_printed_at' IS NULL);
  INSERT INTO _t VALUES ('bakers: empty range gives no runs', jsonb_array_length(om_report_bakers_get(200000000002, DATE '2032-04-01', DATE '2032-04-02', NULL)->'runs') = 0);

  -- labels
  r := om_report_labels_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', 'MORNING', ARRAY[a]);
  INSERT INTO _t VALUES ('labels: one per order line of the selected customer (2)', jsonb_array_length(r->'labels') = 2);
  INSERT INTO _t VALUES ('labels carry customer, event, order number and prep options',
      r->'labels'->0->>'customer_name' = 'RPT ACCOUNT' AND r->'labels'->0->>'department_event' = 'RPT ACCOUNT' AND r->'labels'->0->>'order_number' IS NOT NULL AND r->'labels'->0->>'prep_options' = 'Sliced');
  INSERT INTO _t VALUES ('labels: a site order appears under its parent customer with the site as event',
      EXISTS (SELECT 1 FROM jsonb_array_elements(om_report_labels_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, ARRAY[d1])->'labels') l WHERE l->>'department_event' = 'RPT SITE'));
  INSERT INTO _t VALUES ('labels: only selected customers (d2 only -> 1 label)', jsonb_array_length(om_report_labels_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, ARRAY[d2])->'labels') = 1);
END $$;

DO $$
DECLARE a bigint; d1 bigint; d2 bigint; r jsonb; r2 jsonb; d boolean; n1 text; n2 text; inv jsonb;
BEGIN
  SELECT v INTO a FROM _id WHERE k='a'; SELECT v INTO d1 FROM _id WHERE k='d1'; SELECT v INTO d2 FROM _id WHERE k='d2';
  BEGIN PERFORM om_report_packaging_issue(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, ARRAY[a]); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('packaging: raises when the run has not been processed', d);
  BEGIN PERFORM om_report_labels_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, ARRAY[]::bigint[]); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('labels: no customers selected raises', d);

  PERFORM om_production_runs_process(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL);
  r := om_report_customers_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, 'INVOICE');
  INSERT INTO _t VALUES ('invoice basis lists the 2 invoice owners after processing', jsonb_array_length(r) = 2);

  -- print only the invoiced department first: A stays DRAFT
  r := om_report_packaging_issue(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, ARRAY[d1]);
  inv := r->'invoices'->0;
  INSERT INTO _t VALUES ('packaging: department invoice numbered from the sequence and OPEN', (r->>'newly_numbered')::int = 1 AND inv->>'document_number' LIKE 'INV-%'
      AND (SELECT status FROM ar_transactions WHERE ar_transaction_id = (inv->>'ar_transaction_id')::bigint) = 'OPEN');
  INSERT INTO _t VALUES ('packaging: unselected owner stays DRAFT without a number',
      (SELECT status = 'DRAFT' AND document_number IS NULL FROM ar_transactions WHERE customer_id = a AND transaction_type = 'INV' AND production_run_id IS NOT NULL
         AND production_run_id = (SELECT production_run_id FROM om_production_runs WHERE tenant_id = 200000000002 AND production_date = DATE '2032-03-10')));
  INSERT INTO _t VALUES ('packaging: the department invoice groups its two orders (department and site) with totals 40 and 10',
      jsonb_array_length(inv->'orders') = 2 AND (inv->>'amount')::numeric = 50 AND (SELECT SUM((o->>'order_total')::numeric) FROM jsonb_array_elements(inv->'orders') o) = 50);
  n1 := inv->>'document_number';

  r := om_report_packaging_issue(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, ARRAY[a, d1]);
  INSERT INTO _t VALUES ('packaging: reprint keeps the locked number and numbers only the new one',
      (r->>'newly_numbered')::int = 1 AND jsonb_array_length(r->'invoices') = 2
      AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'invoices') i WHERE i->>'document_number' = n1));
  n2 := (SELECT i->>'document_number' FROM jsonb_array_elements(r->'invoices') i WHERE (i->>'customer_id')::bigint = a);
  INSERT INTO _t VALUES ('packaging: invoice numbers are unique and sequential', n1 <> n2 AND n2 LIKE 'INV-%');
  INSERT INTO _t VALUES ('packaging: the account invoice groups its 2 orders (account and shared department), amount 27, copies = 2',
      (SELECT jsonb_array_length(i->'orders') = 2 AND (i->>'copies')::int = 2 AND (i->>'amount')::numeric = 27 FROM jsonb_array_elements(r->'invoices') i WHERE (i->>'customer_id')::bigint = a));
  INSERT INTO _t VALUES ('packaging stamps the run', (SELECT packaging_printed_at IS NOT NULL FROM om_production_runs WHERE tenant_id = 200000000002 AND production_date = DATE '2032-03-10'));
  r2 := om_report_packaging_issue(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, ARRAY[a, d1]);
  INSERT INTO _t VALUES ('packaging: a second reprint numbers nothing', (r2->>'newly_numbered')::int = 0);
END $$;

DO $$
DECLARE r jsonb; d boolean; b jsonb; n int;
BEGIN
  -- delivery sheet: own-fleet stops with invoice numbers
  r := om_report_delivery_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL);
  INSERT INTO _t VALUES ('delivery: 3 stops (account, invoiced department, shared department)', jsonb_array_length(r->'stops') = 3);
  INSERT INTO _t VALUES ('delivery: stops show invoice numbers and items',
      EXISTS (SELECT 1 FROM jsonb_array_elements(r->'stops') s WHERE jsonb_array_length(s->'invoice_numbers') = 1 AND jsonb_array_length(s->'items') >= 1));
  -- a customer on a carrier is not on the driver's sheet
  UPDATE fnd_customers SET delivery_method_code = 'CARRIER' WHERE customer_name = 'RPT DEPT SHARED';
  PERFORM om_production_runs_process(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL);
  INSERT INTO _t VALUES ('delivery: a carrier shipment is left off the driver sheet', jsonb_array_length(om_report_delivery_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL)->'stops') = 2);

  -- print stamps and the changed-since-print flag
  n := om_production_runs_mark_printed(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, 'baker');
  INSERT INTO _t VALUES ('mark printed stamps only the chosen report', n = 1 AND (SELECT baker_sheet_printed_at IS NOT NULL AND labels_printed_at IS NULL AND delivery_printed_at IS NULL
        FROM om_production_runs WHERE tenant_id = 200000000002 AND production_date = DATE '2032-03-10'));
  b := om_report_bakers_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL);
  INSERT INTO _t VALUES ('bakers: not changed right after printing', NOT (b->'runs'->0->>'changed_since_print')::boolean);
  -- now() is the transaction start, so pretend the print happened a minute ago
  UPDATE om_production_runs SET baker_sheet_printed_at = now() - interval '1 minute' WHERE tenant_id = 200000000002 AND production_date = DATE '2032-03-10';
  UPDATE om_order_lines SET quantity = quantity + 1 WHERE order_id = (SELECT order_id FROM om_orders WHERE customer_name = 'RPT DEPT SHARED' LIMIT 1);
  b := om_report_bakers_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL);
  INSERT INTO _t VALUES ('bakers: an order line changed after the print is flagged', (b->'runs'->0->>'changed_since_print')::boolean);
  BEGIN PERFORM om_production_runs_mark_printed(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, 'BOGUS'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('mark printed rejects an unknown report', d);
END $$;

-- customer-restricted callers are refused
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('allowed_tenant_ids', json_build_array(200000000002), 'restricted_tenant_ids', json_build_array(200000000002),
                    'allowed_customer_ids', json_build_array(0)))::text, true);
DO $$
DECLARE d boolean;
BEGIN
  BEGIN PERFORM om_report_bakers_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot run the Baker''s Report', d);
  BEGIN PERFORM om_report_labels_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, ARRAY[1::bigint]); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot print labels', d);
  BEGIN PERFORM om_report_packaging_issue(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, ARRAY[1::bigint]); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot print invoices', d);
  BEGIN PERFORM om_report_delivery_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot run the delivery report', d);
  BEGIN PERFORM om_report_customers_get(200000000002, DATE '2032-03-10', DATE '2032-03-10', NULL, 'ORDER'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot list report customers', d);
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % order-report tests failed', bad, total; END IF;
  RAISE NOTICE 'all % order-report tests passed', total;
END $$;
ROLLBACK;
