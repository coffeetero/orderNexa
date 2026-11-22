-- ============================================================
-- SQL tests for fnd_user_preferences (isolation, validation, upsert). One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/user_preferences_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
GRANT ALL ON _t TO PUBLIC;

DO $$
DECLARE v_a bigint; v_b bigint; v_tenant bigint;
BEGIN
  SELECT user_id, tenant_id INTO v_a, v_tenant FROM fnd_users WHERE user_type = 'TENANCY_USER' ORDER BY user_id LIMIT 1;
  SELECT user_id INTO v_b FROM fnd_users WHERE user_type = 'CUSTOMER_USER' ORDER BY user_id LIMIT 1;
  PERFORM set_config('pref.user_a', v_a::text, true);
  PERFORM set_config('pref.user_b', v_b::text, true);
  -- clean slate for these users, inside this rolled-back transaction only
  DELETE FROM fnd_user_preferences WHERE user_id IN (v_a, v_b);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('app_user_id', current_setting('pref.user_a')::bigint))::text, true);

DO $$
DECLARE r jsonb; n int; denied boolean;
BEGIN
  r := fnd_user_preferences_get();
  INSERT INTO _t VALUES ('get returns empty appearance when never saved', r->'appearance' = '{}'::jsonb);

  PERFORM fnd_user_preferences_save('{"mode":"dark","themeId":"clay"}'::jsonb);
  r := fnd_user_preferences_get();
  INSERT INTO _t VALUES ('save then get round-trips', r->'appearance'->>'themeId' = 'clay' AND r->'appearance'->>'mode' = 'dark');

  PERFORM fnd_user_preferences_save('{"mode":"light","themeId":"sepia"}'::jsonb);
  SELECT count(*) INTO n FROM fnd_user_preferences;
  INSERT INTO _t VALUES ('second save updates the same row', n = 1 AND (fnd_user_preferences_get()->'appearance'->>'themeId') = 'sepia');
  INSERT INTO _t VALUES ('audit columns are set', (SELECT created_by = updated_by AND created_by = current_setting('pref.user_a')::bigint FROM fnd_user_preferences LIMIT 1));

  BEGIN PERFORM fnd_user_preferences_save('[1,2]'::jsonb); denied := false; EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('non-object appearance rejected', denied);
  BEGIN PERFORM fnd_user_preferences_save(NULL); denied := false; EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('null appearance rejected', denied);
  BEGIN PERFORM fnd_user_preferences_save(jsonb_build_object('x', repeat('a', 70000))); denied := false; EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('oversized appearance rejected', denied);
END $$;

-- another user cannot see or change it
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('app_user_id', current_setting('pref.user_b')::bigint))::text, true);
DO $$
DECLARE n int; denied boolean;
BEGIN
  SELECT count(*) INTO n FROM fnd_user_preferences;
  INSERT INTO _t VALUES ('user B cannot see user A preferences', n = 0);
  INSERT INTO _t VALUES ('user B get is empty', fnd_user_preferences_get()->'appearance' = '{}'::jsonb);
  BEGIN INSERT INTO fnd_user_preferences (user_id, appearance) VALUES (current_setting('pref.user_a')::bigint, '{}'); denied := false;
  EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('user B cannot write a row for user A', denied);
  PERFORM fnd_user_preferences_save('{"mode":"system","themeId":"ocean"}'::jsonb);
  INSERT INTO _t VALUES ('user B saves independently', (SELECT count(*) FROM fnd_user_preferences) = 1);
END $$;

-- anonymous
SELECT set_config('request.jwt.claims', '', true);
SET LOCAL ROLE anon;
DO $$
DECLARE denied boolean;
BEGIN
  BEGIN PERFORM 1 FROM bps.fnd_user_preferences LIMIT 1; denied := false; EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  INSERT INTO _t VALUES ('anon has no table access', denied);
  BEGIN PERFORM bps.fnd_user_preferences_get(); denied := false; EXCEPTION WHEN OTHERS THEN denied := true; END;
  INSERT INTO _t VALUES ('anon cannot call get', denied);
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % preference tests failed', bad, total; END IF;
  RAISE NOTICE 'all % preference tests passed', total;
END $$;
ROLLBACK;
