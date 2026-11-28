-- ============================================================
-- SQL tests for customer address roles and Google verification (add_address_roles, fnd_customer_addresses,
-- fnd_address_validation): Bill to / Ship to move between addresses, a flagged address cannot be removed, a customer's
-- first address takes both roles, a department without addresses uses its account's, invoices/routes pick by role,
-- Google's answer verifies or suggests (keeping the typed delivery instructions), Accept/Reject, an edit clears the
-- verification, the Dashboard review counts. Staff only.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/customer_addresses_test.sql
-- Assumes the Alpine Bakery seed (tenant 200000000002, staff user 200000174045).
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t TO PUBLIC;
GRANT ALL ON _id TO PUBLIC;

INSERT INTO _t SELECT 'backfill: every customer with addresses has exactly one Bill to', NOT EXISTS (
  SELECT 1 FROM fnd_contacts k JOIN fnd_contact_points cp ON cp.contact_id = k.contact_id
   WHERE k.source_table = 'fnd_customers' AND k.is_active AND cp.type = 'ADDRESS' AND cp.is_active
   GROUP BY k.entity_id HAVING count(*) FILTER (WHERE cp.use_as_billing) <> 1);

DO $$
DECLARE a bigint; d bigint;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (200000000002, 'ZZ ADDR ACCOUNT', 'ACCOUNT') RETURNING customer_id INTO a;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id) VALUES (200000000002, 'Zz Addr Dept', 'DEPARTMENT', a) RETURNING customer_id INTO d;
  INSERT INTO _id VALUES ('a', a), ('d', d);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

DO $$
DECLARE a bigint; d bigint; p1 bigint; p2 bigint; g jsonb; ok boolean; vtxt text;
BEGIN
  SELECT v INTO a FROM _id WHERE k = 'a'; SELECT v INTO d FROM _id WHERE k = 'd';
  g := fnd_customer_addresses_get(200000000002, a);
  INSERT INTO _t VALUES ('no address yet: Bill to and Ship to are missing', (g ->> 'missing_bill')::boolean AND (g ->> 'missing_ship')::boolean);

  p1 := (fnd_customer_address_save(200000000002, a, NULL, E'  Zz Grand Hotel \n\n 700 Fifth Avenue\nNew York, NY 10019 ', ' Delivery entrance on 55th St ') ->> 'contact_point_id')::bigint;
  p2 := (fnd_customer_address_save(200000000002, a, NULL, E'PO Box 4410\nNewark, NJ 07101') ->> 'contact_point_id')::bigint;
  INSERT INTO _id VALUES ('p1', p1), ('p2', p2);
  INSERT INTO _t VALUES ('save: blank lines and spaces are tidied; instructions kept apart',
    (SELECT value = E'Zz Grand Hotel\n700 Fifth Avenue\nNew York, NY 10019' AND instructions = 'Delivery entrance on 55th St' FROM fnd_contact_points WHERE contact_point_id = p1));
  INSERT INTO _t VALUES ('save: the first address takes Bill to and Ship to, the second neither',
    (SELECT use_as_billing AND use_as_shipping FROM fnd_contact_points WHERE contact_point_id = p1)
    AND (SELECT NOT use_as_billing AND NOT use_as_shipping FROM fnd_contact_points WHERE contact_point_id = p2));

  PERFORM fnd_customer_address_action(200000000002, a, p2, 'BILL');
  INSERT INTO _t VALUES ('BILL moves Bill to; Ship to stays', (SELECT use_as_billing FROM fnd_contact_points WHERE contact_point_id = p2)
    AND (SELECT NOT use_as_billing AND use_as_shipping FROM fnd_contact_points WHERE contact_point_id = p1));
  INSERT INTO _t VALUES ('pick: invoices use Bill to, routes Ship to',
    fnd_customer_address_pick(200000000002, a, 'BILL') = p2 AND fnd_customer_address_pick(200000000002, a, 'SHIP') = p1
    AND om_customer_ship_address(200000000002, a) LIKE '%700 Fifth Avenue%');
  INSERT INTO _t VALUES ('department without addresses uses its account''s (pick and screen)',
    fnd_customer_address_pick(200000000002, d, 'BILL') = p2 AND fnd_customer_address_pick(200000000002, d, 'SHIP') = p1
    AND (fnd_customer_addresses_get(200000000002, d) -> 'inherited_from' ->> 'customer_id')::bigint = a);

  BEGIN
    PERFORM fnd_customer_address_action(200000000002, a, p1, 'REMOVE'); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'Move Bill to and Ship to%';
  END;
  INSERT INTO _t VALUES ('REMOVE is refused while the address is Bill to or Ship to', ok);
  BEGIN
    PERFORM fnd_customer_address_action(200000000002, d, p1, 'SHIP'); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'Address not found%';
  END;
  INSERT INTO _t VALUES ('a department cannot move its account''s roles', ok);
  BEGIN
    PERFORM fnd_customer_address_save(200000000002, a, p2, E'PO Box 4410\nNewark, NJ 07101', NULL, false); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'A customer needs a Billing address%';
  END;
  INSERT INTO _t VALUES ('card save: the only Billing address cannot be unticked', ok);

  -- Google: p1 found as typed (abbreviations, ZIP+4) → verified; p2 corrected → suggestion
  g := fnd_address_validation_save(200000000002, jsonb_build_array(
    jsonb_build_object('contact_point_id', p1, 'status', 'OK', 'granularity', 'PREMISE', 'street', '700 5TH AVE', 'city_line', 'NEW YORK NY 10019-0001'),
    jsonb_build_object('contact_point_id', p2, 'status', 'OK', 'granularity', 'PREMISE', 'street', 'PO BOX 4410', 'city_line', 'NEWARK NJ 07101-4410')));
  INSERT INTO _t VALUES ('validation: Fifth/5th differs → a suggestion keeping the name line, not verified',
    (SELECT NOT is_verified AND suggested_address = E'Zz Grand Hotel\n700 5TH AVE\nNEW YORK NY 10019-0001' FROM fnd_contact_points WHERE contact_point_id = p1));
  INSERT INTO _t VALUES ('validation: abbreviations, punctuation and ZIP+4 alone count as the same address → verified',
    (SELECT is_verified AND suggested_address IS NULL FROM fnd_contact_points WHERE contact_point_id = p2) AND (g ->> 'VERIFIED')::int = 1);
  INSERT INTO _t VALUES ('queue: checked addresses are not handed out again',
    jsonb_array_length(fnd_address_validation_queue_get(200000000002, 50, ARRAY[p1, p2])) = 0);

  PERFORM fnd_customer_address_action(200000000002, a, p1, 'ACCEPT');
  SELECT value INTO vtxt FROM fnd_contact_points WHERE contact_point_id = p1;
  INSERT INTO _t VALUES ('ACCEPT: the suggestion replaces the address, keeps the name line and instructions, and it stays verified',
    vtxt = E'Zz Grand Hotel\n700 5TH AVE\nNEW YORK NY 10019-0001'
    AND (SELECT instructions FROM fnd_contact_points WHERE contact_point_id = p1) = 'Delivery entrance on 55th St'
    AND (SELECT is_verified AND suggested_address IS NULL AND geocode_status = 'PENDING' FROM fnd_contact_points WHERE contact_point_id = p1));

  PERFORM fnd_customer_address_save(200000000002, a, p2, E'PO Box 4411\nNewark, NJ 07101');
  INSERT INTO _t VALUES ('an edit clears the verification and queues it for Google again',
    (SELECT NOT is_verified AND verified_at IS NULL FROM fnd_contact_points WHERE contact_point_id = p2)
    AND jsonb_array_length(fnd_address_validation_queue_get(200000000002, 50, ARRAY[p2])) = 1);
  PERFORM fnd_address_validation_save(200000000002, jsonb_build_array(jsonb_build_object('contact_point_id', p2, 'status', 'OK', 'granularity', 'OTHER')));
  INSERT INTO _t VALUES ('validation: an address Google cannot place is NOT_FOUND',
    (SELECT google_geocode_response -> 'validation' ->> 'status' FROM fnd_contact_points WHERE contact_point_id = p2) = 'NOT_FOUND');
  g := fnd_address_review_get(200000000002);
  INSERT INTO _t VALUES ('review: the customer is listed and counted', (g -> 'customer_ids') @> to_jsonb(a) AND (g ->> 'not_found')::int >= 1);
  PERFORM fnd_customer_address_save(200000000002, a, p2, E'PO Box 4411\nNewark, NJ 07101', NULL, true, NULL, true);
  INSERT INTO _t VALUES ('card save: Validated ticked by staff verifies it as typed', (SELECT is_verified FROM fnd_contact_points WHERE contact_point_id = p2));
  PERFORM fnd_customer_address_save(200000000002, a, p1, E'Zz Grand Hotel\n700 5TH AVE\nNEW YORK NY 10019-0001', 'Dock 2', NULL, false);
  INSERT INTO _t VALUES ('card save: unticking Shipping clears it; text unchanged keeps Validated',
    (SELECT NOT use_as_shipping AND is_verified AND instructions = 'Dock 2' FROM fnd_contact_points WHERE contact_point_id = p1));
  PERFORM fnd_customer_address_save(200000000002, a, p1, E'Zz Grand Hotel\n700 5TH AVE\nNEW YORK NY 10019-0001', 'Dock 2', NULL, true);
  INSERT INTO _t VALUES ('review: a verified customer with both roles drops off the list',
    NOT ((fnd_address_review_get(200000000002) -> 'customer_ids') @> to_jsonb(a)));
END $$;

SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002),
                    'restricted_tenant_ids', json_build_array(200000000002)))::text, true);
DO $$
BEGIN
  PERFORM fnd_customer_addresses_get(200000000002, (SELECT v FROM _id WHERE k = 'a'));
  INSERT INTO _t VALUES ('customer users cannot read or change customer addresses', FALSE);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO _t VALUES ('customer users cannot read or change customer addresses', SQLERRM LIKE 'Only tenant staff%');
END $$;

RESET ROLE;
SELECT CASE WHEN COALESCE(ok, false) THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT COALESCE(ok, false)), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % customer address tests failed', bad, total; END IF;
  RAISE NOTICE 'all % customer address tests passed', total;
END $$;
ROLLBACK;
