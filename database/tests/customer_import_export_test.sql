-- ============================================================
-- SQL tests for Export Customers and Import Customers: export layout and filters, round trip with zero changes, row checks,
-- hierarchy order, apply (insert / update, contacts, top customer), re-export of what was imported, access.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/customer_import_export_test.sql
-- Assumes the Alpine Bakery migration: account FEATHERSTONE BAKING (15700) with departments 15702 and 15703, account 10000,
-- staff user 200000174045 (all customers), customer user 200000174046. Test customer numbers start with ZZT (unused).
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
GRANT ALL ON _t TO PUBLIC;

SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b',
  'claims', jsonb_build_object('role', 'authenticated', 'sub', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b', 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) \g /dev/null
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  t bigint := 200000000002;
  acc bigint := (SELECT customer_id FROM fnd_customers WHERE tenant_id = 200000000002 AND customer_number = '15700');
  ex jsonb; r jsonb; imp bigint; d boolean; n int;
  dep jsonb;   -- the export row of 15702
  f jsonb;     -- a file
  row_of jsonb;
BEGIN
  -- 1) export
  ex := bps.fnd_customer_export_get(t, false, NULL);
  INSERT INTO _t VALUES ('export all = every customer', jsonb_array_length(ex) = (SELECT count(*) FROM fnd_customers WHERE tenant_id = t));
  INSERT INTO _t VALUES ('export active only = active customers', jsonb_array_length(bps.fnd_customer_export_get(t, true, NULL)) = (SELECT count(*) FROM fnd_customers WHERE tenant_id = t AND is_active));
  INSERT INTO _t VALUES ('every parent comes before its children', NOT EXISTS (
     SELECT 1 FROM jsonb_array_elements(ex) WITH ORDINALITY c(v, i) JOIN jsonb_array_elements(ex) WITH ORDINALITY p(v, i) ON p.v ->> 'customer_number' = c.v ->> 'parent_number'
      WHERE p.i > c.i));
  INSERT INTO _t VALUES ('rows carry the hierarchy (type and parent number)', EXISTS (SELECT 1 FROM jsonb_array_elements(ex) x WHERE x ->> 'customer_number' = '15702'
     AND x ->> 'parent_number' = '15700' AND x ->> 'customer_type' = 'DEPARTMENT'));
  INSERT INTO _t VALUES ('no internal ids or legacy columns', NOT EXISTS (SELECT 1 FROM jsonb_array_elements(ex) x, jsonb_object_keys(x) k WHERE k LIKE '%\_id' OR k LIKE 'legacy%'));
  r := bps.fnd_customer_export_get(t, false, acc);
  INSERT INTO _t VALUES ('one account: the account first, then only its own customers', r -> 0 ->> 'customer_number' = '15700'
     AND jsonb_array_length(r) = (SELECT count(*) FROM fnd_customers WHERE tenant_id = t AND top_customer_id = acc)
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x ->> 'customer_number' = '10000'));
  BEGIN PERFORM bps.fnd_customer_export_get(t, false, (SELECT customer_id FROM fnd_customers WHERE tenant_id = t AND customer_number = '15702')); d := false;
  EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('the account filter needs an ACCOUNT', d);

  -- 2) round trip: the export imports back with zero changes
  r := bps.fnd_customer_import_upload(t, jsonb_build_object('file_name', 'all.csv', 'rows', ex));
  imp := (r ->> 'customer_import_id')::bigint;
  INSERT INTO _t VALUES ('round trip: every row unchanged, no errors', (r ->> 'unchanged_count')::int = jsonb_array_length(ex)
     AND (r ->> 'new_count')::int = 0 AND (r ->> 'changed_count')::int = 0 AND (r ->> 'error_count')::int = 0);
  r := bps.fnd_customer_import_apply(t, imp);
  INSERT INTO _t VALUES ('round trip apply changes nothing', (r ->> 'applied')::boolean AND (r ->> 'inserted')::int = 0 AND (r ->> 'updated')::int = 0);
  BEGIN PERFORM bps.fnd_customer_import_apply(t, imp); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('an import is applied only once', d);

  -- the same values typed differently are still unchanged (yes/no, $ and commas, mask format, CRLF, spaces)
  dep := (SELECT x FROM jsonb_array_elements(ex) x WHERE x ->> 'customer_number' = '15702');
  r := bps.fnd_customer_import_upload(t, jsonb_build_object('rows', jsonb_build_array(dep
         || jsonb_build_object('customer_number', '157-02', 'parent_number', ' 15700 ', 'is_active', CASE dep ->> 'is_active' WHEN 'Y' THEN 'yes' ELSE 'no' END,
                               'customer_type', lower(dep ->> 'customer_type'),
                               'credit_limit', CASE WHEN dep ->> 'credit_limit' IS NULL THEN NULL ELSE '$' || (dep ->> 'credit_limit') END,
                               'billing_address', replace(dep ->> 'billing_address', E'\n', E'\r\n'), 'pricebook', 'SOME OTHER BOOK'))));
  INSERT INTO _t VALUES ('equivalent values are unchanged; a masked number matches', r -> 'rows' -> 0 ->> 'row_action' = 'UNCHANGED');
  INSERT INTO _t VALUES ('a different pricing book is only a note', r -> 'rows' -> 0 ->> 'issue' LIKE 'Pricing book is not imported%');

  -- 3) row checks
  f := jsonb_build_array(
    jsonb_build_object('customer_number', 'ZZT1', 'customer_name', 'Bad type', 'customer_type', 'SHOP'),
    jsonb_build_object('customer_number', 'ZZT2', 'customer_name', 'Bad flag', 'customer_type', 'ACCOUNT', 'is_active', 'maybe'),
    jsonb_build_object('customer_number', 'ZZT3', 'customer_name', 'Lost', 'customer_type', 'SITE', 'parent_number', 'NOPE-9'),
    jsonb_build_object('customer_number', 'ZZT4', 'customer_name', 'Account with parent', 'customer_type', 'ACCOUNT', 'parent_number', '15700'),
    jsonb_build_object('customer_number', 'ZZT5', 'customer_name', 'Twice', 'customer_type', 'ACCOUNT'),
    jsonb_build_object('customer_number', 'ZZT5', 'customer_name', 'Twice', 'customer_type', 'ACCOUNT'),
    jsonb_build_object('customer_number', 'ZZT6', 'customer_name', 'Under bad', 'customer_type', 'DEPARTMENT', 'parent_number', 'ZZT2'),
    jsonb_build_object('customer_number', 'ZZT7', 'customer_name', '', 'customer_type', 'ACCOUNT', 'billing_type', 'CASH', 'billing_period', 'YEARLY',
                       'credit_limit', '-5', 'delivery_method', 'DRONE', 'cutoff_extra_minutes', 'x', 'invoice_copy_count', '0', 'email', 'nope'),
    jsonb_build_object('customer_number', 'ZZT8', 'customer_name', 'Loop A', 'customer_type', 'SITE', 'parent_number', 'ZZT9'),
    jsonb_build_object('customer_number', 'ZZT9', 'customer_name', 'Loop B', 'customer_type', 'SITE', 'parent_number', 'ZZT8'),
    jsonb_build_object('customer_number', '', 'customer_name', 'No number', 'customer_type', 'ACCOUNT'),
    jsonb_build_object('customer_number', 'ZZT10', 'customer_name', 'Fine', 'customer_type', 'ACCOUNT'));
  r := bps.fnd_customer_import_upload(t, jsonb_build_object('file_name', 'bad.csv', 'rows', f));
  imp := (r ->> 'customer_import_id')::bigint;
  INSERT INTO _t VALUES ('11 rows with errors, 1 new', (r ->> 'error_count')::int = 11 AND (r ->> 'new_count')::int = 1);
  INSERT INTO _t VALUES ('messages: type, flag, parent not found, account with parent, twice, parent has errors, missing number', (
     SELECT bool_and(x ->> 'issue' LIKE m.pat) FROM jsonb_array_elements(r -> 'rows') x
       JOIN (VALUES (1, 'Type must be%'), (2, 'Active must be Y or N'), (3, 'Parent no NOPE-9 not found'), (4, 'An ACCOUNT cannot have a parent'),
                    (5, '%more than once'), (7, 'Parent no ZZT2 has errors'), (9, '%makes a loop%'), (10, '%makes a loop%'), (11, 'Customer no is missing')) m(rn, pat)
         ON (x ->> 'row_number')::int = m.rn) AND (SELECT count(*) FROM jsonb_array_elements(r -> 'rows') x WHERE x ->> 'row_number' IN ('1','2','3','4','5','7','9','10','11')) = 9);
  row_of := (SELECT x FROM jsonb_array_elements(r -> 'rows') x WHERE x ->> 'row_number' = '8');
  INSERT INTO _t VALUES ('every value check on one row', row_of ->> 'issue' LIKE 'Name is missing%' AND row_of ->> 'issue' LIKE '%Billing type%'
     AND row_of ->> 'issue' LIKE '%Billing period%' AND row_of ->> 'issue' LIKE '%Credit limit%' AND row_of ->> 'issue' LIKE '%Delivery method DRONE%'
     AND row_of ->> 'issue' LIKE '%Cutoff extra minutes%' AND row_of ->> 'issue' LIKE '%Invoice copies%' AND row_of ->> 'issue' LIKE '%Email%');
  r := bps.fnd_customer_import_apply(t, imp);
  INSERT INTO _t VALUES ('apply with errors applies nothing', NOT (r ->> 'applied')::boolean AND NOT EXISTS (SELECT 1 FROM fnd_customers WHERE tenant_id = t AND customer_number LIKE 'ZZT%'));

  -- 4) apply: new account -> site -> department (children listed first), a change, contacts
  f := jsonb_build_array(
    jsonb_build_object('customer_number', 'ZZT-D1', 'customer_name', 'Test Kitchen', 'customer_type', 'DEPARTMENT', 'parent_number', 'ZZT-S1',
                       'billing_address', E'1 Test St\nHoboken, NJ 07030', 'phone', '201-555-0101', 'email', 'kitchen@example.test'),
    jsonb_build_object('customer_number', 'ZZT-S1', 'customer_name', 'Test Site', 'customer_type', 'SITE', 'parent_number', 'ZZT-A1', 'invoice_copy_count', '2'),
    jsonb_build_object('customer_number', 'ZZT-A1', 'customer_name', 'Test Account', 'customer_type', 'ACCOUNT', 'billing_type', 'cod', 'billing_period', 'weekly',
                       'credit_limit', '1,500.00', 'delivery_method', 'pickup', 'is_standing_order', 'Y',
                       'billing_address', E'9 Main St\nHoboken, NJ 07030', 'shipping_address', E'9 Dock Rd\nHoboken, NJ 07030'),
    dep || jsonb_build_object('customer_name', 'RENAMED DEPT', 'phone', '201-555-0199', 'shipping_address', E'77 New Rd\nNewark, NJ 07102'));
  r := bps.fnd_customer_import_upload(t, jsonb_build_object('file_name', 'new.csv', 'rows', f));
  imp := (r ->> 'customer_import_id')::bigint;
  INSERT INTO _t VALUES ('preview: 3 new, 1 changed', (r ->> 'new_count')::int = 3 AND (r ->> 'changed_count')::int = 1 AND (r ->> 'error_count')::int = 0);
  INSERT INTO _t VALUES ('changes list the fields with from and to', (SELECT jsonb_agg(c ->> 'field' ORDER BY c ->> 'field') FROM jsonb_array_elements(r -> 'rows') x, jsonb_array_elements(x -> 'changes') c
     WHERE x ->> 'customer_number' = '15702') = '["customer_name", "phone", "shipping_address"]'::jsonb
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'rows') x, jsonb_array_elements(x -> 'changes') c WHERE c ->> 'field' = 'customer_name' AND c ->> 'to' = 'RENAMED DEPT'
                 AND c ->> 'from' = dep ->> 'customer_name'));
  INSERT INTO _t VALUES ('nothing changes before apply', NOT EXISTS (SELECT 1 FROM fnd_customers WHERE tenant_id = t AND customer_number LIKE 'ZZT%'));
  r := bps.fnd_customer_import_apply(t, imp);
  INSERT INTO _t VALUES ('apply inserts 3 and updates 1', (r ->> 'applied')::boolean AND (r ->> 'inserted')::int = 3 AND (r ->> 'updated')::int = 1 AND r ->> 'import_status' = 'APPLIED');
  INSERT INTO _t VALUES ('hierarchy and top customer are set', EXISTS (
     SELECT 1 FROM fnd_customers dd JOIN fnd_customers s ON s.customer_id = dd.customer_parent_id JOIN fnd_customers a ON a.customer_id = s.customer_parent_id
      WHERE dd.tenant_id = t AND dd.customer_number = 'ZZT-D1' AND s.customer_number = 'ZZT-S1' AND a.customer_number = 'ZZT-A1'
        AND dd.top_customer_id = a.customer_id AND s.top_customer_id = a.customer_id AND a.top_customer_id = a.customer_id AND a.customer_parent_id IS NULL));
  INSERT INTO _t VALUES ('new values and defaults', EXISTS (SELECT 1 FROM fnd_customers WHERE tenant_id = t AND customer_number = 'ZZT-A1' AND billing_type = 'COD'
     AND billing_period = 'WEEKLY' AND credit_limit = 1500 AND delivery_method_code = 'PICKUP' AND is_standing_order AND is_active AND is_returns_allowed
     AND NOT is_label_required AND invoice_copy_count = 1)
     AND (SELECT invoice_copy_count FROM fnd_customers WHERE tenant_id = t AND customer_number = 'ZZT-S1') = 2);
  INSERT INTO _t VALUES ('each new customer has a Billing & Shipping contact', (SELECT count(*) FROM fnd_contacts ct JOIN fnd_customers c ON c.customer_id = ct.entity_id
     WHERE ct.source_table = 'fnd_customers' AND ct.contact_type = 'ADDRESSES' AND c.tenant_id = t AND c.customer_number LIKE 'ZZT%') = 3);
  INSERT INTO _t VALUES ('the existing department was updated', (SELECT customer_name FROM fnd_customers WHERE tenant_id = t AND customer_number = '15702') = 'RENAMED DEPT');

  -- re-export what was imported: same values, imports back unchanged
  r := (SELECT jsonb_agg(x) FROM jsonb_array_elements(bps.fnd_customer_export_get(t, false, NULL)) x WHERE x ->> 'customer_number' IN ('ZZT-A1', 'ZZT-S1', 'ZZT-D1', '15702'));
  INSERT INTO _t VALUES ('re-export shows the imported values', EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x ->> 'customer_number' = 'ZZT-D1'
     AND x ->> 'billing_address' = E'1 Test St\nHoboken, NJ 07030' AND x ->> 'phone' = '201-555-0101' AND x ->> 'email' = 'kitchen@example.test')
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x ->> 'customer_number' = 'ZZT-A1' AND x ->> 'shipping_address' = E'9 Dock Rd\nHoboken, NJ 07030'
                 AND x ->> 'credit_limit' = '1500')
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x ->> 'customer_number' = '15702' AND x ->> 'phone' = '201-555-0199'
                 AND x ->> 'shipping_address' = E'77 New Rd\nNewark, NJ 07102' AND x ->> 'billing_address' IS NOT DISTINCT FROM dep ->> 'billing_address'));
  r := bps.fnd_customer_import_upload(t, jsonb_build_object('rows', r));
  INSERT INTO _t VALUES ('...and imports back unchanged', (r ->> 'unchanged_count')::int = 4 AND (r ->> 'row_count')::int = 4);

  -- blank keep-fields keep the value; blank nullable fields clear it
  r := bps.fnd_customer_import_upload(t, jsonb_build_object('rows', jsonb_build_array(jsonb_build_object('customer_number', 'ZZT-A1', 'customer_name', 'Test Account',
         'customer_type', 'ACCOUNT', 'billing_address', '', 'is_standing_order', ''))));
  INSERT INTO _t VALUES ('blank flags and address keep the value; blank billing type, period, credit, delivery clear it',
     (SELECT jsonb_agg(c ->> 'field' ORDER BY c ->> 'field') FROM jsonb_array_elements(r -> 'rows' -> 0 -> 'changes') c)
       = '["billing_period", "billing_type", "credit_limit", "delivery_method"]'::jsonb);

  -- an existing customer may move under a new parent from the same file
  r := bps.fnd_customer_import_upload(t, jsonb_build_object('rows', jsonb_build_array(
         jsonb_build_object('customer_number', 'ZZT-A2', 'customer_name', 'Second', 'customer_type', 'ACCOUNT'),
         (SELECT x FROM jsonb_array_elements(bps.fnd_customer_export_get(t, false, NULL)) x WHERE x ->> 'customer_number' = 'ZZT-S1') || '{"parent_number": "ZZT-A2"}')));
  r := bps.fnd_customer_import_apply(t, (r ->> 'customer_import_id')::bigint);
  INSERT INTO _t VALUES ('a site moves to a new account; its department follows (top customer)', (r ->> 'applied')::boolean AND
     (SELECT top_customer_id FROM fnd_customers WHERE tenant_id = t AND customer_number = 'ZZT-D1') = (SELECT customer_id FROM fnd_customers WHERE tenant_id = t AND customer_number = 'ZZT-A2'));

  -- a loop through an existing customer: ZZT-A2 has child ZZT-S1; make ZZT-A2 a site under ZZT-D1
  r := bps.fnd_customer_import_upload(t, jsonb_build_object('rows', jsonb_build_array(
         jsonb_build_object('customer_number', 'ZZT-A2', 'customer_name', 'Second', 'customer_type', 'SITE', 'parent_number', 'ZZT-D1'))));
  INSERT INTO _t VALUES ('a loop through customers not in the file is found', r -> 'rows' -> 0 ->> 'issue' LIKE '%makes a loop%');

  BEGIN PERFORM bps.fnd_customer_import_upload(t, '{"rows": []}'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('an empty file is refused', d);
END $$;

-- 5) a customer user can neither export nor import
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', '006f6c23-5efa-4f31-b0f3-b36ad4d587e7',
  'claims', jsonb_build_object('role', 'authenticated', 'sub', '006f6c23-5efa-4f31-b0f3-b36ad4d587e7', 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE d boolean;
BEGIN
  BEGIN PERFORM bps.fnd_customer_export_get(200000000002, false, NULL); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('customer user cannot export', d);
  BEGIN PERFORM bps.fnd_customer_import_upload(200000000002, '{"rows": [{"customer_number": "ZZT0"}]}'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('customer user cannot import', d);
  INSERT INTO _t VALUES ('customer user sees no imports', (SELECT count(*) FROM fnd_customer_imports) = 0 AND (SELECT count(*) FROM fnd_customer_import_rows) = 0);
  BEGIN PERFORM bps.fnd_customer_export_rows(200000000002, NULL); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('the internal row function is not callable by app users', d);
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok OR ok IS NULL), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % customer import/export tests failed', bad, total; END IF;
  RAISE NOTICE 'all % customer import/export tests passed', total;
END $$;
ROLLBACK;
