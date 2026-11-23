-- ============================================================
-- SQL tests for the health checks: run, open/close findings, severity counts, enable/disable, access.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q < database/tests/health_checks_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _id (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t, _id TO PUBLIC;

DO $$
DECLARE acc bigint; pb bigint; r_cl bigint; u_cl bigint; o bigint;
BEGIN
  INSERT INTO fnd_customers (tenant_id, customer_name, customer_type, is_active) VALUES (200000000002, 'zz Health Account', 'ACCOUNT', true) RETURNING customer_id INTO acc;
  INSERT INTO fnd_pricebooks (tenant_id, pricebook_name, is_active, currency_id, status) VALUES (200000000002, 'zz Health Book', true, 200000000001, 'Approved') RETURNING pricebook_id INTO pb;
  INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'zz health clerk', 'TENANT') RETURNING role_id INTO r_cl;
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write) VALUES (200000000002, r_cl, 'admin.health', true, true);
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz health clerk', 'TENANCY_USER') RETURNING user_id INTO u_cl;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (200000000002, u_cl);
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, u_cl, r_cl);
  INSERT INTO _id VALUES ('acc', acc), ('pb', pb), ('u_cl', u_cl);
END $$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
  json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174045))::text, true);

DO $$
DECLARE acc bigint; pb bigint; s jsonb; f jsonb; n int; o jsonb; r boolean; lid bigint;
BEGIN
  SELECT v INTO acc FROM _id WHERE k='acc'; SELECT v INTO pb FROM _id WHERE k='pb';

  s := fnd_health_run(200000000002, 'Manual');
  INSERT INTO _t VALUES ('a run covers every check in the list', (s ->> 'checks_run')::int = (SELECT count(*) FROM fnd_health_catalog()));
  INSERT INTO _t VALUES ('the checks list shows each check with Setup and Data categories',
    (SELECT count(DISTINCT x ->> 'category') FROM jsonb_array_elements(fnd_health_checks_get(200000000002)) x) = 2);
  INSERT INTO _t VALUES ('an account without a pricing book is a Warning finding',
    EXISTS (SELECT 1 FROM jsonb_array_elements(fnd_health_findings_get(200000000002)) x WHERE x ->> 'check_code' = 'accounts_without_pricebook' AND (x ->> 'customer_id')::bigint = acc AND x ->> 'type' = 'Warning'));
  INSERT INTO _t VALUES ('a finding carries remediation text', EXISTS (SELECT 1 FROM jsonb_array_elements(fnd_health_findings_get(200000000002)) x WHERE (x ->> 'customer_id')::bigint = acc AND length(x ->> 'remediation') > 10));
  INSERT INTO _t VALUES ('with only warnings and information the heart state is warning (or ok, never error)', (s ->> 'state') IN ('warning', 'ok'));

  -- assign + approve the book: the finding closes by itself
  INSERT INTO fnd_customer_pricebooks (tenant_id, customer_id, pricebook_id, assignment_type, status, effective_start_date, is_active, precedence) VALUES (200000000002, acc, pb, 'Default', 'Approved', '2020-01-01', true, 1);
  PERFORM fnd_health_run(200000000002, 'Manual', 'accounts_without_pricebook');
  INSERT INTO _t VALUES ('assigning an approved book closes the finding automatically (fixed_by stays empty)',
    EXISTS (SELECT 1 FROM fnd_health_log WHERE tenant_id = 200000000002 AND record_id = acc AND check_code = 'accounts_without_pricebook' AND fixed_at IS NOT NULL AND fixed_by IS NULL)
    AND NOT EXISTS (SELECT 1 FROM fnd_health_log WHERE tenant_id = 200000000002 AND record_id = acc AND check_code = 'accounts_without_pricebook' AND fixed_at IS NULL));

  -- an upcoming order for an account whose book does not cover the delivery date is an Error
  UPDATE fnd_customer_pricebooks SET effective_end_date = '2020-12-31' WHERE customer_id = acc;
  PERFORM om_orders_save(200000000002, NULL, NULL, jsonb_build_object('customer_id', acc, 'production_date', (current_date + 10)::text, 'production_code', 'MORNING',
     'lines', jsonb_build_array(jsonb_build_object('item_id', (SELECT item_id FROM bps.fnd_items WHERE tenant_id = 200000000002 AND legacy_id = 11608), 'item_description', 'Roll', 'quantity', 1, 'unit_price', 1))));
  s := fnd_health_run(200000000002, 'Manual', 'orders_without_pricebook');
  INSERT INTO _t VALUES ('an upcoming order with no pricing book in effect is an Error', EXISTS (SELECT 1 FROM jsonb_array_elements(fnd_health_findings_get(200000000002)) x WHERE x ->> 'check_code' = 'orders_without_pricebook' AND x ->> 'type' = 'Error' AND (x ->> 'customer_id')::bigint = acc));
  INSERT INTO _t VALUES ('an open Error turns the heart red', fnd_health_status(200000000002) ->> 'state' = 'error');
  INSERT INTO _t VALUES ('the errors column counts it', (SELECT last_errors FROM fnd_health_checks WHERE tenant_id = 200000000002 AND check_code = 'orders_without_pricebook') >= 1);
  UPDATE fnd_customer_pricebooks SET effective_end_date = NULL WHERE customer_id = acc;
  PERFORM fnd_health_run(200000000002, 'Manual', 'orders_without_pricebook');
  INSERT INTO _t VALUES ('covering the delivery date closes the Error', NOT EXISTS (SELECT 1 FROM fnd_health_log WHERE tenant_id = 200000000002 AND check_code = 'orders_without_pricebook' AND customer_id = acc AND fixed_at IS NULL));

  -- a person marks a finding fixed; the next run opens it again if it is still true
  UPDATE fnd_customer_pricebooks SET is_active = false WHERE customer_id = acc;
  PERFORM fnd_health_run(200000000002, 'Manual', 'accounts_without_pricebook');
  SELECT log_id INTO lid FROM fnd_health_log WHERE tenant_id = 200000000002 AND record_id = acc AND check_code = 'accounts_without_pricebook' AND fixed_at IS NULL;
  PERFORM fnd_health_finding_fix(200000000002, lid);
  INSERT INTO _t VALUES ('marking a finding fixed records who', (SELECT fixed_by FROM fnd_health_log WHERE log_id = lid) = 200000174045);
  PERFORM fnd_health_run(200000000002, 'Manual', 'accounts_without_pricebook');
  INSERT INTO _t VALUES ('if the problem is still there the next run opens it again', EXISTS (SELECT 1 FROM fnd_health_log WHERE tenant_id = 200000000002 AND record_id = acc AND check_code = 'accounts_without_pricebook' AND fixed_at IS NULL AND log_id <> lid));

  -- information findings and the unused-book summary
  INSERT INTO _t VALUES ('the unused-books summary is an Information finding with a link',
    EXISTS (SELECT 1 FROM jsonb_array_elements(fnd_health_findings_get(200000000002)) x WHERE x ->> 'check_code' = 'pricebook_unused' AND x ->> 'type' = 'Information' AND x ->> 'link_path' = '/inventory/pricing' AND x ->> 'findings' LIKE 'Found % price book%'));

  -- disabling a check
  PERFORM fnd_health_check_set_enabled(200000000002, 'items_stale', false);
  UPDATE fnd_health_checks SET last_run_at = NULL WHERE tenant_id = 200000000002 AND check_code = 'items_stale';
  PERFORM fnd_health_run(200000000002, 'Manual');
  INSERT INTO _t VALUES ('a disabled check is skipped', (SELECT last_run_at FROM fnd_health_checks WHERE tenant_id = 200000000002 AND check_code = 'items_stale') IS NULL);
  PERFORM fnd_health_check_set_enabled(200000000002, 'items_stale', true);
  RESET ROLE;
END $$;

-- the clerk: can run checks but not disable them
SELECT set_config('request.jwt.claims', NULL, true);
DO $$
DECLARE u bigint; r boolean; s jsonb;
BEGIN
  SELECT v INTO u FROM _id WHERE k='u_cl';
  PERFORM set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
    json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', u))::text, true);
  SET LOCAL ROLE authenticated;
  s := fnd_health_run(200000000002, 'Manual', 'users_without_role');
  INSERT INTO _t VALUES ('a user with Write on Health Checks can run a check', (s ->> 'checks_run')::int = 1);
  BEGIN PERFORM fnd_health_check_set_enabled(200000000002, 'users_without_role', false); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('only an administrator (Approve) can disable a check', r);
  RESET ROLE;
  -- a user with no Health Checks access sees state none and cannot run
  PERFORM set_config('request.jwt.claims', json_build_object('role','authenticated','app_metadata',
    json_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', json_build_array(200000000002), 'app_user_id', 200000174046))::text, true);
  SET LOCAL ROLE authenticated;
  INSERT INTO _t VALUES ('a user without access gets heart state none', fnd_health_status(200000000002) ->> 'state' = 'none');
  BEGIN PERFORM fnd_health_run(200000000002, 'Manual'); r := false; EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a user without access cannot run the checks', r);
  RESET ROLE;
END $$;

-- the schedule function (trusted)
SELECT set_config('request.jwt.claims', NULL, true);
DO $$ BEGIN INSERT INTO _t VALUES ('the scheduled run function works and returns a count', fnd_health_run_due() >= 0); END $$;

SELECT name, CASE WHEN ok THEN 'ok' ELSE 'FAIL' END AS result FROM _t WHERE NOT ok;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM _t;
ROLLBACK;
