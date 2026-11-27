-- ============================================================
-- SQL tests for customer segments (add_customer_segments, fnd_customers_save) and the Dashboard sales charts
-- (ar_sales_dashboard_get): segment saved only from the company's list, figures year to date vs the same days last year,
-- a department's sales count for its account and its account's segment, top items + All others, one account's months.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/sales_dashboard_test.sql
-- Assumes the Alpine Bakery seed (tenant 200000000002, staff user 200000174045).
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t TO PUBLIC;
GRANT ALL ON _id TO PUBLIC;

DO $$
DECLARE a bigint; d bigint; today date := (now() AT TIME ZONE fnd_tenant_time_zone(200000000002))::date;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (200000000002, 'ZZ SEG ACCOUNT', 'ACCOUNT') RETURNING customer_id INTO a;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id) VALUES (200000000002, 'Zz Seg Dept', 'DEPARTMENT', a) RETURNING customer_id INTO d;
  -- this year: 1000 invoiced on the department, 100 credited; last year (same days): 500
  INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status) VALUES
    (200000000002, d, 'INV', 'ZZSEG-1', date_trunc('year', today)::date, 1000, 'OPEN'),
    (200000000002, d, 'CM',  'ZZSEG-2', date_trunc('year', today)::date, -100, 'OPEN'),
    (200000000002, d, 'INV', 'ZZSEG-3', date_trunc('year', today - interval '1 year')::date, 500, 'OPEN'),
    (200000000002, d, 'INV', 'ZZSEG-4', date_trunc('year', today)::date, 9999, 'DRAFT');
  INSERT INTO _id VALUES ('a', a), ('d', d);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

DO $$
DECLARE a bigint; r jsonb; s jsonb; ok boolean;
BEGIN
  SELECT v INTO a FROM _id WHERE k = 'a';
  INSERT INTO _t VALUES ('the CUSTOMERSEGMENT list is seeded', (SELECT count(*) FROM fnd_valueset_values vv JOIN fnd_valuesets vs USING (valueset_id)
    WHERE vs.tenant_id = 200000000002 AND vs.valueset_code = 'CUSTOMERSEGMENT') >= 7);

  PERFORM fnd_customers_save(200000000002, a, 'update', jsonb_build_object('segment_code', 'HOTELS'));
  INSERT INTO _t VALUES ('save: a segment from the list is stored', (SELECT segment_code FROM fnd_customers WHERE customer_id = a) = 'HOTELS');
  BEGIN
    PERFORM fnd_customers_save(200000000002, a, 'update', jsonb_build_object('segment_code', 'MARTIANS'));
    ok := false;
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'Unknown segment%';
  END;
  INSERT INTO _t VALUES ('save: a value not in the list is refused', ok);

  r := ar_sales_dashboard_get(200000000002, a);
  INSERT INTO _t VALUES ('one account: this year = invoices less credits, drafts left out (900), last year 500',
    (r->'totals'->>'this')::numeric = 900 AND (r->'totals'->>'last')::numeric = 500);
  INSERT INTO _t VALUES ('months: January to the current month, January holds the figures',
    jsonb_array_length(r->'months') = extract(month FROM (r->>'as_of')::date)::int
    AND (r->'months'->0->>'this')::numeric = 900 AND (r->'months'->0->>'last')::numeric = 500);
  INSERT INTO _t VALUES ('the account is in the picker list (department sales count for it)',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r->'accounts') e WHERE (e->>'customer_id')::bigint = a));
  s := (SELECT e FROM jsonb_array_elements(r->'segments') e WHERE e->>'code' = 'HOTELS');
  INSERT INTO _t VALUES ('segments: the department''s sales count under its account''s segment (Hotels, label from the list)',
    s IS NOT NULL AND s->>'label' = 'Hotels' AND (s->>'this')::numeric >= 900);
  INSERT INTO _t VALUES ('segments: Unassigned comes last',
    (SELECT e->>'code' FROM jsonb_array_elements(r->'segments') WITH ORDINALITY x(e, n) ORDER BY n DESC LIMIT 1) IS NULL
    OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'segments') e WHERE e->>'code' IS NULL));
  r := ar_sales_dashboard_get(200000000002);
  INSERT INTO _t VALUES ('items: at most 7 items then All others',
    jsonb_array_length(r->'items') <= 8 AND (jsonb_array_length(r->'items') < 8 OR (r->'items'->7->>'other')::boolean));
  INSERT INTO _t VALUES ('all accounts: the months add up to the totals',
    (SELECT sum((e->>'this')::numeric) FROM jsonb_array_elements(r->'months') e) = (r->'totals'->>'this')::numeric);
END $$;

SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002),
                    'restricted_tenant_ids', json_build_array(200000000002)))::text, true);
DO $$
BEGIN
  PERFORM ar_sales_dashboard_get(200000000002);
  INSERT INTO _t VALUES ('customer users cannot see sales figures', FALSE);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO _t VALUES ('customer users cannot see sales figures', SQLERRM LIKE 'Only tenant staff%');
END $$;

RESET ROLE;
SELECT CASE WHEN COALESCE(ok, false) THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT COALESCE(ok, false)), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % sales dashboard tests failed', bad, total; END IF;
  RAISE NOTICE 'all % sales dashboard tests passed', total;
END $$;
ROLLBACK;
