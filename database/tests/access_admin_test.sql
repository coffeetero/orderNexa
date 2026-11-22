-- ============================================================
-- SQL tests for the access administration functions (roles, users, groups, numbers). One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q < database/tests/access_admin_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _ids (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t, _ids TO PUBLIC;

DO $$
DECLARE uClerk bigint; uTarget bigint; r_clerk bigint;
BEGIN
  INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'zz clerk', 'TENANT') RETURNING role_id INTO r_clerk;
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write) VALUES (200000000002, r_clerk, 'orders.enter', true, true);
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz clerk', 'TENANCY_USER') RETURNING user_id INTO uClerk;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz target', 'TENANCY_USER') RETURNING user_id INTO uTarget;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (200000000002, uClerk), (200000000002, uTarget);
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uClerk, r_clerk);
  INSERT INTO _ids VALUES ('uClerk', uClerk), ('uTarget', uTarget), ('r_clerk', r_clerk);
END $$;

-- ── tenant administrator (existing seeded staff user) ────────────────────────
DO $$
DECLARE v_role bigint; v_group bigint; v_num bigint; j jsonb; r boolean; uTarget bigint := (SELECT v FROM _ids WHERE k='uTarget'); n int;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":200000174045}}', true);
  SET LOCAL ROLE authenticated;

  INSERT INTO _t VALUES ('tenant administrator areas include every admin area', (SELECT count(*) FROM unnest(fnd_my_areas()) a WHERE a LIKE 'admin.%') = 7);
  -- roles
  j := fnd_roles_get(200000000002);
  INSERT INTO _t VALUES ('roles list shows both system roles', (SELECT count(*) FROM jsonb_array_elements(j) e WHERE (e->>'is_system')::boolean) = 2);
  v_role := fnd_role_save(200000000002, jsonb_build_object('role_name','zz Baker','role_audience','TENANT','is_active',true,
     'access', jsonb_build_array(jsonb_build_object('area_key','production.report','can_read',true,'can_write',false),
                                  jsonb_build_object('area_key','production.labels','can_write',true))));
  INSERT INTO _t VALUES ('role created with access rows; a write flag implies read',
     (SELECT count(*) FROM fnd_role_area_access WHERE role_id = v_role) = 2
     AND (SELECT can_read FROM fnd_role_area_access WHERE role_id = v_role AND area_key = 'production.labels'));
  j := fnd_role_access_get(200000000002, v_role);
  INSERT INTO _t VALUES ('access matrix returns every tenant area with the flags',
     jsonb_array_length(j) = (SELECT count(*) FROM fnd_areas WHERE audience = 'TENANT')
     AND (SELECT (e->>'can_write')::boolean FROM jsonb_array_elements(j) e WHERE e->>'area_key' = 'production.labels'));
  INSERT INTO _t VALUES ('a new customer-role matrix lists only customer areas',
     (SELECT bool_and(e->>'area_key' LIKE 'portal.%') FROM jsonb_array_elements(fnd_role_access_get(200000000002, NULL, 'CUSTOMER')) e));
  PERFORM fnd_role_save(200000000002, jsonb_build_object('role_id', v_role, 'role_name','zz Baker 2','is_active',true,
     'access', jsonb_build_array(jsonb_build_object('area_key','production.report','can_read',true))));
  INSERT INTO _t VALUES ('saving again replaces the access rows and renames',
     (SELECT count(*) FROM fnd_role_area_access WHERE role_id = v_role) = 1 AND (SELECT role_name FROM fnd_roles WHERE role_id = v_role) = 'zz Baker 2');
  BEGIN PERFORM fnd_role_save(200000000002, jsonb_build_object('role_id', (SELECT role_id FROM fnd_roles WHERE tenant_id = 200000000002 AND is_system LIMIT 1), 'role_name','x')); r := false;
  EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('system roles cannot be edited', r);
  BEGIN PERFORM fnd_role_save(200000000002, '{"role_name":""}'::jsonb); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a role needs a name', r);
  BEGIN PERFORM fnd_role_delete(200000000002, (SELECT role_id FROM fnd_roles WHERE tenant_id = 200000000002 AND is_system LIMIT 1)); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('system roles cannot be deleted', r);

  -- users
  j := fnd_users_get(200000000002);
  INSERT INTO _t VALUES ('users list includes the test users with their role ids', jsonb_array_length(j) >= 4
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(j) e WHERE e->>'user_name' = 'zz clerk' AND jsonb_array_length(e->'role_ids') = 1));
  v_group := fnd_customer_group_save(200000000002, jsonb_build_object('group_name','zz Group','customer_ids', jsonb_build_array(200000000158)));
  PERFORM fnd_user_access_save(200000000002, uTarget, ARRAY[v_role], ARRAY[v_group], true);
  INSERT INTO _t VALUES ('user access save sets role and group',
     EXISTS (SELECT 1 FROM fnd_user_roles WHERE user_id = uTarget AND role_id = v_role) AND EXISTS (SELECT 1 FROM fnd_user_customer_groups WHERE user_id = uTarget AND group_id = v_group));
  PERFORM fnd_user_access_save(200000000002, uTarget, ARRAY[]::bigint[], ARRAY[]::bigint[], false);
  INSERT INTO _t VALUES ('saving empty lists clears them and deactivates the membership',
     NOT EXISTS (SELECT 1 FROM fnd_user_roles WHERE user_id = uTarget) AND NOT (SELECT is_active FROM fnd_user_tenants WHERE user_id = uTarget AND tenant_id = 200000000002));
  BEGIN PERFORM fnd_user_access_save(200000000002, uTarget, ARRAY[(SELECT role_id FROM fnd_roles WHERE tenant_id = 200000000002 AND role_audience = 'CUSTOMER' AND is_system)], NULL, true); r := false;
  EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a customer role cannot be given to a tenant user', r);
  BEGIN PERFORM fnd_user_access_save(200000000002, 200000174045, ARRAY[]::bigint[], ARRAY[]::bigint[], true); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('an administrator cannot change their own access', r);

  -- groups
  j := fnd_customer_groups_get(200000000002);
  INSERT INTO _t VALUES ('groups list has All Customers first and the new group with its effective customers',
     (j->0->>'is_all_customers')::boolean AND EXISTS (SELECT 1 FROM jsonb_array_elements(j) e WHERE e->>'group_name' = 'zz Group' AND (e->>'effective_count')::int >= 1));
  PERFORM fnd_customer_group_save(200000000002, jsonb_build_object('group_id', v_group, 'group_name','zz Group','customer_ids', jsonb_build_array(200000000685, 200000000106)));
  INSERT INTO _t VALUES ('group members are replaced', (SELECT array_agg(customer_id ORDER BY customer_id) FROM fnd_customer_group_members WHERE group_id = v_group) = ARRAY[200000000106::bigint, 200000000685]);
  BEGIN PERFORM fnd_customer_group_save(200000000002, jsonb_build_object('group_id', (SELECT group_id FROM fnd_customer_groups WHERE tenant_id = 200000000002 AND is_all_customers), 'group_name','x')); r := false;
  EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('the All Customers group cannot be edited', r);
  INSERT INTO _t VALUES ('customer picker lists top-level customers', jsonb_array_length(fnd_customer_options_get(200000000002)) > 50);
  PERFORM fnd_customer_group_delete(200000000002, v_group);
  INSERT INTO _t VALUES ('group deleted', NOT EXISTS (SELECT 1 FROM fnd_customer_groups WHERE group_id = v_group));

  -- numbers
  v_num := fnd_phone_number_save(200000000002, '{"phone_number":"(555) 123-4567 99","channel":"whatsapp","label":"Main"}'::jsonb);
  INSERT INTO _t VALUES ('number stored as E.164 with the channel upper-cased', (SELECT phone_number || channel FROM fnd_tenant_phone_numbers WHERE phone_number_id = v_num) = '+555123456799WHATSAPP');
  BEGIN PERFORM fnd_phone_number_save(200000000002, '{"phone_number":"12"}'::jsonb); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a too-short number is refused', r);
  BEGIN PERFORM fnd_phone_number_save(200000000002, '{"phone_number":"+555 123 4567 99","channel":"WHATSAPP"}'::jsonb); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('the same number and channel cannot be added twice', r);
  PERFORM fnd_phone_number_delete(200000000002, v_num);
  INSERT INTO _t VALUES ('number deleted', jsonb_array_length(fnd_phone_numbers_get(200000000002)) = 0);
  BEGIN PERFORM fnd_role_save(999, '{"role_name":"x"}'::jsonb); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('another tenant id is refused', r);
  RESET ROLE;
END $$;

-- ── tenant roles and customer roles are separate areas (support can see one without the other) ──
DO $$
DECLARE uT bigint; uC bigint; rT bigint; rC bigint; n int; r boolean;
BEGIN
  INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'zz tenant-roles only', 'TENANT') RETURNING role_id INTO rT;
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write, can_delete) VALUES (200000000002, rT, 'admin.roles', true, true, true);
  INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'zz customer-roles only', 'TENANT') RETURNING role_id INTO rC;
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write, can_delete) VALUES (200000000002, rC, 'admin.customer-roles', true, true, true);
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz tr', 'TENANCY_USER') RETURNING user_id INTO uT;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz cr', 'TENANCY_USER') RETURNING user_id INTO uC;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (200000000002, uT), (200000000002, uC);
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uT, rT), (200000000002, uC, rC);

  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', uT), true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM fnd_roles WHERE role_audience = 'CUSTOMER'; INSERT INTO _t VALUES ('tenant-roles user sees no customer roles', n = 0);
  SELECT count(*) INTO n FROM fnd_roles WHERE role_audience = 'TENANT'; INSERT INTO _t VALUES ('...but sees tenant roles', n > 0);
  BEGIN PERFORM fnd_role_save(200000000002, '{"role_name":"zz sneaky","role_audience":"CUSTOMER"}'::jsonb); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('...and cannot create a customer role', r);
  PERFORM fnd_role_save(200000000002, '{"role_name":"zz made by tr","role_audience":"TENANT"}'::jsonb);
  INSERT INTO _t VALUES ('...can create a tenant role', true);

  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', uC), true);
  SELECT count(*) INTO n FROM fnd_roles WHERE role_audience = 'TENANT'; INSERT INTO _t VALUES ('customer-roles user (support) sees no tenant roles', n = 0);
  SELECT count(*) INTO n FROM fnd_roles WHERE role_audience = 'CUSTOMER'; INSERT INTO _t VALUES ('...but sees the customer roles', n > 0);
  BEGIN PERFORM fnd_role_save(200000000002, '{"role_name":"zz sneaky2","role_audience":"TENANT"}'::jsonb); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('...and cannot create a tenant role', r);
  PERFORM fnd_role_save(200000000002, '{"role_name":"zz made by cr","role_audience":"CUSTOMER"}'::jsonb);
  INSERT INTO _t VALUES ('...can create a customer role', true);
  RESET ROLE;
END $$;

-- ── a clerk (orders only) gets nothing and can change nothing ────────────────
DO $$
DECLARE uClerk bigint := (SELECT v FROM _ids WHERE k='uClerk'); uTarget bigint := (SELECT v FROM _ids WHERE k='uTarget'); r boolean;
BEGIN
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', uClerk), true);
  SET LOCAL ROLE authenticated;
  INSERT INTO _t VALUES ('clerk areas list holds orders.enter and no admin area', 'orders.enter' = ANY (fnd_my_areas()) AND NOT EXISTS (SELECT 1 FROM unnest(fnd_my_areas()) a WHERE a LIKE 'admin.%'));
  INSERT INTO _t VALUES ('clerk sees no roles', fnd_roles_get(200000000002) = '[]'::jsonb);
  INSERT INTO _t VALUES ('clerk sees no users except themselves', jsonb_array_length(fnd_users_get(200000000002)) <= 1);
  INSERT INTO _t VALUES ('clerk sees no groups or numbers', fnd_customer_groups_get(200000000002) = '[]'::jsonb AND fnd_phone_numbers_get(200000000002) = '[]'::jsonb);
  BEGIN PERFORM fnd_role_save(200000000002, '{"role_name":"zz hack","role_audience":"TENANT"}'::jsonb); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('clerk cannot create a role', r);
  BEGIN PERFORM fnd_user_access_save(200000000002, uTarget, ARRAY[(SELECT v FROM _ids WHERE k='r_clerk')], NULL, true); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('clerk cannot assign roles', r);
  BEGIN PERFORM fnd_customer_group_save(200000000002, '{"group_name":"zz hack"}'::jsonb); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('clerk cannot create a group', r);
  RESET ROLE;
END $$;

SELECT name, CASE WHEN ok THEN 'ok' ELSE 'FAIL' END AS result FROM _t WHERE NOT ok;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM _t;
ROLLBACK;
