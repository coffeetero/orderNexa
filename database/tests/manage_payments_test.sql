-- ============================================================
-- SQL tests for Financials › Manage Payments: post with auto-apply, partial and manual applications, overpayment left
-- on account, credit applications (no negative cash), duplicate reference, refusals (over-application, other account,
-- applications above the payment, void payment), unapply / reapply, void with reason, as-of reports, and AR totals of
-- every other account unchanged. One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/manage_payments_test.sql
-- Assumes the Alpine Bakery migration: staff user 200000174045 (Company Administrator, auth 9b9b43b7-...), customer
-- user auth 006f6c23-..., account TOM CAT BAKERY with open invoices. Creates two zz accounts and their invoices.
-- ============================================================
BEGIN;
SET search_path = bps, public;
-- the tenant's today (the functions use the tenant time zone, not the server's)
CREATE FUNCTION pg_temp.bps_today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(200000000002), 'UTC'))::date $$;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _v (k text PRIMARY KEY, v numeric);
GRANT ALL ON _t, _v TO PUBLIC;

-- fixtures (as admin): account A with a department, account B; invoices and a credit memo dated in the past
DO $$
DECLARE t bigint := 200000000002; a bigint; d bigint; b bigint; x bigint; d0 date := pg_temp.bps_today();
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (t, 'zz Payments A', 'ACCOUNT') RETURNING customer_id INTO a;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id) VALUES (t, 'zz Payments A kitchen', 'DEPARTMENT', a) RETURNING customer_id INTO d;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (t, 'zz Payments B', 'ACCOUNT') RETURNING customer_id INTO b;
  INSERT INTO _v VALUES ('a', a), ('d', d), ('b', b);
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status)
    VALUES (t, a, 'INV', 'ZZP-1', d0 - 60, 100, 'OPEN') RETURNING ar_transaction_id INTO x;
  INSERT INTO _v VALUES ('i1', x);
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status)
    VALUES (t, d, 'INV', 'ZZP-2', d0 - 45, 50, 'OPEN') RETURNING ar_transaction_id INTO x;
  INSERT INTO _v VALUES ('i2', x);
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status)
    VALUES (t, a, 'INV', 'ZZP-3', d0 - 30, 80, 'OPEN') RETURNING ar_transaction_id INTO x;
  INSERT INTO _v VALUES ('i3', x);
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status)
    VALUES (t, a, 'INV', 'ZZP-4', d0 - 20, 40, 'OPEN') RETURNING ar_transaction_id INTO x;
  INSERT INTO _v VALUES ('i4', x);
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status)
    VALUES (t, a, 'CM', 'ZZP-CM1', d0 - 25, -20, 'OPEN') RETURNING ar_transaction_id INTO x;
  INSERT INTO _v VALUES ('cm', x);
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status)
    VALUES (t, b, 'INV', 'ZZP-B1', d0 - 40, 30, 'OPEN') RETURNING ar_transaction_id INTO x;
  INSERT INTO _v VALUES ('ib', x);
  INSERT INTO _v VALUES ('tomcat', (SELECT customer_id FROM fnd_customers WHERE tenant_id = t AND customer_name = 'TOM CAT BAKERY' AND upper(btrim(customer_type)) = 'ACCOUNT' LIMIT 1));
  -- AR total of every real account before the tests
  INSERT INTO _v SELECT 'total_before', SUM(open_amount) FROM ar_report_open_items(t,
    (SELECT array_agg(customer_id) FROM fnd_customers WHERE tenant_id = t AND upper(btrim(customer_type)) = 'ACCOUNT' AND customer_name NOT LIKE 'zz %'), pg_temp.bps_today());
END $$;

SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b'::uuid,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b', 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) \g /dev/null
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  t  bigint := 200000000002;
  a  bigint := (SELECT v FROM _v WHERE k = 'a');   b  bigint := (SELECT v FROM _v WHERE k = 'b');
  i1 bigint := (SELECT v FROM _v WHERE k = 'i1');  i2 bigint := (SELECT v FROM _v WHERE k = 'i2');
  i3 bigint := (SELECT v FROM _v WHERE k = 'i3');  i4 bigint := (SELECT v FROM _v WHERE k = 'i4');
  cm bigint := (SELECT v FROM _v WHERE k = 'cm');  ib bigint := (SELECT v FROM _v WHERE k = 'ib');
  pd date := pg_temp.bps_today() - 3;
  r jsonb; p_auto bigint; p_over bigint; p_cred bigint; ok boolean; msg text; app bigint; bal numeric;
BEGIN
  -- open items list the account and its department, oldest first; the credit memo is available
  r := ar_payment_open_items_get(t, a);
  INSERT INTO _t VALUES ('open items: 4 invoices of the account tree, oldest first, and the credit',
    jsonb_array_length(r -> 'invoices') = 4 AND (r -> 'invoices' -> 0 ->> 'ar_transaction_id')::bigint = i1
    AND (r -> 'invoices' -> 1 ->> 'ar_transaction_id')::bigint = i2 AND (r -> 'credits' -> 0 ->> 'available')::numeric = 20);

  -- 1) auto-apply 120: invoice 1 in full, 20 on invoice 2 (the department's)
  r := ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'ACH', 'reference_number', 'ZZ-ACH-1',
                                            'amount', 120, 'auto_apply', true));
  p_auto := (r ->> 'ar_payment_id')::bigint;
  INSERT INTO _t VALUES ('auto-apply pays the oldest invoices first',
    ar_transaction_open_amount(t, i1) = 0 AND ar_transaction_open_amount(t, i2) = 30 AND ar_transaction_open_amount(t, i3) = 80
    AND (r ->> 'unapplied')::numeric = 0 AND r ->> 'status' = 'APPLIED' AND r ->> 'payment_number' LIKE 'PMT-%');
  INSERT INTO _t VALUES ('applications are dated the payment date (or the invoice date if later)',
    (SELECT bool_and(applied_at::date = pd) FROM ar_payment_applications WHERE ar_payment_id = p_auto));

  -- 2) partial: 10 on invoice 3
  r := ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'CASH', 'amount', 10,
                                            'applications', jsonb_build_array(jsonb_build_object('ar_transaction_id', i3, 'amount', 10))));
  INSERT INTO _t VALUES ('a partial payment leaves the rest of the invoice open', ar_transaction_open_amount(t, i3) = 70);

  -- 3) overpayment: 200 pays invoice 2 (30) and 3 (70); 100 stays on account
  r := ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'CHECK', 'reference_number', 'ZZ1001',
         'amount', 200, 'applications', jsonb_build_array(jsonb_build_object('ar_transaction_id', i2, 'amount', 30),
                                                          jsonb_build_object('ar_transaction_id', i3, 'amount', 70))));
  p_over := (r ->> 'ar_payment_id')::bigint;
  INSERT INTO _t VALUES ('an overpayment leaves unapplied cash', (r ->> 'unapplied')::numeric = 100 AND r ->> 'status' = 'PARTIAL'
    AND ar_transaction_open_amount(t, i2) = 0 AND ar_transaction_open_amount(t, i3) = 0);
  SELECT SUM(open_amount) INTO bal FROM ar_report_open_items(t, ARRAY[a], pg_temp.bps_today());
  -- invoices 270 + credit -20 - payments 330 = -80
  INSERT INTO _t VALUES ('AR balance of the account = invoices - credit - payments (-80)', bal = -80);
  INSERT INTO _t VALUES ('the unapplied cash shows as a credit line in open items',
    (SELECT open_amount FROM ar_report_open_items(t, ARRAY[a], pg_temp.bps_today()) WHERE transaction_type = 'PMT' AND document_number = r ->> 'payment_number') = -100);

  -- 4) refusals
  BEGIN PERFORM ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'ACH', 'amount', 50,
                  'applications', jsonb_build_array(jsonb_build_object('ar_transaction_id', i4, 'amount', 45))));
    ok := true; EXCEPTION WHEN OTHERS THEN ok := false; msg := SQLERRM; END;
  INSERT INTO _t VALUES ('over-applying an invoice is refused', NOT ok AND msg LIKE 'Cannot apply 45 to invoice ZZP-4: only 40.00 is open');
  BEGIN PERFORM ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'ACH', 'amount', 30,
                  'applications', jsonb_build_array(jsonb_build_object('ar_transaction_id', i4, 'amount', 40))));
    ok := true; EXCEPTION WHEN OTHERS THEN ok := false; msg := SQLERRM; END;
  INSERT INTO _t VALUES ('applications above the payment are refused', NOT ok AND msg LIKE 'Applying 40 of cash is more than the payment has unapplied%');
  BEGIN PERFORM ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'ACH', 'amount', 30,
                  'applications', jsonb_build_array(jsonb_build_object('ar_transaction_id', ib, 'amount', 30))));
    ok := true; EXCEPTION WHEN OTHERS THEN ok := false; msg := SQLERRM; END;
  INSERT INTO _t VALUES ('another account''s invoice is refused', NOT ok AND msg LIKE '%belongs to another customer account');
  BEGIN PERFORM ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'ACH', 'amount', 30,
                  'applications', jsonb_build_array(jsonb_build_object('ar_transaction_id', cm, 'amount', 10))));
    ok := true; EXCEPTION WHEN OTHERS THEN ok := false; msg := SQLERRM; END;
  INSERT INTO _t VALUES ('cash cannot be applied to a credit memo', NOT ok AND msg LIKE 'Only invoices can be paid%');
  BEGIN PERFORM ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pg_temp.bps_today() + 1, 'payment_method', 'ACH', 'amount', 5));
    ok := true; EXCEPTION WHEN OTHERS THEN ok := false; END;
  INSERT INTO _t VALUES ('a future payment date is refused', NOT ok);
  BEGIN PERFORM ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'CHECK', 'amount', 5));
    ok := true; EXCEPTION WHEN OTHERS THEN ok := false; msg := SQLERRM; END;
  INSERT INTO _t VALUES ('a check needs its number', NOT ok AND msg = 'Enter the check number');
  BEGIN PERFORM ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'ACH', 'amount', 5.555));
    ok := true; EXCEPTION WHEN OTHERS THEN ok := false; END;
  INSERT INTO _t VALUES ('fractions of a cent are refused', NOT ok);

  -- 5) duplicate check number
  BEGIN PERFORM ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'CHECK', 'reference_number', ' zz1001 ', 'amount', 5));
    ok := true; EXCEPTION WHEN OTHERS THEN ok := false; msg := SQLERRM; END;
  INSERT INTO _t VALUES ('the same check number for the customer needs confirmation', NOT ok AND msg LIKE 'Duplicate reference: zz1001 is already on payment PMT-%');
  r := ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'CHECK', 'reference_number', 'ZZ1001', 'amount', 5, 'allow_duplicate', true));
  INSERT INTO _t VALUES ('... and is saved once confirmed', r ->> 'status' = 'UNAPPLIED');
  PERFORM ar_payment_void(t, (r ->> 'ar_payment_id')::bigint, 'Entered twice');

  -- 6) credit application: a $0 payment uses credit memo 20 on invoice 4; no negative cash
  r := ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'MISC', 'amount', 0,
         'applications', jsonb_build_array(jsonb_build_object('ar_transaction_id', i4, 'amount', 20)),
         'credits', jsonb_build_array(jsonb_build_object('ar_transaction_id', cm, 'amount', 20))));
  p_cred := (r ->> 'ar_payment_id')::bigint;
  INSERT INTO _t VALUES ('a credit memo applied to an invoice: invoice 20 open, credit used up',
    ar_transaction_open_amount(t, i4) = 20 AND ar_transaction_open_amount(t, cm) = 0
    AND jsonb_array_length(r -> 'credit_applications') = 1 AND jsonb_array_length(r -> 'applications') = 0);
  INSERT INTO _t VALUES ('no new negative payment applications', NOT EXISTS (SELECT 1 FROM ar_payment_applications pa
    JOIN ar_payments p ON p.ar_payment_id = pa.ar_payment_id WHERE p.customer_id = a AND pa.applied_amount <= 0));
  BEGIN PERFORM ar_payment_post(t, jsonb_build_object('customer_id', a, 'payment_date', pd, 'payment_method', 'MISC', 'amount', 0,
                  'applications', jsonb_build_array(jsonb_build_object('ar_transaction_id', i4, 'amount', 5)),
                  'credits', jsonb_build_array(jsonb_build_object('ar_transaction_id', cm, 'amount', 5))));
    ok := true; EXCEPTION WHEN OTHERS THEN ok := false; msg := SQLERRM; END;
  INSERT INTO _t VALUES ('a used-up credit cannot be used again', NOT ok AND msg LIKE 'Cannot use 5 of credit ZZP-CM1: only 0.00 is left');
  SELECT SUM(open_amount) INTO bal FROM ar_report_open_items(t, ARRAY[a], pg_temp.bps_today());
  INSERT INTO _t VALUES ('applying a credit does not change the account balance', bal = -80);

  -- 7) unapply one application of the overpayment, then reapply it
  SELECT ar_payment_application_id INTO app FROM ar_payment_applications WHERE ar_payment_id = p_over AND ar_transaction_id = i3;
  r := ar_payment_unapply(t, p_over, jsonb_build_object('application_ids', jsonb_build_array(app), 'reason', 'Wrong invoice'));
  INSERT INTO _t VALUES ('unapply reopens the invoice and returns the cash, keeping the row',
    ar_transaction_open_amount(t, i3) = 70 AND (r ->> 'unapplied')::numeric = 170
    AND (SELECT reversed_at IS NOT NULL AND reversal_reason = 'Wrong invoice' AND reversed_by IS NOT NULL FROM ar_payment_applications WHERE ar_payment_application_id = app));
  BEGIN PERFORM ar_payment_unapply(t, p_over, jsonb_build_object('application_ids', jsonb_build_array(app)));
    ok := true; EXCEPTION WHEN OTHERS THEN ok := false; END;
  INSERT INTO _t VALUES ('an application cannot be unapplied twice', NOT ok);
  INSERT INTO _t VALUES ('the payment is in the unapplied-only search',
    EXISTS (SELECT 1 FROM jsonb_array_elements(ar_payments_search(t, jsonb_build_object('customer_id', a, 'unapplied_only', true)) -> 'rows') x
             WHERE (x ->> 'ar_payment_id')::bigint = p_over AND (x ->> 'unapplied')::numeric = 170));
  r := ar_payment_apply(t, p_over, jsonb_build_object('applications', jsonb_build_array(jsonb_build_object('ar_transaction_id', i3, 'amount', 70))));
  INSERT INTO _t VALUES ('reapply pays the invoice again from the unapplied cash',
    ar_transaction_open_amount(t, i3) = 0 AND (r ->> 'unapplied')::numeric = 100 AND jsonb_array_length(r -> 'applications') = 3);

  -- 8) void the auto-applied payment (bounced): invoices 1 and 2 reopen, rows kept
  BEGIN PERFORM ar_payment_void(t, p_auto, ' '); ok := true; EXCEPTION WHEN OTHERS THEN ok := false; END;
  INSERT INTO _t VALUES ('void needs a reason', NOT ok);
  r := ar_payment_void(t, p_auto, 'NSF check');
  INSERT INTO _t VALUES ('void reverses the applications and keeps the payment',
    r ->> 'status' = 'VOID' AND r ->> 'void_reason' = 'NSF check' AND ar_transaction_open_amount(t, i1) = 100
    AND ar_transaction_open_amount(t, i2) = 20 AND EXISTS (SELECT 1 FROM ar_payments WHERE ar_payment_id = p_auto)
    AND (SELECT bool_and(reversal_reason = 'Void: NSF check') FROM ar_payment_applications WHERE ar_payment_id = p_auto));
  BEGIN PERFORM ar_payment_apply(t, p_auto, jsonb_build_object('auto_apply', true)); ok := true; EXCEPTION WHEN OTHERS THEN ok := false; END;
  INSERT INTO _t VALUES ('a void payment cannot be applied', NOT ok);
  SELECT SUM(open_amount) INTO bal FROM ar_report_open_items(t, ARRAY[a], pg_temp.bps_today());
  INSERT INTO _t VALUES ('after the void the account owes 120 more (40)', bal = 40);
  SELECT SUM(open_amount) INTO bal FROM ar_report_open_items(t, ARRAY[a], pg_temp.bps_today() - 1);
  -- -80, and the 5.00 duplicate (voided today, so still on the books yesterday)
  INSERT INTO _t VALUES ('as of yesterday the voided payments and their applications still count (-85)', bal = -85);
  INSERT INTO _t VALUES ('as of yesterday invoice 1 was paid',
    (SELECT open_amount FROM ar_report_open_items(t, ARRAY[a], pg_temp.bps_today() - 1) WHERE ar_transaction_id = i1) = 0);

  -- 9) a real account: auto-apply 1000 reduces exactly the oldest open invoices and the account by 1000
  INSERT INTO _v SELECT 'tc_before', SUM(open_amount) FROM ar_report_open_items(t, ARRAY[(SELECT v FROM _v WHERE k = 'tomcat')::bigint], pg_temp.bps_today());
  r := ar_payment_allocate(t, jsonb_build_object('customer_id', (SELECT v FROM _v WHERE k = 'tomcat'), 'amount', 1000));
  CREATE TEMP TABLE _plan AS SELECT (x ->> 'ar_transaction_id')::bigint AS id, (x ->> 'amount')::numeric AS amt,
         ar_transaction_open_amount(t, (x ->> 'ar_transaction_id')::bigint) AS open_before FROM jsonb_array_elements(r -> 'applications') x;
  r := ar_payment_post(t, jsonb_build_object('customer_id', (SELECT v FROM _v WHERE k = 'tomcat'), 'payment_date', pd, 'payment_method', 'ACH',
                                            'amount', 1000, 'auto_apply', true));
  INSERT INTO _t VALUES ('real account: each planned invoice drops by exactly its amount',
    (SELECT bool_and(ar_transaction_open_amount(t, id) = open_before - amt) AND SUM(amt) = 1000 FROM _plan)
    AND (SELECT SUM(applied_amount) FROM ar_payment_applications WHERE ar_payment_id = (r ->> 'ar_payment_id')::bigint) = 1000);
  INSERT INTO _t VALUES ('real account: open balance down exactly 1000',
    (SELECT SUM(open_amount) FROM ar_report_open_items(t, ARRAY[(SELECT v FROM _v WHERE k = 'tomcat')::bigint], pg_temp.bps_today())) = (SELECT v FROM _v WHERE k = 'tc_before') - 1000);
END $$;
RESET ROLE;

-- 10) a customer user cannot enter payments
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', '006f6c23-5efa-4f31-b0f3-b36ad4d587e7'::uuid,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', '006f6c23-5efa-4f31-b0f3-b36ad4d587e7', 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) \g /dev/null
SET LOCAL ROLE authenticated;
DO $$ DECLARE ok boolean; BEGIN
  BEGIN PERFORM bps.ar_payment_post(200000000002, jsonb_build_object('customer_id', (SELECT v FROM _v WHERE k = 'a'), 'payment_date', pg_temp.bps_today(),
                  'payment_method', 'ACH', 'amount', 5));
    ok := true; EXCEPTION WHEN OTHERS THEN ok := false; END;
  INSERT INTO _t VALUES ('a customer user cannot enter payments', NOT ok);
END $$;
RESET ROLE;

-- 11) every other account: AR total unchanged except the real-account payment (which nets to zero)
INSERT INTO _t SELECT 'AR total of all real accounts unchanged by the tests', SUM(open_amount) = (SELECT v FROM _v WHERE k = 'total_before') - 1000
  FROM ar_report_open_items(200000000002,
    (SELECT array_agg(customer_id) FROM fnd_customers WHERE tenant_id = 200000000002 AND upper(btrim(customer_type)) = 'ACCOUNT' AND customer_name NOT LIKE 'zz %'), pg_temp.bps_today());

SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % manage payments tests failed', bad, total; END IF;
  RAISE NOTICE 'all % manage payments tests passed', total;
END $$;
ROLLBACK;
