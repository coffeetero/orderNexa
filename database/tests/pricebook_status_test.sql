-- ============================================================
-- SQL tests for pricing book status, default dates, approver, who/when disabled, and the unused-years company setting.
-- One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q < database/tests/pricebook_status_test.sql
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _ids (k text PRIMARY KEY, v bigint);
GRANT ALL ON _t, _ids TO PUBLIC;

DO $$
DECLARE r_cl bigint; uCl bigint;
BEGIN
  INSERT INTO fnd_roles (tenant_id, role_name, role_audience) VALUES (200000000002, 'zz pricing clerk', 'TENANT') RETURNING role_id INTO r_cl;
  INSERT INTO fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write) VALUES (200000000002, r_cl, 'inventory.pricing', true, true);
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (200000000002, gen_random_uuid(), 'zz pricing clerk', 'TENANCY_USER') RETURNING user_id INTO uCl;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (200000000002, uCl);
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id) VALUES (200000000002, uCl, r_cl);
  INSERT INTO _ids VALUES ('uCl', uCl);
END $$;

-- ── last used refresh (trusted) ──────────────────────────────────────────────
DO $$
DECLARE pb bigint; want date; got date; n int;
BEGIN
  SELECT pricebook_id, last_used_date INTO pb, want FROM fnd_pricebooks WHERE tenant_id = 200000000002 AND last_used_date IS NOT NULL ORDER BY pricebook_id LIMIT 1;
  UPDATE fnd_pricebooks SET last_used_date = NULL WHERE pricebook_id = pb;
  n := fnd_pricebooks_last_used_refresh(200000000002);
  SELECT last_used_date INTO got FROM fnd_pricebooks WHERE pricebook_id = pb;
  INSERT INTO _t VALUES ('the refresh restores a book''s last used date from its customers'' orders', got = want AND n >= 1);
  INSERT INTO _t VALUES ('a second refresh changes nothing', fnd_pricebooks_last_used_refresh(200000000002) = 0);
END $$;

-- ── as the staff administrator ───────────────────────────────────────────────
DO $$
DECLARE id bigint; b jsonb; r boolean; s jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object('app_metadata', jsonb_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', jsonb_build_array(200000000002), 'app_user_id', 200000174045))::text, true);
  SET LOCAL ROLE authenticated;

  id := fnd_pricebook_save(200000000002, jsonb_build_object('pricebook_name', 'zz Spring', 'status', 'Scheduled', 'effective_start_date', '2027-03-01', 'effective_end_date', '2027-05-31'));
  SELECT x INTO b FROM jsonb_array_elements(fnd_pricebooks_list_get(200000000002)) x WHERE (x ->> 'pricebook_id')::bigint = id;
  INSERT INTO _t VALUES ('a new book keeps its status and default dates', b ->> 'status' = 'Scheduled' AND b ->> 'effective_start_date' = '2027-03-01' AND b ->> 'effective_end_date' = '2027-05-31');
  INSERT INTO _t VALUES ('a book that is not approved has no approver', b ->> 'approved_by_name' IS NULL);

  BEGIN PERFORM fnd_pricebook_save(200000000002, jsonb_build_object('pricebook_id', id, 'pricebook_name', 'zz Spring', 'effective_start_date', '2027-06-01', 'effective_end_date', '2027-05-01')); r := false;
  EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('a To date before the From date is refused', r);

  BEGIN PERFORM fnd_pricebook_save(200000000002, jsonb_build_object('pricebook_id', id, 'pricebook_name', 'zz Spring', 'status', 'Bogus')); r := false;
  EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('an unknown status is refused', r);

  PERFORM fnd_pricebook_save(200000000002, jsonb_build_object('pricebook_id', id, 'pricebook_name', 'zz Spring', 'status', 'Approved'));
  SELECT x INTO b FROM jsonb_array_elements(fnd_pricebooks_list_get(200000000002)) x WHERE (x ->> 'pricebook_id')::bigint = id;
  INSERT INTO _t VALUES ('setting Approved records the approver', b ->> 'approved_by_name' IS NOT NULL AND b ->> 'approved_at' IS NOT NULL);

  PERFORM fnd_pricebook_save(200000000002, jsonb_build_object('pricebook_id', id, 'pricebook_name', 'zz Spring', 'status', 'Approved', 'is_active', false));
  SELECT x INTO b FROM jsonb_array_elements(fnd_pricebooks_list_get(200000000002)) x WHERE (x ->> 'pricebook_id')::bigint = id;
  INSERT INTO _t VALUES ('disabling a book records when and who', b ->> 'disabled_at' IS NOT NULL AND b ->> 'disabled_by_name' IS NOT NULL);

  PERFORM fnd_pricebook_save(200000000002, jsonb_build_object('pricebook_id', id, 'pricebook_name', 'zz Spring', 'status', 'Draft', 'is_active', true));
  SELECT x INTO b FROM jsonb_array_elements(fnd_pricebooks_list_get(200000000002)) x WHERE (x ->> 'pricebook_id')::bigint = id;
  INSERT INTO _t VALUES ('enabling clears the disabled stamp and a Draft clears the approver', b ->> 'disabled_at' IS NULL AND b ->> 'approved_by_name' IS NULL);

  INSERT INTO _ids VALUES ('pb', id);
  INSERT INTO _t VALUES ('a book with no customers and no orders is stale', (SELECT (x ->> 'is_stale')::boolean FROM jsonb_array_elements(fnd_pricebooks_list_get(200000000002)) x WHERE (x ->> 'pricebook_id')::bigint = id));
  SELECT x INTO b FROM jsonb_array_elements(fnd_customer_pricebooks_get(200000000002, NULL) -> 'pricebooks') x WHERE (x ->> 'pricebook_id')::bigint = id;
  INSERT INTO _t VALUES ('the customer Pricing tab list carries the book dates', b ->> 'effective_start_date' = '2027-03-01');

  s := fnd_pricing_settings_get(200000000002);
  INSERT INTO _t VALUES ('unused years defaults to 2', (s ->> 'pricebook_unused_years')::int = 2);
  s := fnd_pricing_settings_save(200000000002, '{"pricebook_unused_years": 3}'::jsonb);
  INSERT INTO _t VALUES ('unused years can be changed', (s ->> 'pricebook_unused_years')::int = 3);
  BEGIN PERFORM fnd_pricing_settings_save(200000000002, '{"pricebook_unused_years": 0}'::jsonb); r := false;
  EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('unused years below 1 is refused', r);
  RESET ROLE;
END $$;

-- ── a pricing clerk without Approve rights ───────────────────────────────────
DO $$
DECLARE r boolean; uCl bigint; id bigint;
BEGIN
  SELECT v INTO uCl FROM _ids WHERE k = 'uCl'; SELECT v INTO id FROM _ids WHERE k = 'pb';
  PERFORM set_config('request.jwt.claims', jsonb_build_object('app_metadata', jsonb_build_object('tenant_id', 200000000002, 'allowed_tenant_ids', jsonb_build_array(200000000002), 'app_user_id', uCl))::text, true);
  SET LOCAL ROLE authenticated;
  PERFORM fnd_pricebook_save(200000000002, jsonb_build_object('pricebook_id', id, 'pricebook_name', 'zz Spring', 'status', 'Scheduled'));
  INSERT INTO _t VALUES ('a clerk can save a book as Scheduled', true);
  BEGIN PERFORM fnd_pricebook_save(200000000002, jsonb_build_object('pricebook_id', id, 'pricebook_name', 'zz Spring', 'status', 'Approved')); r := false;
  EXCEPTION WHEN OTHERS THEN r := true; END;
  INSERT INTO _t VALUES ('only a pricing approver can set a book to Approved', r);
  RESET ROLE;
END $$;

SELECT name, CASE WHEN ok THEN 'ok' ELSE 'FAIL' END AS result FROM _t WHERE NOT ok;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed FROM _t;
ROLLBACK;
