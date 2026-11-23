-- ============================================================
-- SQL tests for the rewritten RLS: schema hygiene, anon lockout, area enforcement, data scope, tenancy leakage,
-- definer-function guards, self-escalation. One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q < database/tests/rls_test.sql
-- Assumes the Alpine Bakery seed (tenant 200000000002; orders owned by customers 158 (2), 685, 91, 106; customer user 200000174046 on account 91).
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _ids (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t, _ids TO PUBLIC;

-- ── Part A: schema hygiene (scans every table and function, so a new unprotected table fails this test) ──
DO $$
DECLARE r record; bad text;
BEGIN
  SELECT string_agg(c.relname, ',') INTO bad FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'bps' AND c.relkind = 'r' AND NOT c.relrowsecurity;
  INSERT INTO _t VALUES ('every bps table has row level security ON (' || coalesce(bad, 'none missing') || ')', bad IS NULL);
  SELECT string_agg(DISTINCT table_name, ',') INTO bad FROM information_schema.role_table_grants WHERE table_schema = 'bps' AND grantee = 'anon';
  INSERT INTO _t VALUES ('anon has no table privileges in bps (' || coalesce(bad, 'none') || ')', bad IS NULL);
  SELECT string_agg(DISTINCT table_name, ',') INTO bad FROM information_schema.role_table_grants
   WHERE table_schema = 'bps' AND grantee = 'authenticated' AND privilege_type IN ('TRUNCATE','REFERENCES','TRIGGER');
  INSERT INTO _t VALUES ('authenticated has no TRUNCATE/REFERENCES/TRIGGER (' || coalesce(bad, 'none') || ')', bad IS NULL);
  SELECT string_agg(p.proname, ',') INTO bad FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'bps' AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('public', p.oid, 'EXECUTE'));
  INSERT INTO _t VALUES ('no bps function is executable by anon or PUBLIC (' || coalesce(left(bad, 80), 'none') || ')', bad IS NULL);
  SELECT string_agg(p.proname, ',') INTO bad FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'bps' AND p.prosecdef AND p.proname IN ('fnd_tenant_access_seed','fnd_customer_group_effective_rebuild','bps_access_token_hook')
     AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
  INSERT INTO _t VALUES ('internal definer helpers are not callable by app users', bad IS NULL);
  SELECT string_agg(c.relname, ',') INTO bad FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'bps' AND c.relkind = 'r' AND c.relname ~ '^(fnd_|om_|ar_)' AND c.relname NOT IN ('fnd_areas','fnd_currencies','fnd_user_menu_actions','fnd_user_preferences')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns k WHERE k.table_schema = 'bps' AND k.table_name = c.relname AND k.column_name = 'tenant_id');
  INSERT INTO _t VALUES ('every business table carries tenant_id (' || coalesce(bad, 'none missing') || ')', bad IS NULL);
END $$;

-- ── Setup (trusted) ──────────────────────────────────────────────────────────
DO $$
DECLARE t2 bigint; c2 bigint; uClerk bigint; uWG bigint; uNone bigint; uBoth bigint; uAcct bigint; uCook bigint; g1 bigint;
  r_clerk bigint; r_ar bigint; r_tadm bigint; r_t2adm bigint;
BEGIN
  INSERT INTO fnd_tenants (tenant_name) VALUES ('zz RLS Tenant 2') RETURNING tenant_id INTO t2;
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (t2, 'T2 Customer', 'ACCOUNT') RETURNING customer_id INTO c2;
  INSERT INTO _ids VALUES ('t2', t2), ('c2', c2);
  SELECT role_id INTO r_tadm  FROM fnd_roles WHERE tenant_id = 200000000002 AND role_name = 'Company Administrator';
  SELECT role_id INTO r_t2adm FROM fnd_roles WHERE tenant_id = t2 AND role_name = 'Company Administrator';
  INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'zz Clerk', 'TENANT') RETURNING role_id INTO r_clerk;
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write) VALUES (200000000002, r_clerk, 'orders.enter', true, true);
  INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'zz Accountant', 'TENANT') RETURNING role_id INTO r_ar;
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write)
    VALUES (200000000002, r_ar, 'financials.ar', true, false), (200000000002, r_ar, 'financials.credits', true, true);
  INSERT INTO fnd_customer_groups (tenant_id, group_name) VALUES (200000000002, 'zz G1') RETURNING group_id INTO g1;
  INSERT INTO fnd_customer_group_members (tenant_id, group_id, customer_id) VALUES (200000000002, g1, 200000000158);

  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz clerk all', 'TENANCY_USER') RETURNING user_id INTO uClerk;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz clerk g1', 'TENANCY_USER') RETURNING user_id INTO uWG;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz clerk no group', 'TENANCY_USER') RETURNING user_id INTO uNone;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz two tenants', 'TENANCY_USER') RETURNING user_id INTO uBoth;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz accountant', 'TENANCY_USER') RETURNING user_id INTO uAcct;
  INSERT INTO _ids VALUES ('uClerk', uClerk), ('uWG', uWG), ('uNone', uNone), ('uBoth', uBoth), ('uAcct', uAcct);
  INSERT INTO fnd_user_tenants (tenant_id, user_id) SELECT 200000000002, u FROM unnest(ARRAY[uClerk, uWG, uNone, uBoth, uAcct]) u;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (t2, uBoth);
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES
    (200000000002, uClerk, r_clerk), (200000000002, uWG, r_clerk), (200000000002, uNone, r_clerk), (200000000002, uBoth, r_tadm), (t2, uBoth, r_t2adm), (200000000002, uAcct, r_ar);
  INSERT INTO fnd_user_customer_groups (tenant_id, user_id, group_id) VALUES
    (200000000002, uClerk, (SELECT group_id FROM fnd_customer_groups WHERE tenant_id = 200000000002 AND is_all_customers)),
    (200000000002, uWG, g1),
    (200000000002, uBoth, (SELECT group_id FROM fnd_customer_groups WHERE tenant_id = 200000000002 AND is_all_customers)),
    (200000000002, uAcct, (SELECT group_id FROM fnd_customer_groups WHERE tenant_id = 200000000002 AND is_all_customers)),
    (t2, uBoth, (SELECT group_id FROM fnd_customer_groups WHERE tenant_id = t2 AND is_all_customers));
END $$;

-- ── Part B: anon is locked out ───────────────────────────────────────────────
DO $$
DECLARE r boolean;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon;
  BEGIN PERFORM count(*) FROM fnd_customers; r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('anon cannot read customers', r);
  BEGIN INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (200000000002, 'zz anon', 'ACCOUNT'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('anon cannot insert customers', r);
  BEGIN PERFORM fnd_tenant_sequence_next(200000000002, 'order_number'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('anon cannot burn tenant numbers', r);
  BEGIN PERFORM fnd_customers_save(200000000002, NULL, 'create', '{}'::jsonb); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('anon cannot call the customer save function', r);
  RESET ROLE;
END $$;

-- ── Part C: area enforcement (the clerk holds orders.enter only) ─────────────
DO $$
DECLARE uClerk bigint := (SELECT v FROM _ids WHERE k='uClerk'); uAcct bigint := (SELECT v FROM _ids WHERE k='uAcct'); n int; r boolean; rows int;
BEGIN
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', uClerk), true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM om_orders; INSERT INTO _t VALUES ('clerk sees all 5 orders (All Customers)', n = 5);
  SELECT count(*) INTO n FROM om_order_lines; INSERT INTO _t VALUES ('clerk sees order lines', n > 0);
  SELECT count(*) INTO n FROM ar_transactions; INSERT INTO _t VALUES ('separation of duties: clerk sees no invoices', n = 0);
  SELECT count(*) INTO n FROM ar_payments; INSERT INTO _t VALUES ('...no payments', n = 0);
  SELECT count(*) INTO n FROM fnd_customers WHERE tenant_id = 200000000002; INSERT INTO _t VALUES ('clerk can read customers (needed for order entry)', n > 100);
  BEGIN INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (200000000002, 'zz clerk made', 'ACCOUNT'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('clerk cannot create customers', r);
  UPDATE fnd_customers SET customer_name = 'zz hacked' WHERE customer_id = 200000000040; GET DIAGNOSTICS rows = ROW_COUNT;
  INSERT INTO _t VALUES ('clerk cannot rename customers', rows = 0);
  DELETE FROM om_orders WHERE order_id IN (SELECT order_id FROM om_orders LIMIT 1); GET DIAGNOSTICS rows = ROW_COUNT;
  INSERT INTO _t VALUES ('clerk cannot delete orders (no delete right)', rows = 0);
  BEGIN PERFORM om_production_runs_process(200000000002, DATE '2026-11-23', DATE '2026-11-23', 'MORNING'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('clerk cannot process a production run', r);
  SELECT count(*) INTO n FROM fnd_users WHERE user_id <> uClerk; INSERT INTO _t VALUES ('clerk sees no other users', n = 0);
  SELECT count(*) INTO n FROM fnd_user_tenants WHERE user_id <> uClerk; INSERT INTO _t VALUES ('...nor other memberships', n = 0);
  SELECT count(*) INTO n FROM fnd_tenant_sequences; INSERT INTO _t VALUES ('...nor tenant numbering settings', n = 0);
  UPDATE fnd_users SET time_zone = 'America/Chicago' WHERE user_id = uClerk; GET DIAGNOSTICS rows = ROW_COUNT;
  INSERT INTO _t VALUES ('a user can edit their own display preferences', rows = 1);
  BEGIN UPDATE fnd_users SET user_type = 'CUSTOMER_USER' WHERE user_id = uClerk; r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a user cannot change their own type (no self-escalation)', r);
  BEGIN UPDATE fnd_users SET is_active = false WHERE user_id = uClerk; r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('...nor their own status', r);
  BEGIN INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES ((SELECT v FROM _ids WHERE k='t2'), uClerk); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a user cannot add themselves to another tenant', r);

  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', uAcct), true);
  SELECT count(*) INTO n FROM ar_transactions; INSERT INTO _t VALUES ('accountant sees invoices', n = 2);
  SELECT count(*) INTO n FROM om_orders; INSERT INTO _t VALUES ('accountant: financials areas also let them read orders', n = 5);
  BEGIN INSERT INTO om_orders (tenant_id, customer_id, order_number, order_date) VALUES (200000000002, 200000000158, 'ZZ-1', CURRENT_DATE); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('accountant cannot enter orders', r);
  RESET ROLE;
END $$;

-- ── Part D: data scope on rows ───────────────────────────────────────────────
DO $$
DECLARE uWG bigint := (SELECT v FROM _ids WHERE k='uWG'); uNone bigint := (SELECT v FROM _ids WHERE k='uNone'); n int; n2 int;
BEGIN
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', uWG), true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM om_orders; INSERT INTO _t VALUES ('group user sees only their group''s orders (2 of 5)', n = 2);
  SELECT count(*) INTO n FROM om_order_lines l WHERE NOT EXISTS (SELECT 1 FROM om_orders o WHERE o.order_id = l.order_id);
  INSERT INTO _t VALUES ('...and the lines follow their order', n = 0);
  SELECT count(*) INTO n FROM fnd_customers; INSERT INTO _t VALUES ('group user sees the group''s customer and its departments/sites (7), nothing else', n = 7);
  SELECT count(*) INTO n FROM fnd_notes WHERE source_table = 'fnd_customers' AND entity_id <> 200000000158; INSERT INTO _t VALUES ('notes of other customers are hidden', n = 0);
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', uNone), true);
  SELECT count(*) INTO n FROM om_orders; SELECT count(*) INTO n2 FROM fnd_customers;
  INSERT INTO _t VALUES ('a user with no group sees no orders and no customers', n = 0 AND n2 = 0);
  RESET ROLE;
END $$;

-- ── Part E: tenancy leakage and definer guards ───────────────────────────────
DO $$
DECLARE uBoth bigint := (SELECT v FROM _ids WHERE k='uBoth'); t2 bigint := (SELECT v FROM _ids WHERE k='t2'); c2 bigint := (SELECT v FROM _ids WHERE k='c2'); n int; r boolean; rows int; j jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","sub":"%s","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":%s}}', (SELECT auth_user_id FROM fnd_users WHERE user_id = uBoth), uBoth), true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM fnd_customers WHERE tenant_id = t2; INSERT INTO _t VALUES ('two-tenant user in A sees none of B''s customers', n = 0);
  UPDATE fnd_customers SET customer_name = 'zz leak' WHERE customer_id = c2; GET DIAGNOSTICS rows = ROW_COUNT;
  INSERT INTO _t VALUES ('...cannot update B''s customers', rows = 0);
  BEGIN INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (t2, 'zz planted', 'ACCOUNT'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('...cannot insert into B', r);
  BEGIN PERFORM fnd_tenant_sequence_next(t2, 'order_number'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('...cannot draw B''s numbers through the definer function', r);
  BEGIN PERFORM om_production_run_get_or_create(t2, DATE '2031-01-01', 'MORNING'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('...cannot create B''s production runs', r);
  BEGIN PERFORM fnd_customers_save(t2, c2, 'update', '{"customer_name":"zz leak"}'::jsonb); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('...cannot call the customer save function for B', r);
  j := fnd_tenants_get(); INSERT INTO _t VALUES ('fnd_tenants_get lists only the active tenancy', jsonb_array_length(j) = 1 AND (j->0->>'tenant_id')::bigint = 200000000002);
  SELECT count(*) INTO n FROM fnd_tenants; INSERT INTO _t VALUES ('fnd_tenants shows only the active tenant', n = 1);

  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"allowed_tenant_ids":[],"app_user_id":%s}}', uBoth), true);
  SELECT count(*) INTO n FROM om_orders; INSERT INTO _t VALUES ('a token with no tenancy selected sees no orders', n = 0);
  SELECT count(*) INTO n FROM fnd_customers; INSERT INTO _t VALUES ('...no customers', n = 0);
  SELECT count(*) INTO n FROM fnd_items; INSERT INTO _t VALUES ('...no items', n = 0);
  SELECT count(*) INTO n FROM fnd_valuesets; INSERT INTO _t VALUES ('...no value lists', n = 0);
  SELECT count(*) INTO n FROM fnd_users WHERE user_id <> uBoth; INSERT INTO _t VALUES ('...no other users', n = 0);
  PERFORM set_config('request.jwt.claims', format('{"role":"authenticated","app_metadata":{"tenant_id":%s,"allowed_tenant_ids":[%s],"app_user_id":%s}}', t2, t2, uBoth), true);
  SELECT count(*) INTO n FROM fnd_customers; INSERT INTO _t VALUES ('switching to B shows only B''s customers', n = 1);
  SELECT count(*) INTO n FROM om_orders; INSERT INTO _t VALUES ('...and none of A''s orders', n = 0);
  RESET ROLE;
END $$;

-- ── Part F: customer-side user (account 91) ──────────────────────────────────
DO $$
DECLARE n int; r boolean; rows int;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{"tenant_id":200000000002,"allowed_tenant_ids":[200000000002],"app_user_id":200000174046}}', true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM om_orders; INSERT INTO _t VALUES ('customer user sees only their own account''s orders', n = 1);
  SELECT count(*) INTO n FROM fnd_customers; INSERT INTO _t VALUES ('...and the customers in their own account tree (12)', n = 12);
  SELECT count(*) INTO n FROM fnd_customers WHERE customer_id NOT IN (SELECT customer_id FROM fnd_customers WHERE customer_id = 200000000091 OR customer_parent_id = 200000000091);
  INSERT INTO _t VALUES ('...nothing outside their account tree', n = 0);
  SELECT count(*) INTO n FROM om_production_runs; INSERT INTO _t VALUES ('customer user can read runs/settings (needed for cutoff display)', n >= 0);
  BEGIN INSERT INTO fnd_customers (tenant_id, customer_name, customer_type) VALUES (200000000002, 'zz portal made', 'ACCOUNT'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('customer user cannot create customers', r);
  UPDATE om_production_codes SET cutoff_days_before = 9; GET DIAGNOSTICS rows = ROW_COUNT;
  INSERT INTO _t VALUES ('customer user cannot change production settings', rows = 0);
  SELECT count(*) INTO n FROM fnd_users WHERE user_id <> 200000174046; INSERT INTO _t VALUES ('customer admin sees only users attached to their account', n = 0);
  SELECT count(*) INTO n FROM fnd_tenant_sequences; INSERT INTO _t VALUES ('customer user sees no numbering settings', n = 0);
  SELECT count(*) INTO n FROM ar_transactions WHERE customer_id <> 200000000091; INSERT INTO _t VALUES ('customer user sees no other customer''s invoices', n = 0);
  RESET ROLE;
END $$;

DO $$
DECLARE t2 bigint := (SELECT v FROM _ids WHERE k='t2'); r boolean;
BEGIN
  BEGIN DELETE FROM fnd_tenants WHERE tenant_id = t2; r := true; EXCEPTION WHEN OTHERS THEN r := false; END;
  INSERT INTO _t VALUES ('a whole tenant can still be removed (cascade)', r);
END $$;

SELECT name, CASE WHEN ok THEN 'ok' ELSE 'FAIL' END AS result FROM _t WHERE NOT ok;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM _t;
ROLLBACK;
