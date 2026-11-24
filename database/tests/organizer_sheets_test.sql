-- ============================================================
-- SQL tests for Organizer › Sheets: save / version check, private vs shared visibility, owner-only rename and delete,
-- access area, and the BPS functions (org_sheet_bps_eval). One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/organizer_sheets_test.sql
-- Assumes the Alpine Bakery migration: staff user 200000174045 (Company Administrator), customer user 200000174046,
-- account FEATHERSTONE BAKING (15700) with priced items. Creates two staff users inside the transaction:
-- "zz sheets two" (Company Administrator) and "zz sheets none" (no role).
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _v (k text PRIMARY KEY, v text);
GRANT ALL ON _t, _v TO PUBLIC;

DO $$
DECLARE t bigint := 200000000002; u2 bigint; u3 bigint;
BEGIN
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (t, 'aaaaaaaa-0000-4000-8000-000000000002', 'zz sheets two', 'TENANCY_USER') RETURNING user_id INTO u2;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (t, 'aaaaaaaa-0000-4000-8000-000000000003', 'zz sheets none', 'TENANCY_USER') RETURNING user_id INTO u3;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (t, u2), (t, u3);
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id)
  SELECT t, u2, role_id FROM fnd_roles WHERE tenant_id = t AND is_system AND role_name = 'Company Administrator';
  INSERT INTO _v VALUES ('item', (SELECT i.item_number FROM fnd_items i JOIN ar_transaction_lines l ON l.item_id = i.item_id
                                    JOIN ar_transactions a ON a.ar_transaction_id = l.ar_transaction_id
                                   WHERE a.tenant_id = t AND a.document_number = '546222' ORDER BY i.item_number LIMIT 1));
END $$;

CREATE TEMP TABLE _as (k text PRIMARY KEY, auth uuid);
GRANT ALL ON _as TO PUBLIC;
INSERT INTO _as VALUES ('one', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b'), ('two', 'aaaaaaaa-0000-4000-8000-000000000002'),
                       ('none', 'aaaaaaaa-0000-4000-8000-000000000003'), ('customer', '006f6c23-5efa-4f31-b0f3-b36ad4d587e7');

-- 1) owner: create, update, version check, BPS functions
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'one' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  t bigint := 200000000002; r jsonb; priv bigint; shr bigint; d boolean; e jsonb; item text := (SELECT v FROM _v WHERE k = 'item');
  acc bigint := (SELECT customer_id FROM fnd_customers WHERE tenant_id = 200000000002 AND customer_number = '15700');
  book jsonb := '{"id":"wb","sheets":{"s1":{"id":"s1","name":"Sheet1","cellData":{"0":{"0":{"v":1},"1":{"f":"=A1*2"}}}}}}';
BEGIN
  r := bps.org_sheet_save(t, jsonb_build_object('sheet_name', 'Private list', 'workbook', book));
  priv := (r ->> 'sheet_id')::bigint;
  INSERT INTO _t VALUES ('a new sheet is private by default with version 1', r ->> 'visibility' = 'PRIVATE' AND (r ->> 'version')::int = 1);
  shr := (bps.org_sheet_save(t, jsonb_build_object('sheet_name', 'Shared list', 'visibility', 'shared', 'workbook', book)) ->> 'sheet_id')::bigint;
  INSERT INTO _v VALUES ('priv', priv), ('shr', shr);
  INSERT INTO _t VALUES ('the owner lists both sheets', (SELECT count(*) FROM jsonb_array_elements(bps.org_sheets_get(t)) x
                                                         WHERE (x ->> 'sheet_id')::bigint IN (priv, shr) AND (x ->> 'is_owner')::boolean) = 2);
  INSERT INTO _t VALUES ('get returns the workbook as saved', bps.org_sheet_get(t, priv) -> 'workbook' = book);
  r := bps.org_sheet_save(t, jsonb_build_object('sheet_id', priv, 'sheet_name', 'Private list 2', 'workbook', book, 'version', 1));
  INSERT INTO _t VALUES ('saving with the loaded version bumps it', (r ->> 'version')::int = 2 AND r ->> 'sheet_name' = 'Private list 2');
  BEGIN PERFORM bps.org_sheet_save(t, jsonb_build_object('sheet_id', priv, 'sheet_name', 'x', 'workbook', book, 'version', 1)); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Someone else saved%'; END;
  INSERT INTO _t VALUES ('a stale save is refused', d);
  BEGIN PERFORM bps.org_sheet_save(t, jsonb_build_object('sheet_name', ' ', 'workbook', book)); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a blank name is refused', d);

  e := bps.org_sheet_bps_eval(t, jsonb_build_array(
         jsonb_build_object('fn', 'SALES', 'args', jsonb_build_array('2026-11-01', '2026-11-30')),
         jsonb_build_object('fn', 'balance', 'args', jsonb_build_array('15700')),
         jsonb_build_object('fn', 'AGING', 'args', jsonb_build_array('15700', 'total')),
         jsonb_build_object('fn', 'ITEM_PRICE', 'args', jsonb_build_array(item, '15700')),
         jsonb_build_object('fn', 'QTY_ORDERED', 'args', jsonb_build_array(item, '2026-12-03', 'MORNING')),
         jsonb_build_object('fn', 'NOPE', 'args', '[]'::jsonb),
         jsonb_build_object('fn', 'SALES', 'args', jsonb_build_array('not a date')),
         jsonb_build_object('fn', 'BALANCE', 'args', jsonb_build_array('99999999')),
         jsonb_build_object('fn', 'AGING', 'args', jsonb_build_array('15700', 'week'))));
  INSERT INTO _t VALUES ('SALES = invoices less credits issued in the range',
     (e -> 0 ->> 'v')::numeric = (SELECT COALESCE(SUM(amount), 0) FROM ar_transactions WHERE tenant_id = t AND transaction_type IN ('INV', 'CM')
                                   AND status NOT IN ('DRAFT', 'CANCELLED') AND transaction_date BETWEEN '2026-11-01' AND '2026-11-30'));
  INSERT INTO _t VALUES ('BALANCE = the statement total with credits',
     (e -> 1 ->> 'v')::numeric = (bps.ar_statement_get(t, acc, current_date, true) ->> 'total_due')::numeric);
  INSERT INTO _t VALUES ('AGING total = BALANCE', (e -> 2 ->> 'v')::numeric = (e -> 1 ->> 'v')::numeric);
  INSERT INTO _t VALUES ('ITEM_PRICE = the pricing book price',
     (e -> 3 ->> 'v')::numeric = (bps.fnd_item_prices_map(t, acc, current_date, ARRAY[(SELECT item_id FROM fnd_items WHERE tenant_id = t AND item_number = item ORDER BY is_active DESC LIMIT 1)])
                                  ->> (SELECT item_id FROM fnd_items WHERE tenant_id = t AND item_number = item ORDER BY is_active DESC LIMIT 1)::text)::numeric);
  INSERT INTO _t VALUES ('QTY_ORDERED = the ordered quantity for the date and code',
     (e -> 4 ->> 'v')::numeric = (SELECT COALESCE(SUM(l.quantity), 0) FROM om_order_lines l JOIN om_orders o USING (order_id)
                                   WHERE o.tenant_id = t AND o.production_date = '2026-12-03' AND o.production_code = 'MORNING'
                                     AND l.item_id IN (SELECT item_id FROM fnd_items WHERE tenant_id = t AND item_number = item)));
  INSERT INTO _t VALUES ('errors: unknown function, bad date, unknown customer, bad bucket',
     e -> 5 ->> 'e' = '#NAME?' AND e -> 6 ->> 'e' = '#VALUE!' AND e -> 7 ->> 'e' = '#N/A' AND e -> 8 ->> 'e' = '#VALUE!');
END $$;

-- 2) another staff user: sees shared only, may edit it, may not rename or delete it
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'two' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE t bigint := 200000000002; priv bigint := (SELECT v FROM _v WHERE k = 'priv'); shr bigint := (SELECT v FROM _v WHERE k = 'shr'); d boolean; r jsonb;
BEGIN
  INSERT INTO _t VALUES ('another user sees the shared sheet, not the private one',
     EXISTS (SELECT 1 FROM jsonb_array_elements(bps.org_sheets_get(t)) x WHERE (x ->> 'sheet_id')::bigint = shr AND NOT (x ->> 'is_owner')::boolean)
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(bps.org_sheets_get(t)) x WHERE (x ->> 'sheet_id')::bigint = priv));
  BEGIN PERFORM bps.org_sheet_get(t, priv); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('another user cannot open the private sheet', d);
  r := bps.org_sheet_save(t, jsonb_build_object('sheet_id', shr, 'sheet_name', 'Shared list', 'visibility', 'SHARED', 'workbook', '{"id":"wb2"}'::jsonb, 'version', 1));
  INSERT INTO _t VALUES ('another user can edit a shared sheet', (r ->> 'version')::int = 2);
  BEGIN PERFORM bps.org_sheet_save(t, jsonb_build_object('sheet_id', shr, 'sheet_name', 'Renamed', 'visibility', 'SHARED', 'workbook', '{}'::jsonb, 'version', 2)); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Only the owner%'; END;
  INSERT INTO _t VALUES ('only the owner can rename', d);
  BEGIN PERFORM bps.org_sheet_save(t, jsonb_build_object('sheet_id', shr, 'sheet_name', 'Shared list', 'visibility', 'PRIVATE', 'workbook', '{}'::jsonb, 'version', 2)); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Only the owner%'; END;
  INSERT INTO _t VALUES ('only the owner can change visibility', d);
  BEGIN PERFORM bps.org_sheet_delete(t, shr); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('only the owner can delete', d);
  BEGIN PERFORM bps.org_sheet_save(t, jsonb_build_object('sheet_id', priv, 'sheet_name', 'x', 'workbook', '{}'::jsonb, 'version', 2)); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('another user cannot save over the private sheet', d);
END $$;

-- 3) a staff user without Sheets access
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'none' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE t bigint := 200000000002; d boolean;
BEGIN
  INSERT INTO _t VALUES ('no Sheets access: nothing listed', jsonb_array_length(bps.org_sheets_get(t)) = 0);
  BEGIN PERFORM bps.org_sheet_save(t, jsonb_build_object('sheet_name', 'x', 'workbook', '{}'::jsonb)); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('no Sheets access: cannot save', d);
  INSERT INTO _t VALUES ('no financial access: SALES and BALANCE give #ACCESS',
     (SELECT bool_and(x ->> 'e' = '#ACCESS') FROM jsonb_array_elements(bps.org_sheet_bps_eval(t, jsonb_build_array(
        jsonb_build_object('fn', 'SALES', 'args', jsonb_build_array('2026-11-01')), jsonb_build_object('fn', 'BALANCE', 'args', jsonb_build_array('15700'))))) x));
END $$;

-- 4) a customer user, then the owner deletes
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'customer' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  INSERT INTO _t VALUES ('a customer user sees no sheets', (SELECT count(*) FROM org_sheets) = 0);
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'one' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$ DECLARE t bigint := 200000000002; shr bigint := (SELECT v FROM _v WHERE k = 'shr'); BEGIN
  PERFORM bps.org_sheet_delete(t, shr);
  INSERT INTO _t VALUES ('the owner can delete', NOT EXISTS (SELECT 1 FROM org_sheets WHERE sheet_id = shr));
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % sheets tests failed', bad, total; END IF;
  RAISE NOTICE 'all % sheets tests passed', total;
END $$;
ROLLBACK;
