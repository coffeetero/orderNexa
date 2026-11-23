-- ============================================================
-- SQL tests for the access model: roles/areas, customer-group scope, single active tenancy, leakage, escalation guards.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q < database/tests/access_model_test.sql
-- Assumes the Alpine Bakery seed: tenant 200000000002, account 200000000040 with department 200000000042, account 200000000091.
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _ids (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t, _ids TO PUBLIC;

-- ── Setup (trusted connection) ───────────────────────────────────────────────
DO $$
DECLARE t2 bigint; c2 bigint; g_wg bigint; r_clerk bigint; r_lead bigint; r_cadm bigint; r_tadm bigint; r_t2adm bigint;
  uA bigint; uB bigint; uC bigint; uD bigint; uE bigint; uF bigint; r_cust bigint; r_cust2 bigint;
BEGIN
  INSERT INTO fnd_tenants (tenant_name) VALUES ('zz Test Tenant 2') RETURNING tenant_id INTO t2;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (t2, 'T2 Customer', 'ACCOUNT') RETURNING customer_id INTO c2;
  INSERT INTO _ids VALUES ('t2', t2), ('c2', c2);
  SELECT role_id INTO r_tadm FROM fnd_roles WHERE tenant_id = 200000000002 AND role_name = 'Company Administrator' AND owner_customer_id IS NULL;
  SELECT role_id INTO r_cadm FROM fnd_roles WHERE tenant_id = 200000000002 AND role_name = 'Customer Administrator' AND owner_customer_id IS NULL;
  SELECT role_id INTO r_t2adm FROM fnd_roles WHERE tenant_id = t2 AND role_name = 'Company Administrator';
  INSERT INTO _ids VALUES ('r_tadm', r_tadm), ('r_cadm', r_cadm), ('r_t2adm', r_t2adm);

  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz clerk', 'TENANCY_USER') RETURNING user_id INTO uA;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz nobody', 'TENANCY_USER') RETURNING user_id INTO uB;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz dev two tenants', 'TENANCY_USER') RETURNING user_id INTO uC;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz cust admin 40', 'CUSTOMER_USER') RETURNING user_id INTO uD;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz cust lead 40', 'CUSTOMER_USER') RETURNING user_id INTO uE;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz cust admin 91', 'CUSTOMER_USER') RETURNING user_id INTO uF;
  INSERT INTO _ids VALUES ('uA', uA), ('uB', uB), ('uC', uC), ('uD', uD), ('uE', uE), ('uF', uF);
  INSERT INTO fnd_user_tenants (tenant_id, user_id) SELECT 200000000002, u FROM unnest(ARRAY[uA,uB,uC,uD,uE,uF]) u;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (t2, uC);
  INSERT INTO fnd_user_customers (tenant_id, user_id, customer_id) VALUES (200000000002, uD, 200000000040), (200000000002, uE, 200000000040), (200000000002, uF, 200000000091);

  -- a tenant-level clerk role (order entry only) and a White Glove group holding account 40
  INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'Order Clerk', 'TENANT') RETURNING role_id INTO r_clerk;
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write) VALUES (200000000002, r_clerk, 'orders.enter', true, true);
  INSERT INTO fnd_customer_groups (tenant_id, group_name) VALUES (200000000002, 'White Glove') RETURNING group_id INTO g_wg;
  INSERT INTO fnd_customer_group_members (tenant_id, group_id, customer_id) VALUES (200000000002, g_wg, 200000000040);
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uA, r_clerk), (200000000002, uC, r_tadm), (t2, uC, r_t2adm), (200000000002, uD, r_cadm);
  INSERT INTO fnd_user_customer_groups (tenant_id, user_id, group_id)
    VALUES (200000000002, uA, g_wg),
           (200000000002, uC, (SELECT group_id FROM fnd_customer_groups WHERE tenant_id = 200000000002 AND is_all_customers));
  -- a customer-side "Lead" role (tenant-level, customer audience): manage roles + view orders, but NOT payments
  INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'Portal Lead', 'CUSTOMER') RETURNING role_id INTO r_lead;
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write)
    VALUES (200000000002, r_lead, 'portal.roles', true, true), (200000000002, r_lead, 'portal.orders', true, false);
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uE, r_lead), (200000000002, uF, r_cadm);
  INSERT INTO _ids VALUES ('g_wg', g_wg), ('r_clerk', r_clerk), ('r_lead', r_lead);
END $$;

-- ── Part A: privileges ───────────────────────────────────────────────────────
DO $$
DECLARE uA bigint := (SELECT v FROM _ids WHERE k='uA'); uB bigint := (SELECT v FROM _ids WHERE k='uB'); uD bigint := (SELECT v FROM _ids WHERE k='uD');
  r boolean;
BEGIN
  INSERT INTO _t VALUES ('trusted connection has access', fnd_has_access('financials.credits','D'));
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uA), true);
  SET LOCAL ROLE authenticated;
  INSERT INTO _t VALUES ('clerk: orders.enter read+write', fnd_has_access('orders.enter','R') AND fnd_has_access('orders.enter','W'));
  INSERT INTO _t VALUES ('clerk: no delete/approve on orders.enter', NOT fnd_has_access('orders.enter','D') AND NOT fnd_has_access('orders.enter','A'));
  INSERT INTO _t VALUES ('clerk: separation of duties - no financials', NOT fnd_has_access('financials.credits','R') AND NOT fnd_has_access('financials.payments','R'));
  INSERT INTO _t VALUES ('clerk: cannot administer roles', NOT fnd_has_access('admin.roles','R'));
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uB), true);
  INSERT INTO _t VALUES ('user with no role has no access (deny by default)', NOT fnd_has_access('orders.enter','R') AND NOT fnd_has_access('dashboard','R'));
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uD), true);
  INSERT INTO _t VALUES ('customer admin: portal areas yes', fnd_has_access('portal.orders','W') AND fnd_has_access('portal.users','R'));
  INSERT INTO _t VALUES ('customer admin: staff areas no, even though admin role', NOT fnd_has_access('orders.enter','R') AND NOT fnd_has_access('financials.credits','R') AND NOT fnd_has_access('admin.roles','R'));
  RESET ROLE;
  BEGIN PERFORM fnd_has_access('orders.enter','X'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('bad action raises', r);
END $$;

-- ── Part B: data scope and effective groups ──────────────────────────────────
DO $$
DECLARE uA bigint := (SELECT v FROM _ids WHERE k='uA'); uB bigint := (SELECT v FROM _ids WHERE k='uB'); uC bigint := (SELECT v FROM _ids WHERE k='uC');
  uD bigint := (SELECT v FROM _ids WHERE k='uD'); g_wg bigint := (SELECT v FROM _ids WHERE k='g_wg'); ids bigint[]; new_c bigint; hg bigint; r boolean;
BEGIN
  INSERT INTO _t VALUES ('department inherits the group of its account', EXISTS (SELECT 1 FROM fnd_customer_group_effective WHERE customer_id = 200000000042 AND group_id = g_wg));
  INSERT INTO _t VALUES ('account in the group has an effective row', EXISTS (SELECT 1 FROM fnd_customer_group_effective WHERE customer_id = 200000000040 AND group_id = g_wg));
  INSERT INTO _t VALUES ('unrelated customer has no effective group', NOT EXISTS (SELECT 1 FROM fnd_customer_group_effective WHERE customer_id = 200000000091));
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, customer_parent_id) VALUES (200000000002, 'zz new site', 'SITE', 200000000040) RETURNING customer_id INTO new_c;
  INSERT INTO _t VALUES ('new child customer starts with the parent group', EXISTS (SELECT 1 FROM fnd_customer_group_effective WHERE customer_id = new_c AND group_id = g_wg));
  UPDATE fnd_customers SET customer_parent_id = 200000000091 WHERE customer_id = new_c;
  INSERT INTO _t VALUES ('moving a customer drops the old inherited group', NOT EXISTS (SELECT 1 FROM fnd_customer_group_effective WHERE customer_id = new_c));
  INSERT INTO fnd_customer_groups (tenant_id, group_name) VALUES (200000000002, 'High Risk') RETURNING group_id INTO hg;
  INSERT INTO fnd_customer_group_members (tenant_id, group_id, customer_id) VALUES (200000000002, hg, 200000000042);
  INSERT INTO _t VALUES ('a child with its own group overrides the inherited one', EXISTS (SELECT 1 FROM fnd_customer_group_effective WHERE customer_id = 200000000042 AND group_id = hg)
       AND NOT EXISTS (SELECT 1 FROM fnd_customer_group_effective WHERE customer_id = 200000000042 AND group_id = g_wg));
  DELETE FROM fnd_customer_group_members WHERE group_id = hg;
  INSERT INTO _t VALUES ('removing the override restores inheritance', EXISTS (SELECT 1 FROM fnd_customer_group_effective WHERE customer_id = 200000000042 AND group_id = g_wg));

  BEGIN INSERT INTO fnd_customer_group_members (tenant_id, group_id, customer_id)
          SELECT 200000000002, group_id, 200000000091 FROM fnd_customer_groups WHERE tenant_id = 200000000002 AND is_all_customers; r := false;
  EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('All Customers group refuses explicit members', r);
  BEGIN DELETE FROM fnd_customer_groups WHERE tenant_id = 200000000002 AND is_all_customers; r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('All Customers group cannot be deleted', r);

  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uA), true);
  SET LOCAL ROLE authenticated;
  ids := fnd_scope_customer_ids();
  INSERT INTO _t VALUES ('White Glove user: not all, sees account 40 and department 42 only',
      NOT fnd_scope_is_all() AND 200000000040 = ANY(ids) AND 200000000042 = ANY(ids) AND NOT (200000000091 = ANY(ids)));
  INSERT INTO _t VALUES ('fnd_customer_in_scope agrees', fnd_customer_in_scope(200000000042) AND NOT fnd_customer_in_scope(200000000091));
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uB), true);
  INSERT INTO _t VALUES ('user with no group sees no customers (not "all")', NOT fnd_scope_is_all() AND cardinality(fnd_scope_customer_ids()) = 0);
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uC), true);
  INSERT INTO _t VALUES ('user holding All Customers skips the customer check', fnd_scope_is_all() AND fnd_customer_in_scope(200000000091));
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uD), true);
  ids := fnd_scope_customer_ids();
  INSERT INTO _t VALUES ('customer user scope = own customer + descendants only', NOT fnd_scope_is_all() AND 200000000040 = ANY(ids) AND 200000000042 = ANY(ids) AND NOT (200000000091 = ANY(ids)));
  RESET ROLE;
END $$;

-- ── Part C: tenancy leakage ──────────────────────────────────────────────────
DO $$
DECLARE uC bigint := (SELECT v FROM _ids WHERE k='uC'); uA bigint := (SELECT v FROM _ids WHERE k='uA'); t2 bigint := (SELECT v FROM _ids WHERE k='t2');
  n int; n2 int;
BEGIN
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uC), true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM fnd_roles WHERE tenant_id = 200000000002;
  SELECT count(*) INTO n2 FROM fnd_roles WHERE tenant_id = t2;
  INSERT INTO _t VALUES ('two-tenant user in tenant A sees A roles and zero T2 roles', n > 0 AND n2 = 0);
  SELECT count(*) INTO n FROM fnd_customer_groups WHERE tenant_id = t2;
  SELECT count(*) INTO n2 FROM fnd_role_area_access WHERE tenant_id = t2;
  INSERT INTO _t VALUES ('...nor T2 groups or T2 access rows', n = 0 AND n2 = 0);
  INSERT INTO _t VALUES ('...and has no access in T2 while A is active', NOT EXISTS (SELECT 1 FROM fnd_user_roles WHERE tenant_id = t2));
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":%s,"app_user_id":%s}}', t2, uC), true);
  SELECT count(*) INTO n FROM fnd_roles WHERE tenant_id = 200000000002;
  SELECT count(*) INTO n2 FROM fnd_roles WHERE tenant_id = t2;
  INSERT INTO _t VALUES ('switching the active tenant flips visibility completely', n = 0 AND n2 > 0);
  INSERT INTO _t VALUES ('access in T2 comes from the T2 role', fnd_has_access('admin.roles','W'));
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":%s,"app_user_id":%s}}', t2, uA), true);
  INSERT INTO _t VALUES ('a user claiming a tenant they do not belong to gets nothing',
      NOT fnd_has_access('orders.enter','R') AND NOT EXISTS (SELECT 1 FROM fnd_roles) AND NOT fnd_scope_is_all());
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', uC), true);
  INSERT INTO _t VALUES ('a token without the single tenant_id claim gets nothing (old allowed list ignored)',
      NOT fnd_has_access('admin.roles','R') AND NOT EXISTS (SELECT 1 FROM fnd_roles) AND NOT EXISTS (SELECT 1 FROM fnd_user_roles));
  RESET ROLE;
END $$;

-- ── Part D: who may change what ──────────────────────────────────────────────
DO $$
DECLARE uA bigint := (SELECT v FROM _ids WHERE k='uA'); uC bigint := (SELECT v FROM _ids WHERE k='uC'); uD bigint := (SELECT v FROM _ids WHERE k='uD');
  uE bigint := (SELECT v FROM _ids WHERE k='uE'); uF bigint := (SELECT v FROM _ids WHERE k='uF'); r_tadm bigint := (SELECT v FROM _ids WHERE k='r_tadm');
  r_cadm bigint := (SELECT v FROM _ids WHERE k='r_cadm'); r_clerk bigint := (SELECT v FROM _ids WHERE k='r_clerk'); t2 bigint := (SELECT v FROM _ids WHERE k='t2');
  r boolean; n int; new_role bigint; rows int;
BEGIN
  -- clerk (orders only) cannot read or write groups/roles
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uA), true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM fnd_customer_groups; INSERT INTO _t VALUES ('clerk cannot read customer groups', n = 0);
  SELECT count(*) INTO n FROM fnd_roles;           INSERT INTO _t VALUES ('clerk cannot read roles', n = 0);
  BEGIN INSERT INTO fnd_customer_groups (tenant_id, group_name) VALUES (200000000002, 'zz hack'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('clerk cannot create a group', r);
  BEGIN INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uA, r_tadm); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('clerk cannot grant themselves Company Administrator', r);

  -- tenant admin: system role guards
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uC), true);
  BEGIN DELETE FROM fnd_roles WHERE role_id = r_tadm; r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('system role cannot be deleted', r);
  UPDATE fnd_role_area_access SET can_write = false WHERE role_id = r_tadm; GET DIAGNOSTICS rows = ROW_COUNT;
  INSERT INTO _t VALUES ('system role access rows cannot be edited', rows = 0);
  BEGIN INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uA, r_cadm); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a CUSTOMER role cannot be given to a tenant user', r);
  BEGIN INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uD, r_clerk); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a TENANT role cannot be given to a customer user', r);
  BEGIN INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read) VALUES (200000000002, r_clerk, 'portal.orders', true); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a customer area cannot be put on a tenant role', r);
  BEGIN INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uC, (SELECT role_id FROM fnd_roles WHERE tenant_id = t2 LIMIT 1)); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('cannot assign a role of another tenant', r);
  RESET ROLE;
  UPDATE fnd_tenants SET allow_multiple_roles = false WHERE tenant_id = 200000000002;
  BEGIN INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uA, r_tadm); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('single-role tenants refuse a second role', r);
  UPDATE fnd_tenants SET allow_multiple_roles = true WHERE tenant_id = 200000000002;

  -- customer admin (account 40)
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uD), true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM fnd_roles WHERE role_audience = 'TENANT'; INSERT INTO _t VALUES ('customer admin cannot see tenant-side roles', n = 0);
  SELECT count(*) INTO n FROM fnd_roles WHERE role_audience = 'CUSTOMER'; INSERT INTO _t VALUES ('customer admin sees customer roles', n > 0);
  INSERT INTO fnd_roles (tenant_id, owner_customer_id, role_name, role_audience) VALUES (200000000002, 200000000040, 'Buyers', 'CUSTOMER') RETURNING role_id INTO new_role;
  INSERT INTO _t VALUES ('customer admin can create a role owned by their customer', new_role IS NOT NULL);
  BEGIN INSERT INTO fnd_roles (tenant_id, owner_customer_id, role_name, role_audience) VALUES (200000000002, 200000000091, 'Intruder', 'CUSTOMER'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('...but not for another customer', r);
  BEGIN INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'Tenant-level', 'CUSTOMER'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('...and cannot create a tenant-level role', r);
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read) VALUES (200000000002, new_role, 'portal.orders', true);
  INSERT INTO _t VALUES ('customer admin can give the new role an area they hold', true);
  SELECT count(*) INTO n FROM fnd_user_roles WHERE user_id = uE; INSERT INTO _t VALUES ('customer admin sees role assignments of users in their customer', n > 0);
  SELECT count(*) INTO n FROM fnd_user_roles WHERE user_id = uF; INSERT INTO _t VALUES ('...and none for another customer''s users', n = 0);
  BEGIN INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uF, new_role); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('customer admin cannot assign roles to another customer''s user', r);
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uE, new_role);
  INSERT INTO _t VALUES ('customer admin can assign their customer''s role to their user', true);
  RESET ROLE;
  BEGIN INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uF, new_role); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a role owned by customer 40 cannot go to a user of customer 91 (trigger, even as admin)', r);

  -- escalation: lead (portal.roles write, portal.orders read only) tries to grant rights they do not hold
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uE), true);
  SET LOCAL ROLE authenticated;
  INSERT INTO fnd_roles (tenant_id, owner_customer_id, role_name, role_audience) VALUES (200000000002, 200000000040, 'Lead made', 'CUSTOMER') RETURNING role_id INTO new_role;
  BEGIN INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read) VALUES (200000000002, new_role, 'portal.payments', true); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('escalation blocked: cannot grant an area they do not hold', r);
  BEGIN INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write) VALUES (200000000002, new_role, 'portal.orders', true, true); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('escalation blocked: cannot grant write where they only hold read', r);
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read) VALUES (200000000002, new_role, 'portal.orders', true);
  INSERT INTO _t VALUES ('...but can grant what they hold', true);
  RESET ROLE;
END $$;

-- ── Part E: other tables ─────────────────────────────────────────────────────
DO $$
DECLARE uC bigint := (SELECT v FROM _ids WHERE k='uC'); uA bigint := (SELECT v FROM _ids WHERE k='uA'); n int; r boolean;
BEGIN
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uA), true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM fnd_areas; INSERT INTO _t VALUES ('area registry is readable by any signed-in user', n >= 55);
  BEGIN INSERT INTO fnd_areas (area_key, module, area_name, audience) VALUES ('x.y','x','y','TENANT'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('area registry is not writable by users', r);
  SELECT count(*) INTO n FROM fnd_tenant_phone_numbers; INSERT INTO _t VALUES ('clerk cannot read phone numbers', n = 0);
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"app_user_id":%s}}', uC), true);
  INSERT INTO fnd_tenant_phone_numbers (tenant_id, phone_number, channel, label) VALUES (200000000002, '+15555550100', 'WHATSAPP', 'zz');
  SELECT count(*) INTO n FROM fnd_tenant_phone_numbers; INSERT INTO _t VALUES ('tenant admin can manage the tenant''s numbers', n = 1);
  BEGIN INSERT INTO fnd_tenant_phone_numbers (tenant_id, phone_number, channel) VALUES ((SELECT v FROM _ids WHERE k='t2'), '+15555550101', 'VOICE'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('...but not another tenant''s', r);
  BEGIN INSERT INTO fnd_tenant_phone_numbers (tenant_id, phone_number, channel, is_shared) VALUES (200000000002, '+15555550102', 'VOICE', true); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('shared number cannot carry a tenant', r);
  RESET ROLE;
  INSERT INTO _t VALUES ('seeded users kept access: tenant user is Company Administrator + All Customers',
     EXISTS (SELECT 1 FROM fnd_user_roles ur JOIN fnd_roles r2 USING (role_id) WHERE ur.user_id = 200000174045 AND r2.role_name = 'Company Administrator')
     AND EXISTS (SELECT 1 FROM fnd_user_customer_groups ug JOIN fnd_customer_groups g USING (group_id) WHERE ug.user_id = 200000174045 AND g.is_all_customers));
  INSERT INTO _t VALUES ('a new tenant is seeded with the group and both system roles',
     EXISTS (SELECT 1 FROM fnd_customer_groups WHERE tenant_id = (SELECT v FROM _ids WHERE k='t2') AND is_all_customers)
     AND (SELECT count(*) FROM fnd_roles WHERE tenant_id = (SELECT v FROM _ids WHERE k='t2') AND is_system) = 2);
END $$;

DO $$
DECLARE t2 bigint := (SELECT v FROM _ids WHERE k='t2'); r boolean;
BEGIN
  BEGIN DELETE FROM fnd_tenants WHERE tenant_id = t2; r := true; EXCEPTION WHEN OTHERS THEN r := false; END;
  INSERT INTO _t VALUES ('deleting a tenant cascades through the system group and roles', r AND NOT EXISTS (SELECT 1 FROM fnd_roles WHERE tenant_id = t2));
END $$;

SELECT name, CASE WHEN ok THEN 'ok' ELSE 'FAIL' END AS result FROM _t WHERE NOT ok;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM _t;
ROLLBACK;
