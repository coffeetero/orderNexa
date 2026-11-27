-- ============================================================
-- SQL tests for settled amounts (add_ar_settlements): an invoice paid twice and a payment with unapplied cash, settled the way
-- seed_ar_legacy_settlements does it, drop out of every open-amount calculation: single document, the open-items cache,
-- the reports (as of any date, from settled_at on), open accounts, customer balance, Enter Payments, payment view and search.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/ar_settlements_test.sql
-- Assumes the Alpine Bakery seed (tenant 200000000002, staff user 200000174045).
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t TO PUBLIC;
GRANT ALL ON _id TO PUBLIC;

DO $$
DECLARE a bigint; inv bigint; p1 bigint; p2 bigint; p3 bigint;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (200000000002, 'ZZ SETTLE ACCOUNT', 'ACCOUNT') RETURNING customer_id INTO a;
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, due_date, amount, status)
    VALUES (200000000002, a, 'INV', 'ZZSET-1', '2010-01-05', '2010-01-05', 100, 'OPEN') RETURNING ar_transaction_id INTO inv;
  -- one check entered twice, both applied to the invoice (the old payment detail does this)
  INSERT INTO ar_payments (tenant_id, customer_id, payment_date, amount, payment_number) VALUES (200000000002, a, '2010-01-20', 100, 'ZZP-1') RETURNING ar_payment_id INTO p1;
  INSERT INTO ar_payments (tenant_id, customer_id, payment_date, amount, payment_number) VALUES (200000000002, a, '2010-01-20', 100, 'ZZP-2') RETURNING ar_payment_id INTO p2;
  INSERT INTO ar_payment_applications (tenant_id, ar_payment_id, ar_transaction_id, applied_amount, applied_at) VALUES
    (200000000002, p1, inv, 100, '2010-01-20'), (200000000002, p2, inv, 100, '2010-01-20');
  -- a payment with unapplied cash
  INSERT INTO ar_payments (tenant_id, customer_id, payment_date, amount, payment_number) VALUES (200000000002, a, '2010-02-10', 50, 'ZZP-3') RETURNING ar_payment_id INTO p3;
  INSERT INTO _id VALUES ('a', a), ('inv', inv), ('p3', p3);
END $$;

DO $$
DECLARE a bigint; inv bigint; p3 bigint;
BEGIN
  SELECT v INTO a FROM _id WHERE k = 'a'; SELECT v INTO inv FROM _id WHERE k = 'inv'; SELECT v INTO p3 FROM _id WHERE k = 'p3';
  INSERT INTO _t VALUES ('before: the invoice is overpaid by 100', ar_transaction_open_amount(200000000002, inv) = -100);
  INSERT INTO _t VALUES ('before: the cache holds the invoice (-100) and the payment (-50)',
    (SELECT open_amount FROM ar_open_items WHERE ar_transaction_id = inv) = -100 AND (SELECT open_amount FROM ar_open_items WHERE ar_payment_id = p3) = -50);

  -- settle like the migration step: the invoice on its own date, the payment a little later (to test the date rule)
  UPDATE ar_transactions SET settled_amount = -100, settled_at = '2010-01-05', settled_reason = 'test' WHERE ar_transaction_id = inv;
  UPDATE ar_payments SET settled_amount = 50, settled_at = '2010-03-01', settled_reason = 'test' WHERE ar_payment_id = p3;

  INSERT INTO _t VALUES ('single document: nothing open after settling', ar_transaction_open_amount(200000000002, inv) = 0);
  INSERT INTO _t VALUES ('cache: both rows gone (triggers recalculated them)',
    NOT EXISTS (SELECT 1 FROM ar_open_items WHERE ar_transaction_id = inv OR ar_payment_id = p3));
  INSERT INTO _t VALUES ('report today: nothing open for the account',
    NOT EXISTS (SELECT 1 FROM ar_report_open_items(200000000002, ARRAY[a], current_date) WHERE open_amount <> 0));
  INSERT INTO _t VALUES ('report as of a past date: settled from settled_at on (payment still open before 2010-03-01)',
    (SELECT sum(open_amount) FROM ar_report_open_items(200000000002, ARRAY[a], '2010-02-15') WHERE open_amount <> 0) = -50
    AND NOT EXISTS (SELECT 1 FROM ar_report_open_items(200000000002, ARRAY[a], '2010-03-01') WHERE open_amount <> 0));
  INSERT INTO _t VALUES ('cache and full calculation agree (drift check)',
    (SELECT count(*) FROM ar_report_open_items_full(200000000002, ARRAY[a], current_date) WHERE open_amount <> 0) = 0);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

DO $$
DECLARE a bigint; p3 bigint; r jsonb;
BEGIN
  SELECT v INTO a FROM _id WHERE k = 'a'; SELECT v INTO p3 FROM _id WHERE k = 'p3';
  INSERT INTO _t VALUES ('AR lists: the account is not among accounts with an open balance',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(ar_open_accounts_get(200000000002, current_date)) e WHERE (e->>'customer_id')::bigint = a));
  INSERT INTO _t VALUES ('customer balance: 0', (ar_customer_balance_get(200000000002, a)->>'balance')::numeric = 0);
  r := ar_payment_open_items_get(200000000002, a);
  INSERT INTO _t VALUES ('Enter Payments: no open invoices and no unapplied payments to take',
    jsonb_array_length(r->'invoices') = 0 AND jsonb_array_length(r->'unapplied_payments') = 0);
  r := ar_payment_get(200000000002, p3);
  INSERT INTO _t VALUES ('payment view: unapplied 0, settled 50, status APPLIED',
    (r->>'unapplied')::numeric = 0 AND (r->>'settled')::numeric = 50 AND r->>'status' = 'APPLIED');
  r := ar_payments_search(200000000002, jsonb_build_object('customer_id', a, 'unapplied_only', true));
  INSERT INTO _t VALUES ('payment search: not among payments with cash left',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(r->'payments', r->'rows', '[]'::jsonb)) e WHERE (e->>'ar_payment_id')::bigint = p3));
END $$;

RESET ROLE;
SELECT CASE WHEN COALESCE(ok, false) THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT COALESCE(ok, false)), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % settlement tests failed', bad, total; END IF;
  RAISE NOTICE 'all % settlement tests passed', total;
END $$;
ROLLBACK;
