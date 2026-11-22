-- ============================================================
-- SQL tests for the active tenancy (token hook, picker list, select). One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q < database/tests/active_tenancy_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
GRANT ALL ON _t TO PUBLIC;

DO $$
DECLARE t2 bigint; uOne bigint; uTwo bigint; aOne uuid := gen_random_uuid(); aTwo uuid := gen_random_uuid();
  s1 uuid := gen_random_uuid(); s2 uuid := gen_random_uuid(); ev jsonb; c jsonb; n int; r boolean;
BEGIN
  INSERT INTO fnd_tenants (tenant_name, tenant_slug) VALUES ('zz login tenant', 'zz-login') RETURNING tenant_id INTO t2;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, aOne, 'zz one', 'TENANCY_USER') RETURNING user_id INTO uOne;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, aTwo, 'zz two', 'TENANCY_USER') RETURNING user_id INTO uTwo;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (200000000002, uOne), (200000000002, uTwo), (t2, uTwo);

  -- single tenancy: selected automatically
  ev := bps.bps_access_token_hook(jsonb_build_object('user_id', aOne, 'claims', jsonb_build_object('session_id', s1, 'app_metadata', '{}'::jsonb)));
  c := ev->'claims'->'app_metadata';
  INSERT INTO _t VALUES ('single tenancy: tenant_id claim set automatically', (c->>'tenant_id')::bigint = 200000000002 AND c->>'tenant_slug' = 'alpine-bakery');
  INSERT INTO _t VALUES ('claim keeps app_user_id', (c->>'app_user_id')::bigint = uOne);

  -- two tenancies, nothing chosen: no tenant_id claim
  ev := bps.bps_access_token_hook(jsonb_build_object('user_id', aTwo, 'claims', jsonb_build_object('session_id', s2, 'app_metadata', '{"tenant_id": 999}'::jsonb)));
  c := ev->'claims'->'app_metadata';
  INSERT INTO _t VALUES ('two tenancies, none chosen: no tenant_id (and a stale one is stripped)', NOT (c ? 'tenant_id') AND jsonb_array_length(c->'allowed_tenant_ids') = 2);

  -- choose via the function as the signed-in user
  PERFORM set_config('request.jwt.claims', jsonb_build_object('role','authenticated','session_id', s2, 'app_metadata', jsonb_build_object('app_user_id', uTwo))::text, true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM fnd_user_tenancies_get();
  INSERT INTO _t VALUES ('picker lists both tenancies', n = 2);
  BEGIN PERFORM fnd_user_select_tenant(200000000002, 'zz-login'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('selecting a tenant on another tenant''s host is refused', r);
  PERFORM fnd_user_select_tenant(t2, 'zz-login');
  RESET ROLE;
  ev := bps.bps_access_token_hook(jsonb_build_object('user_id', aTwo, 'claims', jsonb_build_object('session_id', s2, 'app_metadata', '{}'::jsonb)));
  INSERT INTO _t VALUES ('after choosing, the claim follows the session', (ev->'claims'->'app_metadata'->>'tenant_id')::bigint = t2);
  ev := bps.bps_access_token_hook(jsonb_build_object('user_id', aTwo, 'claims', jsonb_build_object('session_id', gen_random_uuid(), 'app_metadata', '{}'::jsonb)));
  INSERT INTO _t VALUES ('another session of the same user is NOT affected (multi-tab / multi-browser safe)', NOT (ev->'claims'->'app_metadata' ? 'tenant_id'));

  -- not a member
  PERFORM set_config('request.jwt.claims', jsonb_build_object('role','authenticated','session_id', s1, 'app_metadata', jsonb_build_object('app_user_id', uOne))::text, true);
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM fnd_user_select_tenant(t2); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('cannot select a tenancy the user does not belong to', r);
  RESET ROLE;
  -- someone else's session row cannot be hijacked
  PERFORM set_config('request.jwt.claims', jsonb_build_object('role','authenticated','session_id', s2, 'app_metadata', jsonb_build_object('app_user_id', uOne))::text, true);
  SET LOCAL ROLE authenticated;
  PERFORM fnd_user_select_tenant(200000000002);
  RESET ROLE;
  INSERT INTO _t VALUES ('an existing session row of another user is not overwritten',
     (SELECT tenant_id FROM fnd_user_active_tenant WHERE auth_session_id = s2) = t2);

  -- a deactivated membership drops out of the claim
  UPDATE fnd_user_tenants SET is_active = false WHERE user_id = uTwo AND tenant_id = t2;
  ev := bps.bps_access_token_hook(jsonb_build_object('user_id', aTwo, 'claims', jsonb_build_object('session_id', s2, 'app_metadata', '{}'::jsonb)));
  INSERT INTO _t VALUES ('losing a membership removes it from the session on next refresh', (ev->'claims'->'app_metadata'->>'tenant_id')::bigint = 200000000002);
  -- unknown auth user
  ev := bps.bps_access_token_hook(jsonb_build_object('user_id', gen_random_uuid(), 'claims', jsonb_build_object('app_metadata', '{}'::jsonb)));
  INSERT INTO _t VALUES ('unknown user: no tenant, empty lists', NOT (ev->'claims'->'app_metadata' ? 'tenant_id') AND jsonb_array_length(ev->'claims'->'app_metadata'->'allowed_tenant_ids') = 0);
END $$;

SELECT name, CASE WHEN ok THEN 'ok' ELSE 'FAIL' END AS result FROM _t WHERE NOT ok;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM _t;
ROLLBACK;
