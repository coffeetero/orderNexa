-- ============================================================
-- SQL tests for Organizer › Contacts: save (company and customer contacts), validation, list / get, favourites, tags,
-- notes timeline, delete vs deactivate, duplicates, merge, import preview / commit, export, access, and that the
-- customer screen functions (fnd_contacts_get / fnd_contacts_save) still work on the same rows.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/organizer_contacts_test.sql
-- Assumes the Alpine Bakery migration: staff user 200000174045 (Company Administrator), customer user 200000174046,
-- account FEATHERSTONE BAKING (15700). Creates staff user "zz contacts none" (no role) inside the transaction.
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _v (k text PRIMARY KEY, v text);
GRANT ALL ON _t, _v TO PUBLIC;

DO $$
DECLARE t bigint := 200000000002; u3 bigint;
BEGIN
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (t, 'aaaaaaaa-0000-4000-8000-0000000000c3', 'zz contacts none', 'TENANCY_USER') RETURNING user_id INTO u3;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (t, u3);
  INSERT INTO _v VALUES ('before', (SELECT count(*) FROM fnd_contacts WHERE tenant_id = t));
END $$;

CREATE TEMP TABLE _as (k text PRIMARY KEY, auth uuid);
GRANT ALL ON _as TO PUBLIC;
INSERT INTO _as VALUES ('one', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b'), ('none', 'aaaaaaaa-0000-4000-8000-0000000000c3'),
                       ('customer', '006f6c23-5efa-4f31-b0f3-b36ad4d587e7');

-- 1) staff administrator
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'one' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  t bigint := 200000000002; r jsonb; a bigint; b bigint; cc bigint; d boolean; tag bigint; p jsonb; imp jsonb;
  acc bigint := (SELECT customer_id FROM fnd_customers WHERE tenant_id = 200000000002 AND customer_number = '15700');
BEGIN
  -- company contact with the iPhone / Google style fields
  r := bps.org_contact_save(t, jsonb_build_object(
         'name_prefix', 'Dr.', 'first_name', 'Zz Ada', 'middle_name', 'M', 'last_name', 'Lovelace', 'nickname', 'Ada',
         'company_name', 'Analytical Engines', 'job_title', 'Engineer', 'is_favorite', true,
         'important_dates', jsonb_build_array(jsonb_build_object('label', 'Birthday', 'date', '1815-12-10'),
                                              jsonb_build_object('label', 'anniversary', 'date', '--06-01')),
         'related_people', jsonb_build_array(jsonb_build_object('label', 'parent', 'name', 'Lord Byron')),
         'photo_data', 'data:image/jpeg;base64,AAAA',
         'points', jsonb_build_array(
           jsonb_build_object('type', 'MOBILE', 'label', 'mobile', 'value', '(555) 010-1234', 'is_primary', true),
           jsonb_build_object('type', 'PHONE', 'label', 'work', 'value', '555 010 9999', 'is_primary', true),
           jsonb_build_object('type', 'EMAIL', 'label', 'work', 'value', 'zz.ada@example.test'),
           jsonb_build_object('type', 'ADDRESS', 'label', 'home', 'value', E'1 Main St\nLondon'),
           jsonb_build_object('type', 'WEBSITE', 'label', 'homepage', 'value', 'https://ada.example.test'),
           jsonb_build_object('type', 'OTHER', 'label', 'LinkedIn', 'value', 'ada-l'))));
  a := (r ->> 'contact_id')::bigint;
  INSERT INTO _v VALUES ('a', a);
  INSERT INTO _t VALUES ('a company contact belongs to the tenant',
    (SELECT source_table = 'fnd_tenants' AND entity_id = t AND contact_type = 'PERSON' FROM fnd_contacts WHERE contact_id = a) AND r ->> 'kind' = 'COMPANY');
  INSERT INTO _t VALUES ('full name uses prefix, middle name', r ->> 'full_name' = 'Dr. Zz Ada M Lovelace');
  INSERT INTO _t VALUES ('six contact points saved', jsonb_array_length(r -> 'points') = 6);
  INSERT INTO _t VALUES ('one primary per point type (MOBILE and PHONE each)',
    (SELECT count(*) FROM fnd_contact_points WHERE contact_id = a AND is_primary) = 2);
  INSERT INTO _t VALUES ('date labels are lower-cased, no-year dates kept',
    r -> 'important_dates' = '[{"label":"birthday","date":"1815-12-10"},{"label":"anniversary","date":"--06-01"}]'::jsonb);
  INSERT INTO _t VALUES ('card_name filled for a company contact', (SELECT card_name FROM fnd_contacts WHERE contact_id = a) = 'Zz Ada Lovelace');

  -- validation
  BEGIN PERFORM bps.org_contact_save(t, jsonb_build_object('job_title', 'x')); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Give the contact%'; END;
  INSERT INTO _t VALUES ('a contact needs a name or company', d);
  BEGIN PERFORM bps.org_contact_save(t, jsonb_build_object('first_name', 'x', 'points', jsonb_build_array(jsonb_build_object('type', 'EMAIL', 'value', 'nope')))); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE '%not an email%'; END;
  INSERT INTO _t VALUES ('a bad email is refused', d);
  BEGIN PERFORM bps.org_contact_save(t, jsonb_build_object('first_name', 'x', 'important_dates', jsonb_build_array(jsonb_build_object('date', '2020-02-31')))); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE '%not a valid date%'; END;
  INSERT INTO _t VALUES ('an impossible date is refused', d);
  BEGIN PERFORM bps.org_contact_save(t, jsonb_build_object('first_name', 'x', 'points', jsonb_build_array(jsonb_build_object('type', 'NOTE', 'value', 'x')))); d := false;
  EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('NOTE points cannot be added here', d);
  BEGIN PERFORM bps.org_contact_save(t, jsonb_build_object('first_name', 'x', 'photo_data', 'javascript:alert(1)')); d := false;
  EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a photo must be a data:image URL', d);

  -- update: drop a point, keep the photo when photo_data is not sent
  p := (bps.org_contact_get(t, a) -> 'points');
  r := bps.org_contact_save(t, jsonb_build_object('contact_id', a, 'first_name', 'Zz Ada', 'last_name', 'Lovelace', 'company_name', 'Analytical Engines',
         'points', (SELECT jsonb_agg(e) FROM jsonb_array_elements(p) e WHERE e ->> 'type' <> 'OTHER')));
  INSERT INTO _t VALUES ('a point left out is removed, ids kept for the rest', jsonb_array_length(r -> 'points') = 5
    AND (SELECT count(*) FROM fnd_contact_points WHERE contact_id = a) = 5
    AND (r -> 'points' -> 0 ->> 'contact_point_id') = (SELECT e ->> 'contact_point_id' FROM jsonb_array_elements(p) e WHERE e ->> 'type' = 'ADDRESS'));
  INSERT INTO _t VALUES ('photo kept when not sent', r ->> 'photo_data' = 'data:image/jpeg;base64,AAAA');
  INSERT INTO _t VALUES ('favourite is part of the save (cleared when sent false)', (r ->> 'is_favorite')::boolean = false);
  PERFORM bps.org_contact_favorite_set(t, a, true);
  INSERT INTO _t VALUES ('favourite toggle', (SELECT is_favorite FROM fnd_contacts WHERE contact_id = a));

  -- customer contact
  r := bps.org_contact_save(t, jsonb_build_object('customer_id', acc, 'first_name', 'Zz Bob', 'last_name', 'Baker', 'department', 'Receiving',
         'points', jsonb_build_array(jsonb_build_object('type', 'EMAIL', 'value', 'zz.bob@example.test', 'label', 'work'))));
  b := (r ->> 'contact_id')::bigint;
  INSERT INTO _v VALUES ('b', b);
  INSERT INTO _t VALUES ('a customer contact links to the customer', r ->> 'kind' = 'CUSTOMER' AND (r ->> 'customer_id')::bigint = acc
    AND (SELECT card_name FROM fnd_contacts WHERE contact_id = b) = 'Receiving');
  INSERT INTO _t VALUES ('the list shows company and customer contacts, not system rows',
    (SELECT count(*) FROM jsonb_array_elements(bps.org_contacts_get(t)) x WHERE (x ->> 'contact_id')::bigint IN (a, b)) = 2
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(bps.org_contacts_get(t)) x JOIN fnd_contacts c ON c.contact_id = (x ->> 'contact_id')::bigint
                     WHERE c.contact_type <> 'PERSON'));
  INSERT INTO _t VALUES ('list carries primary phone/email and search text',
    (SELECT x ->> 'phone' = '(555) 010-1234' AND x ->> 'email' = 'zz.ada@example.test' AND x ->> 'search' LIKE '%5550101234%'
       FROM jsonb_array_elements(bps.org_contacts_get(t)) x WHERE (x ->> 'contact_id')::bigint = a));

  -- tags
  tag := (bps.org_contact_tag_save(t, jsonb_build_object('tag_name', 'Zz Suppliers', 'tag_color', 'green')) ->> 'tag_id')::bigint;
  BEGIN PERFORM bps.org_contact_tag_save(t, jsonb_build_object('tag_name', 'zz suppliers')); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE '%already exists%'; END;
  INSERT INTO _t VALUES ('tag names are unique ignoring case', d);
  r := bps.org_contact_save(t, (bps.org_contact_get(t, b) - 'timeline') || jsonb_build_object('customer_id', acc, 'tag_ids', jsonb_build_array(tag)));
  INSERT INTO _t VALUES ('a tag is assigned through save', r -> 'tags' -> 0 ->> 'tag_name' = 'Zz Suppliers');
  INSERT INTO _t VALUES ('tags list counts contacts', (SELECT (x ->> 'contact_count')::int FROM jsonb_array_elements(bps.org_contact_tags_get(t)) x WHERE (x ->> 'tag_id')::bigint = tag) = 1);

  -- notes timeline
  PERFORM bps.org_contact_note_save(t, a, jsonb_build_object('note_text', 'Called about the order'));
  PERFORM bps.org_contact_note_save(t, a, jsonb_build_object('note_text', 'Pinned fact', 'is_pinned', true));
  r := bps.org_contact_get(t, a);
  INSERT INTO _t VALUES ('timeline lists notes, pinned first', jsonb_array_length(r -> 'timeline') = 2 AND r -> 'timeline' -> 0 ->> 'note_text' = 'Pinned fact');
  PERFORM bps.org_contact_note_delete(t, (r -> 'timeline' -> 1 ->> 'note_id')::bigint);
  INSERT INTO _t VALUES ('a note can be removed', jsonb_array_length(bps.org_contact_get(t, a) -> 'timeline') = 1);

  -- duplicates and merge
  cc := (bps.org_contact_save(t, jsonb_build_object('first_name', 'zz ada', 'last_name', 'LOVELACE', 'job_title', 'Countess',
          'points', jsonb_build_array(jsonb_build_object('type', 'PHONE', 'value', '+1 555-010-1234'),
                                      jsonb_build_object('type', 'EMAIL', 'value', 'ada.home@example.test')))) ->> 'contact_id')::bigint;
  PERFORM bps.org_contact_note_save(t, cc, jsonb_build_object('note_text', 'From the duplicate'));
  INSERT INTO _t VALUES ('duplicates found by name and phone',
    (SELECT count(*) FROM jsonb_array_elements(bps.org_contact_duplicates_get(t)) g
      WHERE g -> 'contacts' @> jsonb_build_array(jsonb_build_object('contact_id', a)) AND g -> 'contacts' @> jsonb_build_array(jsonb_build_object('contact_id', cc))) = 2);
  BEGIN PERFORM bps.org_contact_merge(t, a, b); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'This contact belongs to a customer%'; END;
  INSERT INTO _t VALUES ('a customer contact cannot be merged into a company contact', d);
  r := bps.org_contact_merge(t, a, cc);
  INSERT INTO _t VALUES ('merge removes the duplicate', NOT EXISTS (SELECT 1 FROM fnd_contacts WHERE contact_id = cc));
  INSERT INTO _t VALUES ('merge keeps own values, fills blanks, adds new points only', r ->> 'first_name' = 'Zz Ada'
    AND r ->> 'job_title' = 'Countess' AND jsonb_array_length(r -> 'points') = 6);
  INSERT INTO _t VALUES ('merge moves timeline notes', jsonb_array_length(bps.org_contact_get(t, a) -> 'timeline') = 2);

  -- import preview / commit
  imp := jsonb_build_array(
    jsonb_build_object('first_name', 'Zz New', 'last_name', 'Person', 'tag_names', jsonb_build_array('Zz Imported'),
                       'points', jsonb_build_array(jsonb_build_object('type', 'EMAIL', 'value', 'zz.new@example.test'))),
    jsonb_build_object('first_name', 'Other', 'points', jsonb_build_array(jsonb_build_object('type', 'EMAIL', 'value', 'ZZ.ADA@example.test'))),
    jsonb_build_object('job_title', 'nameless'),
    jsonb_build_object('first_name', 'Zz New', 'last_name', 'Person'));
  r := bps.org_contacts_import(t, imp, false);
  INSERT INTO _t VALUES ('import preview: new, duplicate (email, then same file), invalid',
    (r ->> 'new')::int = 1 AND (r ->> 'duplicate')::int = 2 AND (r ->> 'invalid')::int = 1
    AND r -> 'rows' -> 1 ->> 'status' = 'DUPLICATE' AND r -> 'rows' -> 3 ->> 'status' = 'DUPLICATE');
  INSERT INTO _t VALUES ('import preview keeps nothing', NOT EXISTS (SELECT 1 FROM fnd_contacts WHERE tenant_id = t AND first_name = 'Zz New')
    AND NOT EXISTS (SELECT 1 FROM fnd_contact_tags WHERE tenant_id = t AND tag_name = 'Zz Imported'));
  r := bps.org_contacts_import(t, imp, true);
  INSERT INTO _t VALUES ('import commit creates the new row with its tag', (r ->> 'new')::int = 1
    AND (SELECT count(*) FROM fnd_contacts c JOIN fnd_contact_tag_links l USING (contact_id) JOIN fnd_contact_tags g USING (tag_id)
          WHERE c.tenant_id = t AND c.first_name = 'Zz New' AND g.tag_name = 'Zz Imported' AND c.source_table = 'fnd_tenants') = 1);

  -- export
  INSERT INTO _t VALUES ('export of chosen ids, without photos',
    (SELECT count(*) = 2 AND bool_and(x -> 'photo_data' = 'null'::jsonb) FROM jsonb_array_elements(bps.org_contacts_export(t, ARRAY[a, b])) x));

  -- delete: a contact with notes is deactivated, one without is deleted
  r := bps.org_contact_delete(t, a);
  INSERT INTO _t VALUES ('delete with notes deactivates', r ->> 'result' = 'DEACTIVATED' AND NOT (SELECT is_active FROM fnd_contacts WHERE contact_id = a)
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(bps.org_contacts_get(t)) x WHERE (x ->> 'contact_id')::bigint = a));
  r := bps.org_contact_delete(t, (SELECT contact_id FROM fnd_contacts WHERE tenant_id = t AND first_name = 'Zz New'));
  INSERT INTO _t VALUES ('delete without notes removes the row', r ->> 'result' = 'DELETED');
  PERFORM bps.org_contact_tag_delete(t, tag);
  INSERT INTO _t VALUES ('tag delete removes its links', NOT EXISTS (SELECT 1 FROM fnd_contact_tag_links WHERE tag_id = tag));
END $$;

-- 2) the customer screen functions on the same customer contact
DO $$
DECLARE
  t bigint := 200000000002; b bigint := (SELECT v FROM _v WHERE k = 'b'); g jsonb; c jsonb;
  acc bigint := (SELECT customer_id FROM fnd_customers WHERE tenant_id = 200000000002 AND customer_number = '15700');
BEGIN
  UPDATE fnd_contacts SET is_favorite = true, nickname = 'Bobby' WHERE contact_id = b;
  g := bps.fnd_contacts_get(t, acc, 'fnd_customers');
  c := (SELECT x FROM jsonb_array_elements(g) x WHERE (x ->> 'contact_id')::bigint = b);
  INSERT INTO _t VALUES ('customer screen lists the contact made in Organizer', c IS NOT NULL AND c ->> 'card_name' = 'Receiving'
    AND jsonb_array_length(c -> 'contact_points') = 1);
  INSERT INTO _t VALUES ('customer screen still lists its system rows', (SELECT count(*) FROM jsonb_array_elements(g) x WHERE x ->> 'contact_type' <> 'PERSON') >= 1);
  PERFORM bps.fnd_contacts_save(t, acc, 'fnd_customers', c || jsonb_build_object('job_title', 'Manager'));
  INSERT INTO _t VALUES ('customer screen save keeps the Organizer fields',
    (SELECT is_favorite AND nickname = 'Bobby' AND job_title = 'Manager' FROM fnd_contacts WHERE contact_id = b));
END $$;

-- 3) a staff user without Contacts access, and a customer user
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'none' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE t bigint := 200000000002; d boolean; b bigint := (SELECT v FROM _v WHERE k = 'b');
BEGIN
  BEGIN PERFORM bps.org_contacts_get(t); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'You do not have access%'; END;
  INSERT INTO _t VALUES ('no Contacts access: cannot list', d);
  BEGIN PERFORM bps.org_contact_save(t, jsonb_build_object('first_name', 'x')); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('no Contacts access: cannot save', d);
  INSERT INTO _t VALUES ('no Contacts access: tags hidden by row security', (SELECT count(*) FROM fnd_contact_tags) = 0);
  BEGIN PERFORM bps.org_contact_check(t, b, 'R'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('app users cannot call the internal check', d);
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'customer' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$ DECLARE t bigint := 200000000002; d boolean; BEGIN
  BEGIN PERFORM bps.org_contacts_get(t); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('a customer user cannot open the address book', d);
END $$;

RESET ROLE;
DO $$ BEGIN
  INSERT INTO _t VALUES ('only test rows were added', (SELECT count(*) FROM fnd_contacts WHERE tenant_id = 200000000002 AND lower(COALESCE(first_name, '')) NOT LIKE 'zz%')
                                                     = (SELECT v::bigint FROM _v WHERE k = 'before'));
END $$;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok OR ok IS NULL), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % contacts tests failed', bad, total; END IF;
  RAISE NOTICE 'all % contacts tests passed', total;
END $$;
ROLLBACK;
