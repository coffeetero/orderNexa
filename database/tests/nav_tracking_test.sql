-- ============================================================
-- SQL tests for per-user navigation tracking (Quick Access + recent records).
-- Everything runs in ONE transaction that is ROLLED BACK, so no data is left behind.
-- Run against a LOCAL database only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/nav_tracking_test.sql
-- Fails loudly (non-zero exit) when an assertion does not hold.
-- ============================================================
BEGIN;
SET search_path = bps, public;

CREATE TEMP TABLE _t (name text, ok boolean);
GRANT ALL ON _t TO PUBLIC;

-- Fixtures (as superuser): a second tenant and two real users.
DO $$
DECLARE v_user_a bigint; v_user_b bigint; v_tenant_a bigint; v_tenant_x bigint;
BEGIN
  SELECT user_id, tenant_id INTO v_user_a, v_tenant_a FROM fnd_users WHERE user_type = 'TENANCY_USER' ORDER BY user_id LIMIT 1;
  SELECT user_id INTO v_user_b FROM fnd_users WHERE user_type = 'CUSTOMER_USER' ORDER BY user_id LIMIT 1;
  INSERT INTO fnd_tenants (tenant_name) VALUES ('__nav_test_tenant__') RETURNING tenant_id INTO v_tenant_x;
  PERFORM set_config('nav.user_a', v_user_a::text, true);
  PERFORM set_config('nav.user_b', v_user_b::text, true);
  PERFORM set_config('nav.tenant_a', v_tenant_a::text, true);
  PERFORM set_config('nav.tenant_x', v_tenant_x::text, true);
  -- Start from a clean slate for both users. This only affects this transaction (it is rolled back at the end),
  -- so real usage history is never touched; it just stops existing data from skewing the counts below.
  DELETE FROM fnd_user_menu_actions  WHERE user_id IN (v_user_a, v_user_b);
  DELETE FROM fnd_user_recent_records WHERE user_id IN (v_user_a, v_user_b);
  -- a row for user A in the OTHER tenant, planted as superuser
  INSERT INTO fnd_user_recent_records (user_id, tenant_id, record_type, record_key, label)
  VALUES (v_user_a, v_tenant_x, 'customer', '1', 'PLANTED in other tenant');
END $$;

-- ---------- act as user A (allowed: tenant A only) ----------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('app_user_id', current_setting('nav.user_a')::bigint,
                    'allowed_tenant_ids', json_build_array(current_setting('nav.tenant_a')::bigint)))::text, true);

DO $$
DECLARE ta bigint := current_setting('nav.tenant_a')::bigint; tx bigint := current_setting('nav.tenant_x')::bigint;
        r jsonb; n int; denied boolean;
BEGIN
  -- action usage counts
  PERFORM fnd_nav_touch(ta, '/orders'); PERFORM fnd_nav_touch(ta, '/orders'); PERFORM fnd_nav_touch(ta, '/customers');
  SELECT use_count INTO n FROM fnd_user_menu_actions WHERE action_key = '/orders';
  INSERT INTO _t VALUES ('action use_count increments', n = 2);

  -- pins: set, reorder, replace, limits
  PERFORM fnd_nav_pins_set(ARRAY['/customers','/orders']);
  r := fnd_nav_sidebar_get(ta);
  INSERT INTO _t VALUES ('pins keep order', (r->'actions'->0->>'action_key') = '/customers' AND (r->'actions'->0->>'pin_order') = '1'
                                          AND (r->'actions'->1->>'action_key') = '/orders'    AND (r->'actions'->1->>'pin_order') = '2');
  PERFORM fnd_nav_pins_set(ARRAY['/orders','/customers']);
  SELECT pin_order INTO n FROM fnd_user_menu_actions WHERE action_key = '/orders';
  INSERT INTO _t VALUES ('pins can be reordered', n = 1);
  SELECT use_count INTO n FROM fnd_user_menu_actions WHERE action_key = '/orders';
  INSERT INTO _t VALUES ('re-pinning preserves use_count', n = 2);
  BEGIN PERFORM fnd_nav_pins_set(ARRAY['/a','/b','/c','/d']); denied := false; EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('more than 3 pins rejected', denied);
  BEGIN PERFORM fnd_nav_pins_set(ARRAY['/a','/a']); denied := false; EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('duplicate pins rejected', denied);
  BEGIN PERFORM fnd_nav_touch(ta, 'not a path'); denied := false; EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('invalid action key rejected', denied);
  PERFORM fnd_nav_pins_set(ARRAY[]::text[]);
  SELECT count(*) INTO n FROM fnd_user_menu_actions WHERE is_pinned;
  INSERT INTO _t VALUES ('empty array unpins all', n = 0);

  -- recents: upsert + label refresh + count
  PERFORM fnd_nav_touch(ta, NULL, 'customer', '10700', '10700 · HOBOKEN', NULL);
  PERFORM fnd_nav_touch(ta, NULL, 'customer', '10700', '10700 · HOBOKEN BREAD DIST', NULL);
  SELECT access_count INTO n FROM fnd_user_recent_records WHERE tenant_id = ta AND record_key = '10700';
  INSERT INTO _t VALUES ('recent upsert increments access_count', n = 2);
  INSERT INTO _t VALUES ('recent label is refreshed',
    (SELECT label FROM fnd_user_recent_records WHERE tenant_id = ta AND record_key = '10700') = '10700 · HOBOKEN BREAD DIST');

  -- cap: 25 customers -> 20 kept, newest survive
  FOR n IN 1..25 LOOP PERFORM fnd_nav_touch(ta, NULL, 'customer', 'c' || n, 'Customer ' || n, NULL); PERFORM pg_sleep(0.002); END LOOP;
  SELECT count(*) INTO n FROM fnd_user_recent_records WHERE tenant_id = ta AND record_type = 'customer';
  INSERT INTO _t VALUES ('recents capped at 20 per type', n = 20);
  INSERT INTO _t VALUES ('newest recents survive the cap',
    EXISTS (SELECT 1 FROM fnd_user_recent_records WHERE tenant_id = ta AND record_key = 'c25')
    AND NOT EXISTS (SELECT 1 FROM fnd_user_recent_records WHERE tenant_id = ta AND record_key = 'c1'));
  PERFORM fnd_nav_touch(ta, NULL, 'order', '1', '0001 · Acme', 'Acme');
  PERFORM fnd_nav_touch(ta, NULL, 'item', '9', 'Baguette', NULL);

  -- sidebar_get: per-type limit and type filter
  r := fnd_nav_sidebar_get(ta, ARRAY['customer'], 5);
  INSERT INTO _t VALUES ('sidebar_get limits per type', jsonb_array_length(r->'recents') = 5);
  INSERT INTO _t VALUES ('sidebar_get filters types', NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'recents') e WHERE e->>'record_type' <> 'customer'));
  r := fnd_nav_sidebar_get(ta, ARRAY['order','item'], 5);
  INSERT INTO _t VALUES ('sidebar_get returns orders and items', jsonb_array_length(r->'recents') = 2);

  -- tenant isolation
  BEGIN PERFORM fnd_nav_touch(tx, NULL, 'customer', '2', 'x'); denied := false; EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('touch denied for a tenant not in the token', denied);
  BEGIN PERFORM fnd_nav_sidebar_get(tx); denied := false; EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('sidebar_get denied for a tenant not in the token', denied);
  SELECT count(*) INTO n FROM fnd_user_recent_records WHERE tenant_id = tx;
  INSERT INTO _t VALUES ('RLS hides own rows in a non-allowed tenant', n = 0);
  BEGIN INSERT INTO fnd_user_recent_records (user_id, tenant_id, record_type, record_key, label)
        VALUES (current_setting('nav.user_a')::bigint, tx, 'customer', '3', 'x'); denied := false;
  EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('RLS blocks direct insert into a non-allowed tenant', denied);
END $$;

-- ---------- act as user B (a different user, same tenant) ----------
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('app_user_id', current_setting('nav.user_b')::bigint,
                    'allowed_tenant_ids', json_build_array(current_setting('nav.tenant_a')::bigint)))::text, true);
DO $$
DECLARE ta bigint := current_setting('nav.tenant_a')::bigint; n int; r jsonb; denied boolean;
BEGIN
  SELECT count(*) INTO n FROM fnd_user_menu_actions;
  INSERT INTO _t VALUES ('user B cannot see user A menu actions', n = 0);
  SELECT count(*) INTO n FROM fnd_user_recent_records;
  INSERT INTO _t VALUES ('user B cannot see user A recents', n = 0);
  r := fnd_nav_sidebar_get(ta);
  INSERT INTO _t VALUES ('user B sidebar_get is empty', jsonb_array_length(r->'actions') = 0 AND jsonb_array_length(r->'recents') = 0);
  BEGIN INSERT INTO fnd_user_menu_actions (user_id, action_key) VALUES (current_setting('nav.user_a')::bigint, '/stolen'); denied := false;
  EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('user B cannot write rows for user A', denied);
  PERFORM fnd_nav_touch(ta, '/orders');
  SELECT count(*) INTO n FROM fnd_user_menu_actions WHERE action_key = '/orders' AND use_count = 1;
  INSERT INTO _t VALUES ('user B counts are independent of user A', n = 1);
END $$;

-- ---------- anonymous / no claims ----------
SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;
DO $$
DECLARE denied boolean;
BEGIN
  BEGIN PERFORM 1 FROM bps.fnd_user_recent_records LIMIT 1; denied := false; EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  INSERT INTO _t VALUES ('anon has no table access', denied);
  BEGIN PERFORM bps.fnd_nav_touch(1, '/orders'); denied := false; EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('anon cannot call fnd_nav_touch', denied);
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % nav tracking tests failed', bad, total; END IF;
  RAISE NOTICE 'all % nav tracking tests passed', total;
END $$;
ROLLBACK;
