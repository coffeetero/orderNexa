-- ============================================================
-- Customer administrators manage their own users; a former staff member's email can be released for a new account.
--
-- 1. Ended accounts. A former user's record can be marked ended (fnd_users.ended_at / ended_by): it is kept unchanged for
--    history (same user_id, same email, everything they did stays theirs) but no longer holds the email, so a NEW account
--    (new user_id) can be made with it. Their old sign-in account is retired by the website (disabled, address replaced by a
--    placeholder), so the audit trail of the old sign-in stays with the old record. One user per email now means
--    "not deleted and not ended". fnd_user_release_email ends a deactivated staff member (Company Administrators only).
-- 2. fnd_security_events: things Company Administrators should know about. First kind: EMAIL_REUSE_ATTEMPT, someone tried to
--    add a user whose email belongs to active or former staff here (often the first sign that a person left without
--    anyone deactivating them). Shown on the Dashboard To-Do (fnd_security_signals_get).
-- 3. Customer administrators (portal.users write) add users to their own customer account, invite them, change their
--    role and deactivate them; never their own access, never staff or other customers. Roles: customer roles of the
--    company (not another customer's own roles). New role Customer Staff (orders and history, no Users, Roles or Payments).
--
-- New columns fnd_users.ended_at, fnd_users.ended_by. New table fnd_security_events.
-- Load after migration/add_user_activity_signals.sql. Then load functions/fnd_user_invites.sql, functions/fnd_users_get.sql
-- and functions/fnd_user_email_sync.sql (updated versions).
-- ============================================================
SET search_path = bps, public;

-- ------------------------------------------------------------ 1. ended accounts
ALTER TABLE bps.fnd_users ADD COLUMN IF NOT EXISTS ended_at timestamptz;
ALTER TABLE bps.fnd_users ADD COLUMN IF NOT EXISTS ended_by bigint;
COMMENT ON COLUMN bps.fnd_users.ended_at IS 'The account was ended and its email released for a new account. The record is kept unchanged for history.';

DROP INDEX IF EXISTS bps.fnd_users_email_key;
CREATE UNIQUE INDEX fnd_users_email_key ON bps.fnd_users (lower(email)) WHERE email IS NOT NULL AND deleted_at IS NULL AND ended_at IS NULL;

-- ------------------------------------------------------------ 2. security events
CREATE TABLE IF NOT EXISTS bps.fnd_security_events (
  event_id    bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id   bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  event_type  text   NOT NULL,
  user_id     bigint REFERENCES bps.fnd_users(user_id) ON DELETE CASCADE,
  details     jsonb  NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  bigint,
  resolved_at timestamptz,
  resolved_by bigint
);
COMMENT ON TABLE bps.fnd_security_events IS 'Security events for Company Administrators (Dashboard To-Do). EMAIL_REUSE_ATTEMPT: someone tried to add a user whose email belongs to staff here. Written by functions only.';
CREATE INDEX IF NOT EXISTS idx_fnd_security_events_open ON bps.fnd_security_events (tenant_id, created_at) WHERE resolved_at IS NULL;
ALTER TABLE bps.fnd_security_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_fnd_security_events_read ON bps.fnd_security_events;
CREATE POLICY pol_fnd_security_events_read ON bps.fnd_security_events FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.users', 'R'))));
REVOKE ALL ON bps.fnd_security_events FROM PUBLIC, anon;
GRANT SELECT ON bps.fnd_security_events TO authenticated;
GRANT ALL ON bps.fnd_security_events TO service_role, bps_dev;

-- ------------------------------------------------------------ 3a. Customer Staff role (every company; editable by the company)
CREATE OR REPLACE FUNCTION bps.fnd_tenant_access_seed(p_tenant_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  INSERT INTO bps.fnd_customer_groups (tenant_id, group_name, is_all_customers)
  SELECT p_tenant_id, 'All Customers', true
   WHERE NOT EXISTS (SELECT 1 FROM bps.fnd_customer_groups WHERE tenant_id = p_tenant_id AND is_all_customers);
  INSERT INTO bps.fnd_roles (tenant_id, role_name, role_audience, is_system)
  SELECT p_tenant_id, v.n, v.a, true FROM (VALUES ('Company Administrator','TENANT'),('Customer Administrator','CUSTOMER')) v(n,a)
   WHERE NOT EXISTS (SELECT 1 FROM bps.fnd_roles r WHERE r.tenant_id = p_tenant_id AND r.owner_customer_id IS NULL AND r.role_name = v.n);
  INSERT INTO bps.fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write, can_approve, can_void, can_delete)
  SELECT p_tenant_id, r.role_id, a.area_key, true, true, true, true, true
    FROM bps.fnd_roles r JOIN bps.fnd_areas a ON a.audience = r.role_audience
   WHERE r.tenant_id = p_tenant_id AND r.is_system AND r.owner_customer_id IS NULL
  ON CONFLICT (role_id, area_key) DO UPDATE SET can_read = true, can_write = true, can_approve = true, can_void = true, can_delete = true;

  -- Customer Staff: a customer's ordinary employees. Not a system role, so the company can change it; created once.
  IF NOT EXISTS (SELECT 1 FROM bps.fnd_roles r WHERE r.tenant_id = p_tenant_id AND r.owner_customer_id IS NULL AND r.role_name = 'Customer Staff') THEN
    WITH r AS (INSERT INTO bps.fnd_roles (tenant_id, role_name, role_audience, is_system) VALUES (p_tenant_id, 'Customer Staff', 'CUSTOMER', false) RETURNING role_id)
    INSERT INTO bps.fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write, can_approve, can_void, can_delete)
    SELECT p_tenant_id, r.role_id, v.area, true, v.w, false, false, false
      FROM r, (VALUES ('portal.dashboard', false), ('portal.orders', true), ('portal.order-history', false), ('portal.invoicing', false),
                      ('portal.invoice-history', false), ('portal.documents', false), ('portal.payment-history', false)) v(area, w)
     WHERE EXISTS (SELECT 1 FROM bps.fnd_areas a WHERE a.area_key = v.area);
  END IF;
END $function$;
DO $$ DECLARE t record; BEGIN FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP; END $$;

-- ------------------------------------------------------------ 3b. helpers
-- The customer account(s) a customer administrator looks after (their own account), or none.
CREATE OR REPLACE FUNCTION bps.fnd_portal_admin_accounts() RETURNS bigint[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'bps', 'public' AS $$
  SELECT CASE WHEN bps.fnd_has_access('portal.users', 'W') THEN
    COALESCE((SELECT array_agg(DISTINCT uc.customer_id) FROM bps.fnd_user_customers uc
               WHERE uc.user_id = bps.fnd_current_user_id() AND uc.tenant_id = bps.fnd_active_tenant_id() AND uc.is_active), '{}')
  ELSE '{}'::bigint[] END
$$;
REVOKE EXECUTE ON FUNCTION bps.fnd_portal_admin_accounts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_portal_admin_accounts() TO authenticated, service_role, bps_dev;

-- May the caller manage this user from the customer portal? A customer user of one of the caller's accounts, not the caller.
CREATE OR REPLACE FUNCTION bps.fnd_portal_can_manage(p_tenant_id bigint, p_user_id bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'bps', 'public' AS $$
  SELECT p_user_id IS DISTINCT FROM bps.fnd_current_user_id()
     AND EXISTS (SELECT 1 FROM bps.fnd_users u JOIN bps.fnd_user_customers uc ON uc.user_id = u.user_id AND uc.tenant_id = p_tenant_id
                  WHERE u.user_id = p_user_id AND u.user_type = 'CUSTOMER_USER' AND u.ended_at IS NULL
                    AND uc.customer_id = ANY (bps.fnd_portal_admin_accounts()))
$$;
REVOKE EXECUTE ON FUNCTION bps.fnd_portal_can_manage(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_portal_can_manage(bigint, bigint) TO authenticated, service_role, bps_dev;

-- Roles a customer administrator may give: active customer roles of the company that are not another customer's own roles.
CREATE OR REPLACE FUNCTION bps.fnd_portal_roles_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'bps', 'public' AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('role_id', r.role_id, 'role_name', r.role_name) ORDER BY r.is_system, r.role_name), '[]'::jsonb)
    FROM bps.fnd_roles r
   WHERE r.tenant_id = p_tenant_id AND p_tenant_id = bps.fnd_active_tenant_id() AND r.role_audience = 'CUSTOMER' AND r.is_active
     AND (r.owner_customer_id IS NULL OR r.owner_customer_id = ANY (bps.fnd_portal_admin_accounts()))
     AND cardinality(bps.fnd_portal_admin_accounts()) > 0
$$;
REVOKE EXECUTE ON FUNCTION bps.fnd_portal_roles_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_portal_roles_get(bigint) TO authenticated, service_role, bps_dev;

-- ------------------------------------------------------------ 3c. customer administrator: list, save
CREATE OR REPLACE FUNCTION bps.fnd_portal_users_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'bps', 'public' AS $$
DECLARE v_accounts bigint[];
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  v_accounts := bps.fnd_portal_admin_accounts();
  IF cardinality(v_accounts) = 0 THEN RAISE EXCEPTION 'You are not allowed to manage users' USING ERRCODE = '42501'; END IF;
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'user_id', u.user_id, 'user_name', u.user_name, 'email', u.email,
      'is_active', ut.is_active AND u.is_active, 'is_me', u.user_id = bps.fnd_current_user_id(),
      'status', CASE WHEN bps.fnd_auth_user_signed_in(u.auth_user_id) THEN 'ACTIVE' WHEN u.invited_at IS NOT NULL THEN 'INVITED' ELSE 'NOT_INVITED' END,
      'invited_at', u.invited_at,
      'role_ids', COALESCE((SELECT jsonb_agg(ur.role_id ORDER BY ur.role_id) FROM bps.fnd_user_roles ur WHERE ur.user_id = u.user_id AND ur.tenant_id = p_tenant_id), '[]'::jsonb))
      ORDER BY u.user_name), '[]'::jsonb)
    FROM bps.fnd_users u
    JOIN bps.fnd_user_tenants ut ON ut.user_id = u.user_id AND ut.tenant_id = p_tenant_id
   WHERE u.user_type = 'CUSTOMER_USER' AND u.ended_at IS NULL AND u.deleted_at IS NULL
     AND EXISTS (SELECT 1 FROM bps.fnd_user_customers uc WHERE uc.user_id = u.user_id AND uc.tenant_id = p_tenant_id AND uc.customer_id = ANY (v_accounts)));
END $$;
REVOKE EXECUTE ON FUNCTION bps.fnd_portal_users_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_portal_users_get(bigint) TO authenticated, service_role, bps_dev;

-- Change a customer user's roles and whether they are active. Never one's own; never leaves the account without someone
-- who can manage its users.
CREATE OR REPLACE FUNCTION bps.fnd_portal_user_save(p_tenant_id bigint, p_user_id bigint, p_role_ids bigint[], p_is_active boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'bps', 'public' AS $$
DECLARE v_accounts bigint[]; r bigint;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF p_user_id = bps.fnd_current_user_id() THEN RAISE EXCEPTION 'Ask another administrator to change your own access' USING ERRCODE = '42501'; END IF;
  IF NOT bps.fnd_portal_can_manage(p_tenant_id, p_user_id) THEN RAISE EXCEPTION 'You are not allowed to change this user' USING ERRCODE = '42501'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(COALESCE(p_role_ids, '{}')) x
              WHERE x NOT IN (SELECT (e ->> 'role_id')::bigint FROM jsonb_array_elements(bps.fnd_portal_roles_get(p_tenant_id)) e)) THEN
    RAISE EXCEPTION 'One of the roles cannot be given here';
  END IF;
  v_accounts := bps.fnd_portal_admin_accounts();
  UPDATE bps.fnd_user_tenants SET is_active = COALESCE(p_is_active, is_active), updated_by = bps.fnd_current_user_id()
   WHERE user_id = p_user_id AND tenant_id = p_tenant_id;
  DELETE FROM bps.fnd_user_roles WHERE user_id = p_user_id AND tenant_id = p_tenant_id;
  FOREACH r IN ARRAY COALESCE(p_role_ids, '{}') LOOP
    INSERT INTO bps.fnd_user_roles (tenant_id, user_id, role_id) VALUES (p_tenant_id, p_user_id, r);
  END LOOP;
  -- the account must keep someone (active, with a login) who can manage its users
  IF NOT EXISTS (SELECT 1 FROM bps.fnd_users u
                   JOIN bps.fnd_user_tenants ut ON ut.user_id = u.user_id AND ut.tenant_id = p_tenant_id AND ut.is_active
                   JOIN bps.fnd_user_customers uc ON uc.user_id = u.user_id AND uc.tenant_id = p_tenant_id AND uc.is_active AND uc.customer_id = ANY (v_accounts)
                   JOIN bps.fnd_user_roles ur ON ur.user_id = u.user_id AND ur.tenant_id = p_tenant_id
                   JOIN bps.fnd_role_area_access a ON a.role_id = ur.role_id AND a.area_key = 'portal.users' AND a.can_write
                  WHERE u.is_active AND u.ended_at IS NULL AND u.auth_user_id IS NOT NULL) THEN
    RAISE EXCEPTION 'This would leave nobody able to manage your users';
  END IF;
END $$;
REVOKE EXECUTE ON FUNCTION bps.fnd_portal_user_save(bigint, bigint, bigint[], boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_portal_user_save(bigint, bigint, bigint[], boolean) TO authenticated, service_role, bps_dev;

-- ------------------------------------------------------------ 3d. adding users
-- fnd_user_create (staff and customer administrators) is in functions/fnd_user_invites.sql: load it after this file.

-- Records that someone tried to add a user whose email belongs to staff of this company (after fnd_user_create refused it,
-- in its own call so the record is kept). Only records a real holder; one open event per staff member and customer.
CREATE OR REPLACE FUNCTION bps.fnd_email_conflict_record(p_tenant_id bigint, p_email text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'bps', 'public' AS $$
DECLARE v_holder record; v_me bigint := bps.fnd_current_user_id(); v_accounts bigint[] := bps.fnd_portal_admin_accounts(); v_cus record;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.users', 'W') AND cardinality(v_accounts) = 0 THEN RETURN; END IF;
  SELECT u.user_id, u.user_name, u.email INTO v_holder FROM bps.fnd_users u JOIN bps.fnd_user_tenants ut ON ut.user_id = u.user_id AND ut.tenant_id = p_tenant_id
   WHERE lower(u.email) = lower(btrim(p_email)) AND u.user_type = 'TENANCY_USER' AND u.deleted_at IS NULL AND u.ended_at IS NULL;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT c.customer_id, c.customer_name INTO v_cus FROM bps.fnd_customers c WHERE c.customer_id = v_accounts[1];
  IF EXISTS (SELECT 1 FROM bps.fnd_security_events e WHERE e.tenant_id = p_tenant_id AND e.event_type = 'EMAIL_REUSE_ATTEMPT' AND e.user_id = v_holder.user_id
               AND e.resolved_at IS NULL AND (e.details ->> 'customer_id') IS NOT DISTINCT FROM v_cus.customer_id::text) THEN RETURN; END IF;
  INSERT INTO bps.fnd_security_events (tenant_id, event_type, user_id, details, created_by)
  VALUES (p_tenant_id, 'EMAIL_REUSE_ATTEMPT', v_holder.user_id,
          jsonb_build_object('email', v_holder.email, 'customer_id', v_cus.customer_id, 'customer_name', v_cus.customer_name,
                             'attempted_by', (SELECT user_name FROM bps.fnd_users WHERE user_id = v_me)), v_me);
END $$;
REVOKE EXECUTE ON FUNCTION bps.fnd_email_conflict_record(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_email_conflict_record(bigint, text) TO authenticated, service_role, bps_dev;

-- Ends a deactivated staff member so their email can be used for a new account. Returns their sign-in account id, which
-- the website then retires. Company Administrators only; never oneself; not someone still active here, nor a member of
-- another company (OrderNexa handles that). Settles their open security events.
CREATE OR REPLACE FUNCTION bps.fnd_user_release_email(p_tenant_id bigint, p_user_id bigint) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'bps', 'public' AS $$
DECLARE v_me bigint := bps.fnd_current_user_id(); v_u record;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.users', 'W') THEN RAISE EXCEPTION 'Only user administrators can do this' USING ERRCODE = '42501'; END IF;
  IF p_user_id = v_me THEN RAISE EXCEPTION 'Ask another administrator to end your own account' USING ERRCODE = '42501'; END IF;
  SELECT u.user_id, u.user_type, u.auth_user_id, u.ended_at,
         EXISTS (SELECT 1 FROM bps.fnd_user_tenants t WHERE t.user_id = u.user_id AND t.tenant_id = p_tenant_id) AS here,
         EXISTS (SELECT 1 FROM bps.fnd_user_tenants t WHERE t.user_id = u.user_id AND t.tenant_id = p_tenant_id AND t.is_active) AS active_here,
         EXISTS (SELECT 1 FROM bps.fnd_user_tenants t WHERE t.user_id = u.user_id AND t.tenant_id <> p_tenant_id) AS elsewhere
    INTO v_u FROM bps.fnd_users u WHERE u.user_id = p_user_id AND u.deleted_at IS NULL;
  IF NOT FOUND OR NOT v_u.here OR v_u.user_type <> 'TENANCY_USER' THEN RAISE EXCEPTION 'Staff member not found in this company'; END IF;
  IF v_u.active_here THEN RAISE EXCEPTION 'Deactivate this person first'; END IF;
  IF v_u.elsewhere THEN RAISE EXCEPTION 'This person also belongs to another company. Contact OrderNexa to release the email.'; END IF;
  IF v_u.ended_at IS NULL THEN
    UPDATE bps.fnd_users SET ended_at = now(), ended_by = v_me, updated_by = v_me WHERE user_id = p_user_id;
  END IF;
  UPDATE bps.fnd_security_events SET resolved_at = now(), resolved_by = v_me
   WHERE tenant_id = p_tenant_id AND user_id = p_user_id AND resolved_at IS NULL;
  RETURN v_u.auth_user_id;
END $$;
REVOKE EXECUTE ON FUNCTION bps.fnd_user_release_email(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_user_release_email(bigint, bigint) TO authenticated, service_role, bps_dev;
