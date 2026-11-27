-- ============================================================
-- SQL tests for Purchasing (proof of concept): vendors (codes, names, terms, delivery days), vendor items (kinds,
-- ingredient link, packs), cost per lb / kg / l / gal / each from the pack price, price history (new, changed, unchanged),
-- preferred source per ingredient, vendor contacts (fnd_contacts with source_table po_vendors), deletes, access.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/purchasing_test.sql
-- Assumes the Alpine Bakery migration: staff user 200000174045 (Company Administrator).
-- Creates staff user "zz purchasing none" (no role) inside the transaction.
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
GRANT ALL ON _t TO PUBLIC;

DO $$
DECLARE t bigint := 200000000002; u3 bigint;
BEGIN
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (t, 'aaaaaaaa-0000-4000-8000-0000000000e1', 'zz purchasing none', 'TENANCY_USER') RETURNING user_id INTO u3;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (t, u3);
END $$;

CREATE TEMP TABLE _as (k text PRIMARY KEY, auth uuid);
GRANT ALL ON _as TO PUBLIC;
INSERT INTO _as VALUES ('one', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b'), ('none', 'aaaaaaaa-0000-4000-8000-0000000000e1');

-- 1) staff administrator
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'one' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  t bigint := 200000000002; d boolean; r jsonb; h jsonb;
  giusto bigint; central bigint; flour bigint; i1 bigint; i2 bigint; i3 bigint; i4 bigint; c jsonb;
BEGIN
  -- vendors
  r := bps.po_vendor_save(t, '{"vendor_code":"zz-giusto","vendor_name":"zz Giusto''s","account_number":"A-1001","payment_terms":"Net 30",
                               "lead_time_days":"3","delivery_days":["thu","mon","MON"],"min_order_amount":"250"}');
  giusto := (r ->> 'vendor_id')::bigint;
  INSERT INTO _t VALUES ('vendor saved: code upper case, days in week order without repeats, USD by default',
    r ->> 'vendor_code' = 'ZZ-GIUSTO' AND r -> 'delivery_days' = '["MON","THU"]'::jsonb AND r ->> 'currency_code' = 'USD'
    AND (r ->> 'lead_time_days')::int = 3 AND (r ->> 'min_order_amount')::numeric = 250 AND (r ->> 'item_count')::int = 0);
  central := (bps.po_vendor_save(t, '{"vendor_code":"ZZ-CENTRAL","vendor_name":"zz Central Milling"}') ->> 'vendor_id')::bigint;
  BEGIN PERFORM bps.po_vendor_save(t, '{"vendor_code":"ZZ-GIUSTO","vendor_name":"zz other"}'); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'There is already a vendor with code%'; END;
  INSERT INTO _t VALUES ('vendor codes are unique', d);
  BEGIN PERFORM bps.po_vendor_save(t, '{"vendor_code":"ZZ-X","vendor_name":"ZZ GIUSTO''S"}'); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'There is already a vendor called%'; END;
  INSERT INTO _t VALUES ('vendor names are unique (any case)', d);
  BEGIN PERFORM bps.po_vendor_save(t, '{"vendor_code":"zz bad code","vendor_name":"zz y"}'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('vendor code with spaces refused', d);
  BEGIN PERFORM bps.po_vendor_save(t, '{"vendor_code":"ZZ-Y","vendor_name":"zz y","delivery_days":["XYZ"]}'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('unknown delivery day refused', d);
  r := bps.po_vendor_save(t, jsonb_build_object('vendor_id', giusto, 'vendor_code', 'ZZ-GIUSTO', 'vendor_name', 'zz Giusto''s Specialty Foods', 'payment_terms', 'Net 15'));
  INSERT INTO _t VALUES ('vendor updated', r ->> 'vendor_name' = 'zz Giusto''s Specialty Foods' AND r ->> 'payment_terms' = 'Net 15');

  -- vendor contacts reuse fnd_contacts
  PERFORM bps.fnd_contacts_save(t, giusto, 'po_vendors', '{"contact_type":"PERSON","card_name":"zz Ana Rep","first_name":"zz Ana","last_name":"Rep","contact_points":[{"type":"PHONE","value":"555-0100","label":"Work"}]}'::jsonb);
  c := bps.fnd_contacts_get(t, giusto, 'po_vendors');
  INSERT INTO _t VALUES ('vendor contact saved and listed through fnd_contacts', jsonb_array_length(c) >= 1
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(c) x WHERE x ->> 'first_name' = 'zz Ana'));

  -- vendor items
  flour := (bps.inv_ingredient_save(t, '{"ingredient_name":"zz PO Bread flour","ingredient_role":"FLOUR"}') ->> 'ingredient_id')::bigint;
  r := bps.po_vendor_item_save(t, jsonb_build_object('vendor_id', giusto, 'ingredient_id', flour, 'vendor_sku', 'HP-50', 'description', 'zz High Performer flour',
         'pack_qty', '50', 'pack_unit', 'lb', 'pack_label', 'bag', 'pack_price', '25.00', 'is_preferred', true));
  i1 := (r ->> 'vendor_item_id')::bigint;
  INSERT INTO _t VALUES ('50 lb bag at $25: $0.50/lb, $1.1023/kg; kind INGREDIENT; preferred; price dated today',
    (r ->> 'cost_per_lb')::numeric = 0.5 AND (r ->> 'cost_per_kg')::numeric = 1.1023 AND r ->> 'item_kind' = 'INGREDIENT'
    AND (r ->> 'is_preferred')::boolean AND r ->> 'ingredient_name' = 'zz PO Bread flour' AND r ->> 'price_date_iso' IS NOT NULL
    AND r -> 'cost_per_ea' = 'null'::jsonb);
  INSERT INTO _t VALUES ('a new item with a price starts its price history', (r ->> 'price_changes')::int = 1);

  r := bps.po_vendor_item_save(t, jsonb_build_object('vendor_id', central, 'ingredient_id', flour, 'description', 'zz Organic Type 85',
         'pack_qty', '25', 'pack_unit', 'kg', 'pack_price', '30', 'is_preferred', true));
  i2 := (r ->> 'vendor_item_id')::bigint;
  INSERT INTO _t VALUES ('25 kg at $30: $1.20/kg', (r ->> 'cost_per_kg')::numeric = 1.2 AND (r ->> 'cost_per_lb')::numeric = 0.5443);
  INSERT INTO _t VALUES ('marking a second source preferred clears the first',
    NOT (SELECT is_preferred FROM po_vendor_items WHERE vendor_item_id = i1) AND (SELECT is_preferred FROM po_vendor_items WHERE vendor_item_id = i2));

  -- price history: unchanged price adds nothing, a change adds a row with the change
  PERFORM bps.po_vendor_item_save(t, jsonb_build_object('vendor_item_id', i1, 'vendor_id', giusto, 'ingredient_id', flour, 'vendor_sku', 'HP-50',
            'description', 'zz High Performer flour 50 lb', 'pack_qty', '50', 'pack_unit', 'lb', 'pack_price', '25.00'));
  INSERT INTO _t VALUES ('saving with the same price adds no history', (SELECT count(*) FROM po_vendor_item_prices WHERE vendor_item_id = i1) = 1);
  PERFORM bps.po_vendor_item_save(t, jsonb_build_object('vendor_item_id', i1, 'vendor_id', giusto, 'ingredient_id', flour, 'vendor_sku', 'HP-50',
            'description', 'zz High Performer flour 50 lb', 'pack_qty', '50', 'pack_unit', 'lb', 'pack_price', '27.50', 'price_date', '2099-01-01'));
  h := bps.po_vendor_item_prices_get(t, i1);
  INSERT INTO _t VALUES ('a price change is kept, newest first, with +$2.50 / +10%', jsonb_array_length(h) = 2
    AND (h -> 0 ->> 'pack_price')::numeric = 27.5 AND (h -> 0 ->> 'change')::numeric = 2.5 AND (h -> 0 ->> 'change_pct')::numeric = 10
    AND h -> 0 ->> 'effective_date' = '01/01/2099' AND h -> 1 -> 'change' = 'null'::jsonb);

  -- packaging, volumes, each
  r := bps.po_vendor_item_save(t, jsonb_build_object('vendor_id', giusto, 'item_kind', 'PACKAGING', 'description', 'zz Baguette bags',
         'pack_qty', '1000', 'pack_unit', 'ea', 'pack_label', 'case', 'pack_price', '45'));
  i3 := (r ->> 'vendor_item_id')::bigint;
  INSERT INTO _t VALUES ('case of 1000 bags at $45: $0.045 each, no weight cost', (r ->> 'cost_per_ea')::numeric = 0.045 AND r -> 'cost_per_lb' = 'null'::jsonb);
  r := bps.po_vendor_item_save(t, jsonb_build_object('vendor_id', central, 'description', 'zz Olive oil', 'pack_qty', '4', 'pack_unit', 'gal', 'pack_price', '80'));
  i4 := (r ->> 'vendor_item_id')::bigint;
  INSERT INTO _t VALUES ('4 gal at $80: $20/gal, $5.2834/l', (r ->> 'cost_per_gal')::numeric = 20 AND (r ->> 'cost_per_l')::numeric = 5.2834);
  r := bps.po_vendor_item_save(t, jsonb_build_object('vendor_id', central, 'description', 'zz no price yet', 'pack_qty', '1', 'pack_unit', 'lb'));
  INSERT INTO _t VALUES ('an item without a price has no cost, no price date and no history',
    r -> 'cost_per_lb' = 'null'::jsonb AND r -> 'price_date_iso' = 'null'::jsonb AND (r ->> 'price_changes')::int = 0);

  BEGIN PERFORM bps.po_vendor_item_save(t, jsonb_build_object('vendor_id', giusto, 'item_kind', 'PACKAGING', 'ingredient_id', flour, 'description', 'zz x', 'pack_qty', '1')); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Only ingredient items%'; END;
  INSERT INTO _t VALUES ('packaging cannot link to an ingredient', d);
  BEGIN PERFORM bps.po_vendor_item_save(t, jsonb_build_object('vendor_id', giusto, 'description', 'zz x', 'pack_qty', '1', 'is_preferred', true)); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Link an ingredient%'; END;
  INSERT INTO _t VALUES ('preferred needs an ingredient', d);
  BEGIN PERFORM bps.po_vendor_item_save(t, jsonb_build_object('vendor_id', giusto, 'vendor_sku', 'hp-50', 'description', 'zz dup', 'pack_qty', '1')); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'This vendor already has an item with SKU%'; END;
  INSERT INTO _t VALUES ('SKUs are unique per vendor (any case)', d);
  BEGIN PERFORM bps.po_vendor_item_save(t, jsonb_build_object('vendor_id', giusto, 'description', 'zz x', 'pack_qty', '0')); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('pack size above 0 required', d);
  BEGIN PERFORM bps.po_vendor_item_save(t, jsonb_build_object('vendor_id', giusto, 'description', 'zz x', 'pack_qty', '1', 'pack_unit', 'bushel')); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('unknown pack unit refused', d);

  -- lists
  INSERT INTO _t VALUES ('vendor items for one vendor, and for all', jsonb_array_length(bps.po_vendor_items_get(t, giusto)) = 2
    AND (SELECT count(*) FROM jsonb_array_elements(bps.po_vendor_items_get(t)) x WHERE x ->> 'description' LIKE 'zz %') = 5);
  INSERT INTO _t VALUES ('vendor list counts active items', (SELECT (x ->> 'item_count')::int FROM jsonb_array_elements(bps.po_vendors_get(t)) x WHERE (x ->> 'vendor_id')::bigint = giusto) = 2);
  INSERT INTO _t VALUES ('options list vendors and ingredients',
    EXISTS (SELECT 1 FROM jsonb_array_elements(bps.po_options_get(t) -> 'vendors') x WHERE (x ->> 'vendor_id')::bigint = central)
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(bps.po_options_get(t) -> 'ingredients') x WHERE (x ->> 'ingredient_id')::bigint = flour));

  -- deletes
  BEGIN PERFORM bps.po_vendor_delete(t, giusto); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'This vendor has 2 item(s)%'; END;
  INSERT INTO _t VALUES ('a vendor with items cannot be deleted', d);
  PERFORM bps.po_vendor_item_delete(t, i1);
  INSERT INTO _t VALUES ('deleting an item removes its price history', NOT EXISTS (SELECT 1 FROM po_vendor_item_prices WHERE vendor_item_id = i1));
  PERFORM bps.po_vendor_item_delete(t, i3);
  PERFORM bps.po_vendor_delete(t, giusto);
  INSERT INTO _t VALUES ('an empty vendor is deleted with its contacts', NOT EXISTS (SELECT 1 FROM po_vendors WHERE vendor_id = giusto)
    AND NOT EXISTS (SELECT 1 FROM fnd_contacts WHERE source_table = 'po_vendors' AND entity_id = giusto));
END $$;

-- 2) a staff user without Purchasing access
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'none' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE t bigint := 200000000002; d boolean;
BEGIN
  BEGIN PERFORM bps.po_vendors_get(t); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'You do not have access%'; END;
  INSERT INTO _t VALUES ('no Purchasing access: cannot list vendors', d);
  BEGIN PERFORM bps.po_vendor_save(t, '{"vendor_code":"ZZ-NOPE","vendor_name":"zz nope"}'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('no Purchasing access: cannot add a vendor', d);
  INSERT INTO _t VALUES ('no Purchasing access: rows hidden by row security', (SELECT count(*) FROM po_vendors) = 0 AND (SELECT count(*) FROM po_vendor_items) = 0);
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok OR ok IS NULL), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % purchasing tests failed', bad, total; END IF;
  RAISE NOTICE 'all % purchasing tests passed', total;
END $$;
ROLLBACK;
