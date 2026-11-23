-- ============================================================
-- SQL tests for saved documents and the Financials report functions. One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q < database/tests/documents_reports_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _ids (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t, _ids TO PUBLIC;

-- Account 91 has orders; build one shipped invoice (25.00), a credit memo (-5.00) and a payment (10.00 applied) around today.
DO $$
DECLARE o record; v_ship bigint; v_sl bigint; v_inv bigint; v_cm bigint; v_pay bigint; v_acc bigint := 200000000091;
        uClerk bigint; uCust91 bigint; uCust40 bigint; r_clerk bigint; r_cadm bigint;
BEGIN
  SELECT order_id, order_line_id, production_run_id INTO o FROM om_orders JOIN om_order_lines USING (order_id, tenant_id) WHERE customer_id = v_acc AND tenant_id = 200000000002 LIMIT 1;
  INSERT INTO om_shipments (tenant_id, production_run_id, ship_to_customer_id, shipment_number, delivery_date, shipment_status)
  VALUES (200000000002, o.production_run_id, v_acc, 'ZZ-SHIP-1', current_date - 40, 'DELIVERED') RETURNING shipment_id INTO v_ship;
  INSERT INTO om_shipment_lines (tenant_id, shipment_id, order_id, order_line_id, quantity, shipped_quantity)
  VALUES (200000000002, v_ship, o.order_id, o.order_line_id, 10, 10) RETURNING shipment_line_id INTO v_sl;
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, due_date, amount, status)
  VALUES (200000000002, v_acc, 'INV', 'ZZ-INV-1', current_date - 40, current_date - 35, 0, 'OPEN') RETURNING ar_transaction_id INTO v_inv;
  INSERT INTO ar_transaction_lines (tenant_id, ar_transaction_id, line_number, source_type, item_description, quantity, unit_price, amount, shipment_line_id)
  VALUES (200000000002, v_inv, 1, 'ITEM', 'zz bread', 10, 2.5, 25, v_sl);
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status, applies_to_ar_transaction_id)
  VALUES (200000000002, v_acc, 'CM', 'ZZ-CM-1', current_date - 10, -5, 'OPEN', v_inv) RETURNING ar_transaction_id INTO v_cm;
  INSERT INTO ar_payments (tenant_id, customer_id, payment_date, amount, payment_number) VALUES (200000000002, v_acc, current_date - 20, 10, 'ZZ-P1') RETURNING ar_payment_id INTO v_pay;
  INSERT INTO ar_payment_applications (tenant_id, ar_payment_id, ar_transaction_id, applied_amount, applied_at) VALUES (200000000002, v_pay, v_inv, 10, now() - interval '20 days');

  INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'zz doc clerk', 'TENANT') RETURNING role_id INTO r_clerk;
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write) VALUES (200000000002, r_clerk, 'orders.enter', true, true);
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz doc clerk', 'TENANCY_USER') RETURNING user_id INTO uClerk;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz doc cust 91', 'CUSTOMER_USER') RETURNING user_id INTO uCust91;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz doc cust 40', 'CUSTOMER_USER') RETURNING user_id INTO uCust40;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) SELECT 200000000002, u FROM unnest(ARRAY[uClerk, uCust91, uCust40]) u;
  INSERT INTO fnd_user_customers (tenant_id, user_id, customer_id) VALUES (200000000002, uCust91, v_acc), (200000000002, uCust40, 200000000040);
  SELECT role_id INTO r_cadm FROM fnd_roles WHERE tenant_id = 200000000002 AND role_name = 'Customer Administrator' AND owner_customer_id IS NULL;
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uClerk, r_clerk), (200000000002, uCust91, r_cadm), (200000000002, uCust40, r_cadm);
  INSERT INTO _ids VALUES ('uClerk', uClerk), ('uCust91', uCust91), ('uCust40', uCust40), ('inv', v_inv);
END $$;

-- ── staff administrator: reports ─────────────────────────────────────────────
DO $$
DECLARE j jsonb; a jsonb; acc bigint[] := ARRAY[200000000091]::bigint[]; n int;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":200000174045}}', true);
  SET LOCAL ROLE authenticated;

  j := fnd_report_accounts_get(200000000002);
  INSERT INTO _t VALUES ('picker lists active accounts only', jsonb_array_length(j) > 0 AND NOT EXISTS (
     SELECT 1 FROM jsonb_array_elements(j) e JOIN fnd_customers c ON c.customer_id = (e ->> 'customer_id')::bigint WHERE upper(c.customer_type) <> 'ACCOUNT' OR NOT c.is_active));

  INSERT INTO _t VALUES ('with-invoices picker lists the account for a range holding its invoice', fnd_report_accounts_get(200000000002, true, current_date - 60, current_date) @> '[{"customer_id":200000000091}]'::jsonb);
  INSERT INTO _t VALUES ('with-invoices picker omits it for a range before the invoice', NOT (fnd_report_accounts_get(200000000002, true, current_date - 90, current_date - 45) @> '[{"customer_id":200000000091}]'::jsonb));
  INSERT INTO _t VALUES ('with-invoices picker lists fewer accounts than the full list', jsonb_array_length(fnd_report_accounts_get(200000000002, true, NULL, current_date)) < jsonb_array_length(fnd_report_accounts_get(200000000002)));
  j := ar_open_balances_get(200000000002, acc, current_date);
  a := j -> 'accounts' -> 0;
  INSERT INTO _t VALUES ('open balance is 10.00 (25 invoice - 10 paid - 5 credit)', (a ->> 'balance')::numeric = 10);
  INSERT INTO _t VALUES ('open items list the invoice (15.00 open) and the credit memo', jsonb_array_length(a -> 'items') = 2
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(a -> 'items') e WHERE e ->> 'document_number' = 'ZZ-INV-1' AND (e ->> 'open')::numeric = 15));
  j := ar_open_balances_get(200000000002, acc, current_date - 45);
  INSERT INTO _t VALUES ('open balance as of before the invoice is 0', ((j -> 'accounts' -> 0) ->> 'balance')::numeric = 0);
  j := ar_open_balances_get(200000000002, acc, current_date - 30);
  INSERT INTO _t VALUES ('open balance as of before the payment is 25.00', ((j -> 'accounts' -> 0) ->> 'balance')::numeric = 25);

  j := ar_aging_get(200000000002, acc, current_date);
  a := j -> 'accounts' -> 0;
  INSERT INTO _t VALUES ('aging puts the invoice in 31-60 and the credit in 1-30', (a ->> 'd31_60')::numeric = 15 AND (a ->> 'd1_30')::numeric = -5 AND (a ->> 'total')::numeric = 10);
  INSERT INTO _t VALUES ('aging totals add up', ((j -> 'totals') ->> 'total')::numeric = 10);

  j := ar_statement_get(200000000002, 200000000091, current_date, current_date - 60);
  INSERT INTO _t VALUES ('statement from before the invoice: opening 0, closing 10, 3 entries', (j ->> 'opening_balance')::numeric = 0 AND (j ->> 'closing_balance')::numeric = 10 AND jsonb_array_length(j -> 'entries') = 3);
  j := ar_statement_get(200000000002, 200000000091, current_date, current_date - 30);
  INSERT INTO _t VALUES ('statement carries the earlier invoice as opening 25 and a running balance', (j ->> 'opening_balance')::numeric = 25 AND ((j -> 'entries' -> 0) ->> 'balance')::numeric = 15 AND (j ->> 'closing_balance')::numeric = 10);

  j := ar_sales_report_get(200000000002, acc, current_date - 60, current_date);
  a := j -> 'accounts' -> 0;
  INSERT INTO _t VALUES ('sales: invoiced 25, credits -5, net 20', (a ->> 'invoiced')::numeric = 25 AND (a ->> 'credits')::numeric = -5 AND (a ->> 'net')::numeric = 20);
  INSERT INTO _t VALUES ('sales lists the item with quantity 10', (a -> 'items' -> 0) ->> 'item' = 'zz bread' AND ((a -> 'items' -> 0) ->> 'quantity')::numeric = 10);

  j := ar_revenue_forecast_get(200000000002, acc, current_date, 8, 4);
  a := j -> 'accounts' -> 0;
  INSERT INTO _t VALUES ('forecast: 20 over 8 weeks is 2.50 a week, 10.00 over 4 weeks', (a ->> 'history_total')::numeric = 20 AND (a ->> 'weekly_average')::numeric = 2.5 AND (a ->> 'projected_total')::numeric = 10);
  BEGIN PERFORM ar_revenue_forecast_get(200000000002, acc, current_date, 1, 4); n := 0; EXCEPTION WHEN OTHERS THEN n := 1; END;
  INSERT INTO _t VALUES ('forecast rejects a one-week look-back', n = 1);

  j := ar_invoice_document_get(200000000002, (SELECT v FROM _ids WHERE k = 'inv'));
  INSERT INTO _t VALUES ('invoice document has header, 1 line and the recognized total', j ->> 'document_number' = 'ZZ-INV-1' AND jsonb_array_length(j -> 'lines') = 1 AND (j ->> 'amount')::numeric = 25);
  INSERT INTO _t VALUES ('unsaved invoices include this one', ar_invoices_unsaved_get(200000000002, 200000000091) @> to_jsonb((SELECT v FROM _ids WHERE k = 'inv')));
  RESET ROLE;
END $$;

-- ── documents: save, list, fetch, access ─────────────────────────────────────
DO $$
DECLARE d1 bigint; d2 bigint; j jsonb; r boolean; b64 text := encode('%PDF-1.4 test'::bytea, 'base64');
        uClerk bigint := (SELECT v FROM _ids WHERE k='uClerk'); u91 bigint := (SELECT v FROM _ids WHERE k='uCust91'); u40 bigint := (SELECT v FROM _ids WHERE k='uCust40');
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":200000174045}}', true);
  SET LOCAL ROLE authenticated;
  d1 := fnd_document_save(200000000002, jsonb_build_object('document_type','STATEMENT','title','Statement','as_of_date',current_date,'customer_id',200000000091,
        'parameters','{"from":"2026-01-01"}'::jsonb,'file_name','s.pdf','content_base64',b64));
  d2 := fnd_document_save(200000000002, jsonb_build_object('document_type','AR_AGING','title','Aging','as_of_date',current_date,'file_name','a.pdf','content_base64',b64));
  INSERT INTO _ids VALUES ('d1', d1), ('d2', d2);
  INSERT INTO _t VALUES ('admin lists the customer documents with as-of date and parameters', (fnd_documents_get(200000000002, 200000000091, NULL) -> 0 ->> 'as_of_date')::date = current_date
     AND (fnd_documents_get(200000000002, 200000000091, NULL) -> 0 -> 'parameters' ->> 'from') = '2026-01-01');
  INSERT INTO _t VALUES ('admin can fetch the PDF bytes back', convert_from(decode(fnd_document_get(200000000002, d1) ->> 'content_base64', 'base64'), 'UTF8') = '%PDF-1.4 test');
  BEGIN PERFORM fnd_document_save(200000000002, jsonb_build_object('document_type','BOGUS','title','x','as_of_date',current_date,'file_name','x.pdf','content_base64',b64)); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('unknown document type is rejected', r);
  BEGIN PERFORM fnd_document_save(200000000002, jsonb_build_object('document_type','SALES','title','x','as_of_date',current_date,'file_name','x.pdf','content_base64','')); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('empty document is rejected', r);
  BEGIN UPDATE fnd_documents SET title = 'changed' WHERE document_id = d1; GET DIAGNOSTICS r = ROW_COUNT; r := (r IS NOT TRUE); EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('saved documents cannot be edited', COALESCE(r, true) AND (SELECT title FROM fnd_documents WHERE document_id = d1) = 'Statement');
  RESET ROLE;

  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', uClerk), true);
  SET LOCAL ROLE authenticated;
  INSERT INTO _t VALUES ('clerk without the documents area sees no documents', jsonb_array_length(fnd_documents_get(200000000002, NULL, NULL)) = 0);
  BEGIN PERFORM fnd_document_save(200000000002, jsonb_build_object('document_type','SALES','title','x','as_of_date',current_date,'file_name','x.pdf','content_base64',b64)); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('clerk cannot save a document', r);
  RESET ROLE;

  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', u91), true);
  SET LOCAL ROLE authenticated;
  j := fnd_documents_get(200000000002, NULL, NULL);
  INSERT INTO _t VALUES ('customer user sees only their own account document', jsonb_array_length(j) = 1 AND (j -> 0 ->> 'document_id')::bigint = d1);
  INSERT INTO _t VALUES ('customer user can open their document', fnd_document_get(200000000002, d1) ->> 'file_name' = 's.pdf');
  BEGIN PERFORM fnd_document_get(200000000002, d2); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('customer user cannot open a multi-customer report', r);
  BEGIN PERFORM fnd_document_save(200000000002, jsonb_build_object('document_type','STATEMENT','title','x','as_of_date',current_date,'customer_id',200000000091,'file_name','x.pdf','content_base64',b64)); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('customer user cannot save a document', r);
  RESET ROLE;

  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', u40), true);
  SET LOCAL ROLE authenticated;
  INSERT INTO _t VALUES ('a customer user of another account sees nothing', jsonb_array_length(fnd_documents_get(200000000002, NULL, NULL)) = 0);
  BEGIN PERFORM fnd_document_get(200000000002, d1); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('and cannot open another account document', r);
  RESET ROLE;
END $$;

SELECT name, CASE WHEN ok THEN 'ok' ELSE 'FAIL' END AS result FROM _t WHERE NOT ok;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM _t;
ROLLBACK;
