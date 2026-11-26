-- ============================================================
-- SQL tests for om_order_invoice_get, the invoice fields om_orders_get_v2 returns to Order Entry, ar_credit_orders_get and ar_credit_find (Enter Credits).
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/order_invoice_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
GRANT ALL ON _t TO PUBLIC;

DO $$
DECLARE c bigint; o1 bigint; o2 bigint; o3 bigint; inv bigint; dr bigint; cx bigint; r jsonb; lst jsonb;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_number) VALUES (200000000002, 'INV TEST ACCOUNT', 'ACCOUNT', 'ZZ901') RETURNING customer_id INTO c;
  INSERT INTO om_orders (tenant_id, customer_id, customer_name, order_number, department_event, po_number, quantity, amount, discount_amount, production_date, production_code)
    VALUES (200000000002, c, 'INV TEST ACCOUNT', 'ZZ-1', 'A', 'PO-77', 1, 10, 0, '2032-04-01', 'MORNING') RETURNING order_id INTO o1;
  INSERT INTO om_orders (tenant_id, customer_id, customer_name, order_number, department_event, quantity, amount, discount_amount, production_date, production_code)
    VALUES (200000000002, c, 'INV TEST ACCOUNT', 'ZZ-2', 'B', 1, 10, 0, '2032-04-01', 'MORNING') RETURNING order_id INTO o2;
  INSERT INTO om_orders (tenant_id, customer_id, customer_name, order_number, department_event, quantity, amount, discount_amount, production_date, production_code)
    VALUES (200000000002, c, 'INV TEST ACCOUNT', 'ZZ-3', 'C', 1, 10, 0, '2032-04-01', 'MORNING') RETURNING order_id INTO o3;
  -- o1: a cancelled invoice and an issued one; o2: a draft; o3: nothing
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status)
    VALUES (200000000002, c, 'INV', 'ZZINV-OLD', '2032-04-01', 10, 'CANCELLED') RETURNING ar_transaction_id INTO cx;
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status)
    VALUES (200000000002, c, 'INV', 'ZZINV-1', '2032-04-01', 10, 'OPEN') RETURNING ar_transaction_id INTO inv;
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status)
    VALUES (200000000002, c, 'INV', 'ZZDRAFT', '2032-04-01', 10, 'DRAFT') RETURNING ar_transaction_id INTO dr;
  INSERT INTO ar_transaction_lines (tenant_id, ar_transaction_id, line_number, order_id, item_description, quantity, unit_price, amount) VALUES
    (200000000002, cx, 1, o1, 'Roll', 20, 0.5, 10), (200000000002, inv, 1, o1, 'Roll', 20, 0.5, 10), (200000000002, dr, 1, o2, 'Roll', 20, 0.5, 10);
  -- an earlier credit memo for 4 rolls on the issued invoice
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status, applies_to_ar_transaction_id)
    VALUES (200000000002, c, 'CM', 'ZZCM-1', '2032-04-02', -2, 'OPEN', inv) RETURNING ar_transaction_id INTO cx;
  INSERT INTO ar_transaction_lines (tenant_id, ar_transaction_id, line_number, item_description, quantity, unit_price, amount, snapshot_data)
    SELECT 200000000002, cx, 1, 'Roll', 4, 0.5, -2, jsonb_build_object('credits_line_id', ar_transaction_line_id)
      FROM ar_transaction_lines WHERE ar_transaction_id = inv;
  PERFORM set_config('t.cust', c::text, false);

  r := om_order_invoice_get(200000000002, o1);
  INSERT INTO _t VALUES ('issued invoice wins over a cancelled one', r->>'invoice_number' = 'ZZINV-1' AND r->>'invoice_status' = 'ISSUED');
  r := om_order_invoice_get(200000000002, o2);
  INSERT INTO _t VALUES ('draft has no number yet', r->>'invoice_number' IS NULL AND r->>'invoice_status' = 'DRAFT');
  r := om_order_invoice_get(200000000002, o3);
  INSERT INTO _t VALUES ('order not on an invoice', r->>'invoice_number' IS NULL AND r->>'invoice_status' = 'NONE');
  r := om_order_invoice_get(200000000003, o1);
  INSERT INTO _t VALUES ('other tenant sees nothing', r->>'invoice_status' = 'NONE');

  lst := om_orders_get_v2(200000000002, NULL, c, '2032-04-01', '2032-04-01');
  INSERT INTO _t VALUES ('list carries invoice, PO and customer number',
    EXISTS (SELECT 1 FROM jsonb_array_elements(lst) e WHERE e->>'order_number' = 'ZZ-1' AND e->>'invoice_number' = 'ZZINV-1'
            AND e->>'po_number' = 'PO-77' AND e->>'customer_number' = 'ZZ901'));
  r := om_orders_get_v2(200000000002, o2);
  INSERT INTO _t VALUES ('detail carries invoice status', r->>'invoice_status' = 'DRAFT');
END $$;

-- Enter Credits list, as tenant staff
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);
DO $$
DECLARE r jsonb; o jsonb;
BEGIN
  r := ar_credit_orders_get(200000000002, current_setting('t.cust')::bigint, '2032-04-01', 'morning');
  INSERT INTO _t VALUES ('credits: all three orders of the slot', jsonb_array_length(r->'orders') = 3);
  SELECT e INTO o FROM jsonb_array_elements(r->'orders') e WHERE e->>'order_number' = 'ZZ-1';
  INSERT INTO _t VALUES ('credits: issued order has its line with earlier credits counted',
    o->>'status' = 'OPEN' AND o->>'invoice_number' = 'ZZINV-1' AND (o->>'credited_amount')::numeric = 2
    AND jsonb_array_length(o->'lines') = 1 AND (o->'lines'->0->>'credited_quantity')::numeric = 4 AND (o->'lines'->0->>'remaining_quantity')::numeric = 16);
  SELECT e INTO o FROM jsonb_array_elements(r->'orders') e WHERE e->>'order_number' = 'ZZ-2';
  INSERT INTO _t VALUES ('credits: draft order has no lines to credit', o->>'status' = 'DRAFT' AND jsonb_array_length(o->'lines') = 0);
  SELECT e INTO o FROM jsonb_array_elements(r->'orders') e WHERE e->>'order_number' = 'ZZ-3';
  INSERT INTO _t VALUES ('credits: order not on an invoice', o->>'status' = 'NONE');
  r := ar_credit_find(200000000002, 'order', 'zz-1');
  INSERT INTO _t VALUES ('find: by order number opens its account and slot',
    jsonb_array_length(r->'matches') = 1 AND (r->'matches'->0->>'account_id')::bigint = current_setting('t.cust')::bigint
    AND r->'matches'->0->>'production_date' = '2032-04-01' AND r->'matches'->0->>'production_code' = 'MORNING');
  r := ar_credit_find(200000000002, 'INVOICE', ' ZZINV-1 ');
  INSERT INTO _t VALUES ('find: by invoice number gives its orders', jsonb_array_length(r->'matches') = 1 AND r->'matches'->0->>'order_number' = 'ZZ-1');
  r := ar_credit_find(200000000002, 'PO', 'po-77');
  INSERT INTO _t VALUES ('find: by PO, any case', jsonb_array_length(r->'matches') = 1 AND r->'matches'->0->>'invoice_number' = 'ZZINV-1');
  r := ar_credit_find(200000000002, 'INVOICE', 'ZZINV-OLD');
  INSERT INTO _t VALUES ('find: cancelled invoice finds nothing', jsonb_array_length(r->'matches') = 0);
  BEGIN
    PERFORM ar_credit_orders_get(200000000002, current_setting('t.cust')::bigint, '2032-04-01', NULL);
    INSERT INTO _t VALUES ('credits: production time is required', false);
  EXCEPTION WHEN raise_exception THEN INSERT INTO _t VALUES ('credits: production time is required', true);
  END;
END $$;
RESET ROLE;

SELECT name, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END FROM _t ORDER BY name;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM _t WHERE ok IS NOT TRUE) THEN RAISE EXCEPTION 'order_invoice_test failed'; END IF; END $$;
ROLLBACK;
