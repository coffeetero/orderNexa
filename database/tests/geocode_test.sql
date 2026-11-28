-- ============================================================
-- SQL tests for address geocoding (fnd_geocode_queue_get / fnd_geocode_save) and the map point of a ship-to
-- (om_customer_ship_point, used by om_route_stops_get): a new address is queued, a saved result stores coordinates, a
-- changed address is queued again, not-found results stop being handed out, failures retry at most 3 times. Staff only.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/geocode_test.sql
-- Assumes the Alpine Bakery seed (tenant 200000000002, staff user 200000174045).
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t TO PUBLIC;
GRANT ALL ON _id TO PUBLIC;

DO $$
DECLARE c bigint; ct bigint; cp bigint; cp2 bigint;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (200000000002, 'ZZ GEO ACCOUNT', 'ACCOUNT') RETURNING customer_id INTO c;
  INSERT INTO fnd_contacts (tenant_id, entity_id, source_table, card_name, contact_type, is_active)
    VALUES (200000000002, c, 'fnd_customers', 'Billing & Shipping', 'ADDRESSES', TRUE) RETURNING contact_id INTO ct;
  INSERT INTO fnd_contact_points (tenant_id, contact_id, type, value, is_primary, is_active, use_as_shipping)
    VALUES (200000000002, ct, 'ADDRESS', E'1 Test Street\nHoboken, NJ 07030', TRUE, TRUE, TRUE) RETURNING contact_point_id INTO cp;
  INSERT INTO fnd_contact_points (tenant_id, contact_id, type, value, is_active, geocode_status)
    VALUES (200000000002, ct, 'ADDRESS', E'Nowhere 9\nAtlantis', TRUE, 'PENDING') RETURNING contact_point_id INTO cp2;
  INSERT INTO _id VALUES ('c', c), ('cp', cp), ('cp2', cp2);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

DO $$
DECLARE c bigint; cp bigint; cp2 bigint; q jsonb; p jsonb; i int;
BEGIN
  SELECT v INTO c FROM _id WHERE k = 'c'; SELECT v INTO cp FROM _id WHERE k = 'cp'; SELECT v INTO cp2 FROM _id WHERE k = 'cp2';
  q := fnd_geocode_queue_get(200000000002, 50, ARRAY[cp, cp2]);
  INSERT INTO _t VALUES ('queue: new addresses are handed out with their text', jsonb_array_length(q) = 2
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(q) e WHERE (e->>'contact_point_id')::bigint = cp AND e->>'address' LIKE '1 Test Street%'));

  PERFORM fnd_geocode_save(200000000002, jsonb_build_array(
    jsonb_build_object('contact_point_id', cp, 'status', 'OK', 'latitude', 40.7440, 'longitude', -74.0324, 'formatted_address', '1 Test St, Hoboken, NJ 07030, USA', 'place_id', 'test-place'),
    jsonb_build_object('contact_point_id', cp2, 'status', 'ZERO_RESULTS')));
  p := om_customer_ship_point(200000000002, c);
  INSERT INTO _t VALUES ('save: coordinates stored; the ship point carries them',
    p->>'geocode_status' = 'OK' AND (p->>'latitude')::numeric = 40.7440 AND (p->>'longitude')::numeric = -74.0324 AND (p->>'contact_point_id')::bigint = cp);
  INSERT INTO _t VALUES ('save: an address Google cannot find is not handed out again',
    jsonb_array_length(fnd_geocode_queue_get(200000000002, 50, ARRAY[cp2])) = 0);

  UPDATE fnd_contact_points SET value = E'2 Test Street\nHoboken, NJ 07030' WHERE contact_point_id = cp;
  INSERT INTO _t VALUES ('a changed address is queued again', jsonb_array_length(fnd_geocode_queue_get(200000000002, 50, ARRAY[cp])) = 1);

  FOR i IN 1..3 LOOP PERFORM fnd_geocode_save(200000000002, jsonb_build_array(jsonb_build_object('contact_point_id', cp, 'status', 'FAILED'))); END LOOP;
  INSERT INTO _t VALUES ('failures are retried at most 3 times', jsonb_array_length(fnd_geocode_queue_get(200000000002, 50, ARRAY[cp])) = 0);
END $$;

SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002),
                    'restricted_tenant_ids', json_build_array(200000000002)))::text, true);
DO $$
BEGIN
  PERFORM fnd_geocode_queue_get(200000000002, 10, NULL);
  INSERT INTO _t VALUES ('customer users cannot read the address queue', FALSE);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO _t VALUES ('customer users cannot read the address queue', SQLERRM LIKE 'Only tenant staff%');
END $$;

RESET ROLE;
SELECT CASE WHEN COALESCE(ok, false) THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT COALESCE(ok, false)), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % geocode tests failed', bad, total; END IF;
  RAISE NOTICE 'all % geocode tests passed', total;
END $$;
ROLLBACK;
