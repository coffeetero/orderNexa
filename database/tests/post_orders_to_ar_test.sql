-- ============================================================
-- SQL tests for Post Orders to Production / Post Orders to AR: printing never numbers invoices (drafts print without a
-- number), Post Orders to AR numbers them and needs the standing orders posted first, STRICT turns later order changes
-- into debit/credit memos on the same invoice (never changing it), RELAXED changes the invoice, the reprint health check,
-- the accounting rules setting, staff only.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/post_orders_to_ar_test.sql
-- Assumes the Alpine Bakery seed (tenant 200000000002, staff user 200000174045, active items). 2031-06-02 is a Monday.
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t TO PUBLIC;
GRANT ALL ON _id TO PUBLIC;

DO $$
DECLARE a bigint; b bigint; d bigint;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (200000000002, 'ZZ AR ACCOUNT', 'ACCOUNT') RETURNING customer_id INTO a;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, is_standing_order) VALUES (200000000002, 'ZZ AR SO ACCOUNT', 'ACCOUNT', TRUE) RETURNING customer_id INTO b;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id, is_standing_order) VALUES (200000000002, 'Zz Ar Dept', 'DEPARTMENT', b, TRUE) RETURNING customer_id INTO d;
  INSERT INTO _id VALUES ('a', a), ('b', b), ('d', d);
  INSERT INTO _id SELECT 'i' || n, item_id FROM (SELECT item_id, row_number() OVER (ORDER BY item_id) AS n FROM fnd_items WHERE tenant_id = 200000000002 AND is_active) x WHERE n <= 4;
  INSERT INTO om_standing_orders (tenant_id, customer_id, production_dow, production_code, item_id, quantity)
  VALUES (200000000002, d, 'MON', 'MORNING', (SELECT v FROM _id WHERE k = 'i1'), 4);
  UPDATE fnd_tenants SET accounting_rules = 'STRICT' WHERE tenant_id = 200000000002;
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

DO $$
DECLARE r jsonb; a bigint; i1 bigint; i2 bigint; o bigint; inv bigint; raised text;
BEGIN
  SELECT v INTO a FROM _id WHERE k = 'a'; SELECT v INTO i1 FROM _id WHERE k = 'i1'; SELECT v INTO i2 FROM _id WHERE k = 'i2';
  r := om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', a, 'production_date', '2031-06-02', 'production_code', 'MORNING',
        'lines', jsonb_build_array(
          jsonb_build_object('item_id', i1, 'item_description', 'one', 'quantity', 10, 'unit_price', 2),
          jsonb_build_object('item_id', i2, 'item_description', 'two', 'quantity', 5, 'unit_price', 3))));
  o := (r->>'order_id')::bigint;
  INSERT INTO _id VALUES ('o', o);

  -- Post to production: a DRAFT invoice with no number
  PERFORM om_production_runs_process(200000000002, '2031-06-02', '2031-06-02', 'MORNING');
  SELECT ar_transaction_id INTO inv FROM ar_transactions WHERE customer_id = a AND transaction_type = 'INV';
  INSERT INTO _id VALUES ('inv', inv);
  INSERT INTO _t VALUES ('post to production: DRAFT invoice, no number, amount 35',
    (SELECT status = 'DRAFT' AND document_number IS NULL AND amount = 35 FROM ar_transactions WHERE ar_transaction_id = inv));

  -- Packaging List and Print Invoices print the draft without numbering it
  r := om_report_packaging_issue(200000000002, '2031-06-02', '2031-06-02', 'MORNING', ARRAY[a]);
  INSERT INTO _t VALUES ('packaging list prints the draft and does not number it',
    jsonb_array_length(r->'invoices') = 1 AND r->'invoices'->0->>'document_number' IS NULL
    AND (SELECT status = 'DRAFT' AND document_number IS NULL AND printed_at IS NOT NULL FROM ar_transactions WHERE ar_transaction_id = inv));
  r := ar_invoices_print_get(200000000002, '2031-06-02', '2031-06-02', 'MORNING', ARRAY[a]);
  INSERT INTO _t VALUES ('print invoices includes the draft (no number)',
    jsonb_array_length(r->'invoices') = 1 AND r->'invoices'->0->>'status' = 'DRAFT' AND r->'invoices'->0->>'document_number' IS NULL);

  -- Post to AR is refused while the standing orders for the date are not posted
  BEGIN
    PERFORM om_invoices_post_to_ar(200000000002, '2031-06-02', '2031-06-02', 'MORNING', ARRAY[a, (SELECT v FROM _id WHERE k = 'b')]);
    raised := NULL;
  EXCEPTION WHEN OTHERS THEN raised := SQLERRM;
  END;
  INSERT INTO _t VALUES ('post to AR refused until standing orders are posted', raised LIKE 'Post standing orders first%');

  PERFORM om_standing_orders_post(200000000002, '2031-06-02', '2031-06-02', ARRAY['MORNING'], ARRAY[(SELECT v FROM _id WHERE k = 'd')]);
  r := om_invoices_post_to_ar(200000000002, '2031-06-02', '2031-06-02', 'MORNING', ARRAY[a, (SELECT v FROM _id WHERE k = 'b')]);
  INSERT INTO _t VALUES ('post to AR numbers the drafts (the account and the standing order customer)',
    (r->>'numbered')::int = 2
    AND (SELECT status = 'OPEN' AND document_number IS NOT NULL FROM ar_transactions WHERE ar_transaction_id = inv));
  r := om_invoices_post_to_ar(200000000002, '2031-06-02', '2031-06-02', 'MORNING', ARRAY[a, (SELECT v FROM _id WHERE k = 'b')]);
  INSERT INTO _t VALUES ('post to AR again: nothing left to number', (r->>'numbered')::int = 0);
END $$;

-- STRICT: 10 -> 25 (typo), 5 -> 3, a new item, then a whole new order
DO $$
DECLARE r jsonb; a bigint; i1 bigint; i2 bigint; i3 bigint; o bigint; inv bigint; lines jsonb; num text;
BEGIN
  SELECT v INTO a FROM _id WHERE k = 'a'; SELECT v INTO o FROM _id WHERE k = 'o'; SELECT v INTO inv FROM _id WHERE k = 'inv';
  SELECT v INTO i1 FROM _id WHERE k = 'i1'; SELECT v INTO i2 FROM _id WHERE k = 'i2'; SELECT v INTO i3 FROM _id WHERE k = 'i3';
  SELECT document_number INTO num FROM ar_transactions WHERE ar_transaction_id = inv;
  SELECT jsonb_agg(jsonb_build_object('order_line_id', order_line_id, 'item_id', item_id, 'item_description', item_description,
           'quantity', CASE WHEN item_id = i1 THEN 25 ELSE 3 END, 'unit_price', unit_price)) INTO lines
    FROM om_order_lines WHERE order_id = o;
  lines := lines || jsonb_build_array(jsonb_build_object('item_id', i3, 'item_description', 'three', 'quantity', 2, 'unit_price', 4));
  PERFORM om_orders_save(200000000002, NULL, o, jsonb_build_object('customer_id', a, 'production_date', '2031-06-02', 'production_code', 'MORNING', 'lines', lines));
  r := om_production_runs_process(200000000002, '2031-06-02', '2031-06-02', 'MORNING');
  INSERT INTO _t VALUES ('STRICT: the invoice is not changed (number, amount, lines)',
    (SELECT document_number = num AND amount = 35 FROM ar_transactions WHERE ar_transaction_id = inv)
    AND (SELECT count(*) FROM ar_transaction_lines WHERE ar_transaction_id = inv) = 2);
  INSERT INTO _t VALUES ('STRICT: a debit memo for +15 of item 1 and the new item (30 + 8)',
    (SELECT amount FROM ar_transactions WHERE applies_to_ar_transaction_id = inv AND transaction_type = 'DM') = 38
    AND (SELECT count(*) FROM ar_transaction_lines l JOIN ar_transactions m ON m.ar_transaction_id = l.ar_transaction_id
          WHERE m.applies_to_ar_transaction_id = inv AND m.transaction_type = 'DM') = 2
    AND (SELECT document_number LIKE 'DM-%' FROM ar_transactions WHERE applies_to_ar_transaction_id = inv AND transaction_type = 'DM'));
  INSERT INTO _t VALUES ('STRICT: a credit memo for -2 of item 2 (-6)',
    (SELECT amount FROM ar_transactions WHERE applies_to_ar_transaction_id = inv AND transaction_type = 'CM') = -6
    AND (SELECT l.quantity FROM ar_transaction_lines l JOIN ar_transactions m ON m.ar_transaction_id = l.ar_transaction_id
          WHERE m.applies_to_ar_transaction_id = inv AND m.transaction_type = 'CM') = 2);
  INSERT INTO _t VALUES ('STRICT: the run reports the memos', (r->0->>'memos')::int = 2);
  r := ar_invoices_print_get(200000000002, '2031-06-02', '2031-06-02', 'MORNING', ARRAY[a]);
  INSERT INTO _t VALUES ('print: the invoice shows its memos and the full total (35 + 38 - 6 = 67)',
    jsonb_array_length(r->'invoices'->0->'memos') = 2 AND (r->'invoices'->0->>'total_with_memos')::numeric = 67);

  r := om_production_runs_process(200000000002, '2031-06-02', '2031-06-02', 'MORNING');
  INSERT INTO _t VALUES ('STRICT: posting to production again with no change adds no memo',
    (r->0->>'memos')::int = 0 AND (SELECT count(*) FROM ar_transactions WHERE applies_to_ar_transaction_id = inv) = 2);

  -- a late, whole new order for the same customer and run
  PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', a, 'production_date', '2031-06-02', 'production_code', 'MORNING',
        'department_event', 'LATE PARTY', 'lines', jsonb_build_array(jsonb_build_object('item_id', i1, 'item_description', 'one', 'quantity', 100, 'unit_price', 2))));
  r := om_production_runs_process(200000000002, '2031-06-02', '2031-06-02', 'MORNING');
  INSERT INTO _t VALUES ('STRICT: a late order becomes a debit memo on the same invoice (no second invoice)',
    (SELECT count(*) FROM ar_transactions WHERE customer_id = a AND transaction_type = 'INV' AND status <> 'CANCELLED') = 1
    AND (SELECT SUM(amount) FROM ar_transactions WHERE applies_to_ar_transaction_id = inv AND transaction_type = 'DM') = 238);
END $$;

-- Health check: memos made after the last print
RESET ROLE;
UPDATE ar_transactions SET printed_at = now() - interval '1 hour' WHERE ar_transaction_id = (SELECT v FROM _id WHERE k = 'inv');
SET LOCAL ROLE authenticated;
DO $$
DECLARE inv bigint;
BEGIN
  SELECT v INTO inv FROM _id WHERE k = 'inv';
  INSERT INTO _t VALUES ('health check: invoice changed after printing is reported',
    EXISTS (SELECT 1 FROM fnd_hc_invoices_need_reprint(200000000002) WHERE record_id = inv));
  PERFORM ar_invoices_mark_printed(200000000002, ARRAY[inv]);
END $$;
RESET ROLE;
UPDATE ar_transactions SET created_at = now() - interval '2 hours' WHERE applies_to_ar_transaction_id = (SELECT v FROM _id WHERE k = 'inv');
SET LOCAL ROLE authenticated;
DO $$
DECLARE inv bigint;
BEGIN
  SELECT v INTO inv FROM _id WHERE k = 'inv';
  INSERT INTO _t VALUES ('health check: clear once printed again',
    NOT EXISTS (SELECT 1 FROM fnd_hc_invoices_need_reprint(200000000002) WHERE record_id = inv));
END $$;

-- RELAXED: the invoice itself changes (same number), no new memo
DO $$
DECLARE r jsonb; a bigint; o bigint; inv bigint; i1 bigint; lines jsonb; num text; n int;
BEGIN
  SELECT v INTO a FROM _id WHERE k = 'a'; SELECT v INTO o FROM _id WHERE k = 'o'; SELECT v INTO inv FROM _id WHERE k = 'inv'; SELECT v INTO i1 FROM _id WHERE k = 'i1';
  r := fnd_accounting_settings_save(200000000002, '{"accounting_rules":"relaxed"}');
  INSERT INTO _t VALUES ('setting saved', r->>'accounting_rules' = 'RELAXED' AND fnd_accounting_settings_get(200000000002)->>'accounting_rules' = 'RELAXED');
  SELECT document_number INTO num FROM ar_transactions WHERE ar_transaction_id = inv;
  SELECT count(*) INTO n FROM ar_transactions WHERE applies_to_ar_transaction_id = inv;
  SELECT jsonb_agg(jsonb_build_object('order_line_id', order_line_id, 'item_id', item_id, 'item_description', item_description,
           'quantity', CASE WHEN item_id = i1 THEN 30 ELSE quantity END, 'unit_price', unit_price)) INTO lines
    FROM om_order_lines WHERE order_id = o;
  PERFORM om_orders_save(200000000002, NULL, o, jsonb_build_object('customer_id', a, 'production_date', '2031-06-02', 'production_code', 'MORNING', 'lines', lines));
  PERFORM om_production_runs_process(200000000002, '2031-06-02', '2031-06-02', 'MORNING');
  INSERT INTO _t VALUES ('RELAXED: same number, invoice rebuilt from the orders (60 + 9 + 8 + 200 = 277), no new memo',
    (SELECT document_number = num AND status = 'OPEN' AND amount = 277 FROM ar_transactions WHERE ar_transaction_id = inv)
    AND (SELECT count(*) FROM ar_transactions WHERE applies_to_ar_transaction_id = inv) = n);
  BEGIN
    PERFORM fnd_accounting_settings_save(200000000002, '{"accounting_rules":"loose"}');
    INSERT INTO _t VALUES ('setting: invalid value refused', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _t VALUES ('setting: invalid value refused', SQLERRM LIKE 'Accounting rules must be%');
  END;
END $$;

-- A customer-side user cannot post to AR
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002),
                    'restricted_tenant_ids', json_build_array(200000000002)))::text, true);
DO $$
BEGIN
  PERFORM om_invoices_post_to_ar(200000000002, '2031-06-02', '2031-06-02');
  INSERT INTO _t VALUES ('customer users cannot post to AR', FALSE);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO _t VALUES ('customer users cannot post to AR', SQLERRM LIKE 'Only tenant staff%');
END $$;

RESET ROLE;
SELECT CASE WHEN COALESCE(ok, false) THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT COALESCE(ok, false)), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % post-to-AR tests failed', bad, total; END IF;
  RAISE NOTICE 'all % post-to-AR tests passed', total;
END $$;
ROLLBACK;
