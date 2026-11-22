-- ============================================================
-- SQL tests for Phase 4: delivery confirmation, shipped quantities, AR recognition, credit memos, customer balance and the
-- invoice/order lookup. One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/order_delivery_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t TO PUBLIC;
GRANT ALL ON _id TO PUBLIC;

DO $$
DECLARE a bigint; b bigint;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (200000000002, 'DLV ACCOUNT A', 'ACCOUNT') RETURNING customer_id INTO a;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, delivery_method_code) VALUES (200000000002, 'DLV ACCOUNT B', 'ACCOUNT', 'CARRIER') RETURNING customer_id INTO b;
  INSERT INTO _id VALUES ('a', a), ('b', b);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('allowed_tenant_ids', json_build_array(200000000002), 'restricted_tenant_ids', json_build_array()))::text, true);

DO $$
DECLARE a bigint; b bigint; r jsonb; o1 text; sa jsonb; sb jsonb; la bigint; lb bigint;
BEGIN
  SELECT v INTO a FROM _id WHERE k='a'; SELECT v INTO b FROM _id WHERE k='b';
  r := om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', a, 'production_date', '2033-02-10', 'production_code', 'MORNING', 'delivery_amount', 6,
       'lines', jsonb_build_array(jsonb_build_object('item_id', 200000001619, 'item_description','Roll','quantity',10,'unit_price',2),
                                  jsonb_build_object('item_id', 200000001619, 'item_description','Loaf','quantity',5,'unit_price',4))));
  INSERT INTO _id VALUES ('o1', (r->>'order_id')::bigint);
  PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', b, 'production_date', '2033-02-10', 'production_code', 'MORNING',
       'lines', jsonb_build_array(jsonb_build_object('item_id', 200000001619, 'item_description','Frozen bun','quantity',3,'unit_price',10))));
  PERFORM om_production_runs_process(200000000002, DATE '2033-02-10', DATE '2033-02-10', NULL);
  PERFORM om_report_packaging_issue(200000000002, DATE '2033-02-10', DATE '2033-02-10', NULL, ARRAY[a, b]);

  r := om_shipments_get(200000000002, DATE '2033-02-10', DATE '2033-02-10', 'MORNING', NULL);
  INSERT INTO _t VALUES ('shipments_get lists 2 PLANNED shipments with lines and invoice numbers',
      jsonb_array_length(r) = 2 AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r) s WHERE s->>'shipment_status' <> 'PLANNED' OR jsonb_array_length(s->'invoice_numbers') <> 1));
  INSERT INTO _t VALUES ('shipments_get filters by status', jsonb_array_length(om_shipments_get(200000000002, DATE '2033-02-10', DATE '2033-02-10', NULL, 'SHIPPED')) = 0);
  SELECT s INTO sa FROM jsonb_array_elements(r) s WHERE s->>'customer_name' = 'DLV ACCOUNT A';
  SELECT s INTO sb FROM jsonb_array_elements(r) s WHERE s->>'customer_name' = 'DLV ACCOUNT B';
  INSERT INTO _id VALUES ('ship_a', (sa->>'shipment_id')::bigint), ('ship_b', (sb->>'shipment_id')::bigint);
  INSERT INTO _id SELECT 'inv_a', ar_transaction_id FROM ar_transactions WHERE customer_id = a AND transaction_type = 'INV';
  INSERT INTO _id SELECT 'inv_b', ar_transaction_id FROM ar_transactions WHERE customer_id = b AND transaction_type = 'INV';

  INSERT INTO _t VALUES ('before shipping nothing is receivable', ar_invoice_recognized_amount((SELECT v FROM _id WHERE k='inv_a')) = 0
      AND (ar_customer_balance_get(200000000002, a)->>'balance')::numeric = 0);
  INSERT INTO _t VALUES ('the carrier customer got a CARRIER shipment that requires tracking', sb->>'delivery_method_code' = 'CARRIER' AND (sb->>'requires_tracking')::boolean);
END $$;

-- ── confirm: validation ──────────────────────────────────────────────────────
DO $$
DECLARE d boolean; v_ship bigint; v_other bigint; v_line bigint; v_otherline bigint;
BEGIN
  SELECT v INTO v_ship FROM _id WHERE k='ship_a'; SELECT v INTO v_other FROM _id WHERE k='ship_b';
  SELECT shipment_line_id INTO v_line FROM om_shipment_lines sl JOIN om_order_lines ol USING (order_line_id) WHERE sl.shipment_id = v_ship AND ol.item_description = 'Roll';
  SELECT shipment_line_id INTO v_otherline FROM om_shipment_lines WHERE shipment_id = v_other LIMIT 1;
  BEGIN PERFORM om_shipment_confirm(200000000002, v_ship, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('shipment_line_id', v_line, 'shipped_quantity', 11)))); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('cannot ship more than planned', d);
  BEGIN PERFORM om_shipment_confirm(200000000002, v_ship, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('shipment_line_id', v_line, 'shipped_quantity', -1)))); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('cannot ship a negative quantity', d);
  BEGIN PERFORM om_shipment_confirm(200000000002, v_ship, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('shipment_line_id', v_otherline, 'shipped_quantity', 1)))); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a line from another shipment is rejected', d);
  BEGIN PERFORM om_shipment_confirm(200000000002, v_ship, '{"shipment_status":"PLANNED"}'::jsonb); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('status must be SHIPPED or DELIVERED', d);
  BEGIN PERFORM om_shipment_confirm(200000000002, v_other, '{"shipment_status":"SHIPPED"}'::jsonb); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a carrier shipment needs a tracking reference', d);
  INSERT INTO _t VALUES ('a failed confirmation changes nothing', (SELECT shipment_status = 'PLANNED' FROM om_shipments WHERE shipment_id = v_ship)
      AND (SELECT shipped_quantity IS NULL FROM om_shipment_lines WHERE shipment_line_id = v_line));
  BEGIN PERFORM om_shipment_confirm(200000000002, v_other, '{"shipment_status":"SHIPPED","delivery_method_code":"NOPE","tracking_reference":"x"}'::jsonb); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('an unknown delivery method is rejected', d);
END $$;

-- ── confirm: short shipment on the truck, carrier shipment with tracking and cost ──
DO $$
DECLARE v_ship bigint; v_other bigint; v_line bigint; r jsonb; ia bigint; ib bigint; a bigint; b bigint; o1 bigint;
BEGIN
  SELECT v INTO v_ship FROM _id WHERE k='ship_a'; SELECT v INTO v_other FROM _id WHERE k='ship_b';
  SELECT v INTO ia FROM _id WHERE k='inv_a'; SELECT v INTO ib FROM _id WHERE k='inv_b'; SELECT v INTO a FROM _id WHERE k='a'; SELECT v INTO b FROM _id WHERE k='b'; SELECT v INTO o1 FROM _id WHERE k='o1';
  SELECT shipment_line_id INTO v_line FROM om_shipment_lines sl JOIN om_order_lines ol USING (order_line_id) WHERE sl.shipment_id = v_ship AND ol.item_description = 'Roll';

  r := om_shipment_confirm(200000000002, v_ship, jsonb_build_object('shipment_status', 'SHIPPED', 'route', 'A1',
        'lines', jsonb_build_array(jsonb_build_object('shipment_line_id', v_line, 'shipped_quantity', 8))));
  INSERT INTO _t VALUES ('confirm: shipped and the 2 missing rolls are reported as a shortage',
      r->>'shipment_status' = 'SHIPPED' AND jsonb_array_length(r->'shortages') = 1 AND (r->'shortages'->0->>'short')::numeric = 2 AND r->'shortages'->0->>'item_name' = 'Roll');
  INSERT INTO _t VALUES ('confirm: unmentioned lines default to the planned quantity',
      (SELECT shipped_quantity = 5 FROM om_shipment_lines sl JOIN om_order_lines ol USING (order_line_id) WHERE sl.shipment_id = v_ship AND ol.item_description = 'Loaf'));
  INSERT INTO _t VALUES ('confirm: shipped_at and route are recorded', (SELECT shipped_at IS NOT NULL AND route = 'A1' FROM om_shipments WHERE shipment_id = v_ship));
  INSERT INTO _t VALUES ('confirm: order line fulfilled_quantity follows what shipped',
      (SELECT fulfilled_quantity = 8 FROM om_order_lines WHERE order_id = o1 AND item_description = 'Roll')
      AND (SELECT fulfilled_quantity = 5 FROM om_order_lines WHERE order_id = o1 AND item_description = 'Loaf'));
  INSERT INTO _t VALUES ('recognized = shipped x price (8x2 + 5x4) + the order delivery charge 6 = 42', ar_invoice_recognized_amount(ia) = 42);
  INSERT INTO _t VALUES ('the unshipped carrier invoice still recognises nothing', ar_invoice_recognized_amount(ib) = 0);
  INSERT INTO _t VALUES ('balance of customer A is 42 (invoice printed total stays 46)', (ar_customer_balance_get(200000000002, a)->>'balance')::numeric = 42
      AND (SELECT amount FROM ar_transactions WHERE ar_transaction_id = ia) = 46);

  r := om_shipment_confirm(200000000002, v_other, '{"shipment_status":"DELIVERED","tracking_reference":"1Z999","carrier":"UPS","delivery_cost":12.5}'::jsonb);
  INSERT INTO _t VALUES ('carrier shipment: tracking, carrier and cost stored, DELIVERED',
      (SELECT shipment_status = 'DELIVERED' AND tracking_reference = '1Z999' AND carrier = 'UPS' AND delivery_cost = 12.5 FROM om_shipments WHERE shipment_id = v_other));
  INSERT INTO _t VALUES ('carrier invoice is now receivable (3 x 10 = 30)', ar_invoice_recognized_amount(ib) = 30 AND (ar_customer_balance_get(200000000002, b)->>'balance')::numeric = 30);
  -- repeat to move SHIPPED -> DELIVERED keeps the original ship time
  PERFORM pg_sleep(0.01);
  PERFORM om_shipment_confirm(200000000002, v_ship, '{"shipment_status":"DELIVERED"}'::jsonb);
  INSERT INTO _t VALUES ('SHIPPED can be moved to DELIVERED without changing the shipped quantities',
      (SELECT shipment_status = 'DELIVERED' FROM om_shipments WHERE shipment_id = v_ship) AND ar_invoice_recognized_amount(ia) = 42);
END $$;

DO $$
DECLARE d boolean; v_ship bigint;
BEGIN
  SELECT v INTO v_ship FROM _id WHERE k='ship_a';
  BEGIN PERFORM om_production_runs_process(200000000002, DATE '2033-02-10', DATE '2033-02-10', NULL); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('processing the run again is refused once deliveries shipped', d);
END $$;

-- ── credit memos, balance, lookup ────────────────────────────────────────────
DO $$
DECLARE ia bigint; a bigint; roll bigint; loaf bigint; r jsonb; d boolean; cm bigint; pay bigint; lk jsonb; num text; o1num text;
BEGIN
  SELECT v INTO ia FROM _id WHERE k='inv_a'; SELECT v INTO a FROM _id WHERE k='a';
  SELECT ar_transaction_line_id INTO roll FROM ar_transaction_lines WHERE ar_transaction_id = ia AND item_description = 'Roll';
  SELECT ar_transaction_line_id INTO loaf FROM ar_transaction_lines WHERE ar_transaction_id = ia AND item_description = 'Loaf';

  r := ar_credit_memo_create(200000000002, ia, jsonb_build_object('reason', 'Kitchen short 3 rolls', 'lines', jsonb_build_array(jsonb_build_object('ar_transaction_line_id', roll, 'quantity', 3))));
  cm := (r->>'ar_transaction_id')::bigint;
  INSERT INTO _t VALUES ('credit memo: numbered CM-, negative amount, linked to the invoice',
      r->>'document_number' LIKE 'CM-%' AND (r->>'amount')::numeric = -6
      AND (SELECT transaction_type = 'CM' AND status = 'OPEN' AND applies_to_ar_transaction_id = ia AND customer_id = a FROM ar_transactions WHERE ar_transaction_id = cm));
  INSERT INTO _t VALUES ('credit memo line is an ADJUSTMENT at the invoice unit price',
      (SELECT source_type = 'ADJUSTMENT' AND quantity = 3 AND unit_price = 2 AND amount = -6 AND snapshot_data ->> 'reason' = 'Kitchen short 3 rolls' FROM ar_transaction_lines WHERE ar_transaction_id = cm));
  INSERT INTO _t VALUES ('balance drops by the credit (42 - 6 = 36)', (ar_customer_balance_get(200000000002, a)->>'balance')::numeric = 36
      AND (ar_customer_balance_get(200000000002, a)->>'credits')::numeric = -6);
  BEGIN PERFORM ar_credit_memo_create(200000000002, ia, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('ar_transaction_line_id', roll, 'quantity', 6)))); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('cannot credit more than was delivered less earlier credits (8 shipped, 3 credited, 6 asked)', d);
  r := ar_credit_memo_create(200000000002, ia, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('ar_transaction_line_id', roll, 'quantity', 5))));
  INSERT INTO _t VALUES ('the remaining 5 can be credited', (r->>'amount')::numeric = -10 AND r->>'document_number' <> (SELECT document_number FROM ar_transactions WHERE ar_transaction_id = cm));
  BEGIN PERFORM ar_credit_memo_create(200000000002, ia, '{"lines":[]}'::jsonb); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a credit memo needs at least one line', d);
  BEGIN PERFORM ar_credit_memo_create(200000000002, ia, jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('ar_transaction_line_id', roll, 'quantity', 0)))); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('credit quantity must be above zero', d);

  -- payments reduce the balance
  INSERT INTO ar_payments (tenant_id, customer_id, payment_date, amount) VALUES (200000000002, a, CURRENT_DATE, 10) RETURNING ar_payment_id INTO pay;
  INSERT INTO ar_payment_applications (tenant_id, ar_payment_id, ar_transaction_id, applied_amount) VALUES (200000000002, pay, ia, 10);
  INSERT INTO _t VALUES ('payments applied reduce the balance (42 - 6 - 10 - 10 = 16)', (ar_customer_balance_get(200000000002, a)->>'balance')::numeric = 16
      AND (ar_customer_balance_get(200000000002, a)->>'payments_applied')::numeric = 10);

  -- lookup by invoice number and by order number
  SELECT document_number INTO num FROM ar_transactions WHERE ar_transaction_id = ia;
  lk := ar_document_lookup(200000000002, lower(num));
  INSERT INTO _t VALUES ('lookup by invoice number (case-insensitive) returns the invoice with lines and credits',
      jsonb_array_length(lk->'invoices') = 1 AND jsonb_array_length(lk->'invoices'->0->'lines') = 3 AND jsonb_array_length(lk->'invoices'->0->'credits') = 2
      AND (lk->'invoices'->0->>'credited_amount')::numeric = 16 AND (lk->'invoices'->0->>'recognized_amount')::numeric = 42);
  INSERT INTO _t VALUES ('lookup shows shipped and credited quantities per line',
      EXISTS (SELECT 1 FROM jsonb_array_elements(lk->'invoices'->0->'lines') l WHERE l->>'item_description' = 'Roll' AND (l->>'shipped_quantity')::numeric = 8 AND (l->>'credited_quantity')::numeric = 8));
  SELECT order_number INTO o1num FROM om_orders WHERE order_id = (SELECT v FROM _id WHERE k='o1');
  lk := ar_document_lookup(200000000002, o1num);
  INSERT INTO _t VALUES ('lookup by order number finds the invoice that carries it', jsonb_array_length(lk->'invoices') = 1 AND lk->'invoices'->0->>'document_number' = num);
  INSERT INTO _t VALUES ('lookup of an unknown number returns nothing', jsonb_array_length(ar_document_lookup(200000000002, 'NO-SUCH')->'invoices') = 0);
  BEGIN PERFORM ar_document_lookup(200000000002, '  '); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('an empty lookup is rejected', d);
END $$;

-- ── customer-restricted callers are refused ─────────────────────────────────
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('allowed_tenant_ids', json_build_array(200000000002), 'restricted_tenant_ids', json_build_array(200000000002),
                    'allowed_customer_ids', json_build_array(0)))::text, true);
DO $$
DECLARE d boolean;
BEGIN
  BEGIN PERFORM om_shipments_get(200000000002, DATE '2033-02-10', DATE '2033-02-10', NULL, NULL); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot list shipments', d);
  BEGIN PERFORM om_shipment_confirm(200000000002, 1, '{"shipment_status":"SHIPPED"}'::jsonb); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot confirm shipments', d);
  BEGIN PERFORM ar_credit_memo_create(200000000002, 1, '{"lines":[{"ar_transaction_line_id":1,"quantity":1}]}'::jsonb); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot create credit memos', d);
  BEGIN PERFORM ar_document_lookup(200000000002, 'INV-1'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot use the document lookup', d);
  BEGIN PERFORM ar_customer_balance_get(200000000002, 1); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot read balances through the staff function', d);
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % order-delivery tests failed', bad, total; END IF;
  RAISE NOTICE 'all % order-delivery tests passed', total;
END $$;
ROLLBACK;
