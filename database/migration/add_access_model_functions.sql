-- =====================================================================================
-- Access model, step (a) part 2: access functions, triggers, seeds and RLS for the tables created by
-- add_access_model_tables.sql (apply that file first).
--
-- Rules:
--  * The active tenancy is ONE claim: app_metadata.tenant_id (set at login by the token hook, step (b)).
--    The old allowed_tenant_ids list is not used here. A token without it gets no rows.
--  * A connection with no JWT claims at all (psql, migrations) is trusted, as elsewhere in bps.
--  * Policy pattern for performance: wrap helper calls in (SELECT ...) so Postgres evaluates them once per query.
--  * Deny by default: no role, no group, no access.
-- =====================================================================================
SET search_path = bps, public;

-- ---------- claims helpers ----------
CREATE OR REPLACE FUNCTION bps.fnd_is_trusted() RETURNS boolean
LANGUAGE sql STABLE SET search_path = bps, public AS
$$ SELECT NULLIF(current_setting('request.jwt.claims', true), '') IS NULL $$;

CREATE OR REPLACE FUNCTION bps.fnd_active_tenant_id() RETURNS bigint
LANGUAGE sql STABLE SET search_path = bps, public AS
$$ SELECT NULLIF(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' ->> 'tenant_id', '')::bigint $$;

CREATE OR REPLACE FUNCTION bps.fnd_current_user_id() RETURNS bigint
LANGUAGE sql STABLE SET search_path = bps, public AS
$$ SELECT NULLIF(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' ->> 'app_user_id', '')::bigint $$;

-- ---------- privileges: area + action (R read, W write, A approve, V void, D delete) ----------
CREATE OR REPLACE FUNCTION bps.fnd_has_access(p_area text, p_action text DEFAULT 'R') RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = bps, public AS $$
DECLARE v_tid bigint; v_uid bigint; v_act text := upper(p_action);
BEGIN
  IF v_act NOT IN ('R','W','A','V','D') THEN RAISE EXCEPTION 'fnd_has_access: bad action %', p_action; END IF;
  IF bps.fnd_is_trusted() THEN RETURN true; END IF;
  v_tid := bps.fnd_active_tenant_id();
  v_uid := bps.fnd_current_user_id();
  IF v_tid IS NULL OR v_uid IS NULL THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1
    FROM bps.fnd_user_tenants ut
    JOIN bps.fnd_users u        ON u.user_id = ut.user_id AND u.is_active AND u.deleted_at IS NULL
    JOIN bps.fnd_areas ar       ON ar.area_key = p_area
    JOIN bps.fnd_user_roles ur  ON ur.user_id = u.user_id AND ur.tenant_id = ut.tenant_id
    JOIN bps.fnd_roles r        ON r.role_id = ur.role_id AND r.tenant_id = ut.tenant_id AND r.is_active
    JOIN bps.fnd_role_area_access a ON a.role_id = r.role_id AND a.area_key = p_area
    WHERE ut.user_id = v_uid AND ut.tenant_id = v_tid AND ut.is_active
      AND ar.audience = CASE u.user_type WHEN 'TENANCY_USER' THEN 'TENANT' WHEN 'CUSTOMER_USER' THEN 'CUSTOMER' END
      AND r.role_audience = ar.audience
      AND CASE v_act WHEN 'R' THEN a.can_read WHEN 'W' THEN a.can_write WHEN 'A' THEN a.can_approve
                     WHEN 'V' THEN a.can_void WHEN 'D' THEN a.can_delete END
  );
END $$;

-- ---------- data scope ----------
CREATE OR REPLACE FUNCTION bps.fnd_scope_is_all() RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = bps, public AS $$
DECLARE v_tid bigint; v_uid bigint;
BEGIN
  IF bps.fnd_is_trusted() THEN RETURN true; END IF;
  v_tid := bps.fnd_active_tenant_id(); v_uid := bps.fnd_current_user_id();
  IF v_tid IS NULL OR v_uid IS NULL THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1 FROM bps.fnd_user_tenants ut
    JOIN bps.fnd_users u ON u.user_id = ut.user_id AND u.is_active AND u.deleted_at IS NULL AND u.user_type = 'TENANCY_USER'
    JOIN bps.fnd_user_customer_groups ucg ON ucg.user_id = u.user_id AND ucg.tenant_id = ut.tenant_id
    JOIN bps.fnd_customer_groups g ON g.group_id = ucg.group_id AND g.is_active AND g.is_all_customers
    WHERE ut.user_id = v_uid AND ut.tenant_id = v_tid AND ut.is_active);
END $$;

-- Customers the caller may see when not "all": tenant users via effective groups, customer users via their customers + descendants.
CREATE OR REPLACE FUNCTION bps.fnd_scope_customer_ids() RETURNS bigint[]
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = bps, public AS $$
DECLARE v_tid bigint; v_uid bigint; v_type text; v_ids bigint[];
BEGIN
  IF bps.fnd_is_trusted() THEN RETURN NULL; END IF;     -- callers test fnd_scope_is_all() first
  v_tid := bps.fnd_active_tenant_id(); v_uid := bps.fnd_current_user_id();
  IF v_tid IS NULL OR v_uid IS NULL THEN RETURN ARRAY[]::bigint[]; END IF;
  SELECT u.user_type INTO v_type FROM bps.fnd_users u
    JOIN bps.fnd_user_tenants ut ON ut.user_id = u.user_id AND ut.tenant_id = v_tid AND ut.is_active
   WHERE u.user_id = v_uid AND u.is_active AND u.deleted_at IS NULL;
  IF v_type = 'TENANCY_USER' THEN
    SELECT COALESCE(array_agg(DISTINCT e.customer_id), ARRAY[]::bigint[]) INTO v_ids
      FROM bps.fnd_user_customer_groups ucg
      JOIN bps.fnd_customer_groups g ON g.group_id = ucg.group_id AND g.is_active AND NOT g.is_all_customers
      JOIN bps.fnd_customer_group_effective e ON e.group_id = g.group_id AND e.tenant_id = v_tid
     WHERE ucg.user_id = v_uid AND ucg.tenant_id = v_tid;
  ELSIF v_type = 'CUSTOMER_USER' THEN
    WITH RECURSIVE down AS (
      SELECT uc.customer_id, 0 AS d FROM bps.fnd_user_customers uc
       WHERE uc.user_id = v_uid AND uc.tenant_id = v_tid AND uc.is_active
      UNION
      SELECT c.customer_id, down.d + 1 FROM down JOIN bps.fnd_customers c
        ON c.customer_parent_id = down.customer_id AND c.tenant_id = v_tid WHERE down.d < 20)
    SELECT COALESCE(array_agg(DISTINCT customer_id), ARRAY[]::bigint[]) INTO v_ids FROM down;
  ELSE
    v_ids := ARRAY[]::bigint[];
  END IF;
  RETURN v_ids;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_customer_in_scope(p_customer_id bigint) RETURNS boolean
LANGUAGE sql STABLE SET search_path = bps, public AS
$$ SELECT bps.fnd_scope_is_all() OR p_customer_id = ANY (bps.fnd_scope_customer_ids()) $$;

-- Is this user attached to a customer inside the caller's scope (customer admins managing their own users)?
CREATE OR REPLACE FUNCTION bps.fnd_user_in_customer_scope(p_user_id bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = bps, public AS
$$ SELECT EXISTS (SELECT 1 FROM bps.fnd_user_customers uc
                   WHERE uc.user_id = p_user_id AND uc.tenant_id = bps.fnd_active_tenant_id() AND uc.is_active
                     AND uc.customer_id = ANY (bps.fnd_scope_customer_ids())) $$;

-- ---------- effective groups (own groups, else nearest ancestor's) ----------
CREATE OR REPLACE FUNCTION bps.fnd_customer_group_effective_rebuild(p_tenant_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = bps, public AS $$
BEGIN
  DELETE FROM bps.fnd_customer_group_effective WHERE tenant_id = p_tenant_id;
  WITH RECURSIVE up AS (
    SELECT c.customer_id, c.customer_id AS anc, 0 AS d FROM bps.fnd_customers c WHERE c.tenant_id = p_tenant_id
    UNION ALL
    SELECT up.customer_id, p.customer_parent_id, up.d + 1
      FROM up JOIN bps.fnd_customers p ON p.customer_id = up.anc
     WHERE p.customer_parent_id IS NOT NULL AND up.d < 20),
  hit AS (
    SELECT DISTINCT ON (up.customer_id) up.customer_id, up.anc
      FROM up WHERE EXISTS (SELECT 1 FROM bps.fnd_customer_group_members m WHERE m.customer_id = up.anc)
     ORDER BY up.customer_id, up.d)
  INSERT INTO bps.fnd_customer_group_effective (tenant_id, customer_id, group_id)
  SELECT p_tenant_id, hit.customer_id, m.group_id
    FROM hit JOIN bps.fnd_customer_group_members m ON m.customer_id = hit.anc;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_cgm_before() RETURNS trigger
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_g bps.fnd_customer_groups%ROWTYPE; v_ct bigint;
BEGIN
  SELECT * INTO v_g FROM bps.fnd_customer_groups WHERE group_id = NEW.group_id;
  SELECT tenant_id INTO v_ct FROM bps.fnd_customers WHERE customer_id = NEW.customer_id;
  IF v_g.is_all_customers THEN RAISE EXCEPTION 'The All Customers group has no explicit members'; END IF;
  IF v_g.tenant_id IS DISTINCT FROM NEW.tenant_id OR v_ct IS DISTINCT FROM NEW.tenant_id THEN
    RAISE EXCEPTION 'Group, customer and membership must belong to the same tenant'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_fnd_cgm_before BEFORE INSERT OR UPDATE ON bps.fnd_customer_group_members
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_cgm_before();

CREATE OR REPLACE FUNCTION bps.fnd_cgm_rebuild_ins() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = bps, public AS $$
DECLARE r record;
BEGIN FOR r IN SELECT DISTINCT tenant_id FROM new_rows LOOP PERFORM bps.fnd_customer_group_effective_rebuild(r.tenant_id); END LOOP; RETURN NULL; END $$;
CREATE OR REPLACE FUNCTION bps.fnd_cgm_rebuild_del() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = bps, public AS $$
DECLARE r record;
BEGIN FOR r IN SELECT DISTINCT tenant_id FROM old_rows LOOP PERFORM bps.fnd_customer_group_effective_rebuild(r.tenant_id); END LOOP; RETURN NULL; END $$;
CREATE TRIGGER trg_fnd_cgm_ins AFTER INSERT ON bps.fnd_customer_group_members
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION bps.fnd_cgm_rebuild_ins();
CREATE TRIGGER trg_fnd_cgm_del AFTER DELETE ON bps.fnd_customer_group_members
  REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION bps.fnd_cgm_rebuild_del();

-- A group's members are replaced by deleting and inserting, so an UPDATE of group_id/customer_id is not supported.
CREATE OR REPLACE FUNCTION bps.fnd_cgm_no_update() RETURNS trigger LANGUAGE plpgsql AS
$$ BEGIN RAISE EXCEPTION 'Group membership cannot be updated; delete and re-insert'; END $$;
CREATE TRIGGER trg_fnd_cgm_no_update BEFORE UPDATE ON bps.fnd_customer_group_members
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_cgm_no_update();

-- Customers: a new customer starts with its parent's effective groups; moving a customer rebuilds the tenant.
CREATE OR REPLACE FUNCTION bps.fnd_customers_group_sync() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = bps, public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.customer_parent_id IS NOT NULL THEN
      INSERT INTO bps.fnd_customer_group_effective (tenant_id, customer_id, group_id)
      SELECT NEW.tenant_id, NEW.customer_id, e.group_id
        FROM bps.fnd_customer_group_effective e WHERE e.customer_id = NEW.customer_parent_id;
    END IF;
  ELSIF NEW.customer_parent_id IS DISTINCT FROM OLD.customer_parent_id THEN
    PERFORM bps.fnd_customer_group_effective_rebuild(NEW.tenant_id);
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER trg_fnd_customers_group_ins AFTER INSERT ON bps.fnd_customers
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_customers_group_sync();
CREATE TRIGGER trg_fnd_customers_group_upd AFTER UPDATE OF customer_parent_id ON bps.fnd_customers
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_customers_group_sync();

-- ---------- guard rails on groups, roles and assignments ----------
CREATE OR REPLACE FUNCTION bps.fnd_groups_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.is_all_customers THEN RAISE EXCEPTION 'The All Customers group cannot be deleted'; END IF;
    RETURN OLD;
  END IF;
  IF NEW.is_all_customers IS DISTINCT FROM OLD.is_all_customers OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id THEN
    RAISE EXCEPTION 'is_all_customers and tenant_id cannot be changed'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_fnd_groups_guard BEFORE UPDATE OR DELETE ON bps.fnd_customer_groups
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_groups_guard();

CREATE OR REPLACE FUNCTION bps.fnd_roles_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.is_system THEN RAISE EXCEPTION 'System roles cannot be deleted'; END IF;
    RETURN OLD;
  END IF;
  IF TG_OP = 'UPDATE' AND (NEW.tenant_id IS DISTINCT FROM OLD.tenant_id OR NEW.role_audience IS DISTINCT FROM OLD.role_audience
      OR NEW.owner_customer_id IS DISTINCT FROM OLD.owner_customer_id OR NEW.is_system IS DISTINCT FROM OLD.is_system) THEN
    RAISE EXCEPTION 'tenant_id, role_audience, owner_customer_id and is_system cannot be changed'; END IF;
  IF NEW.owner_customer_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM bps.fnd_customers c WHERE c.customer_id = NEW.owner_customer_id AND c.tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'Role owner customer must belong to the same tenant'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_fnd_roles_guard BEFORE INSERT OR UPDATE OR DELETE ON bps.fnd_roles
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_roles_guard();

-- Role assignment: same tenant, user belongs to the tenant, audience matches the user type, optional single role,
-- and a customer-owned role may only go to users attached to that customer (or beneath it).
CREATE OR REPLACE FUNCTION bps.fnd_user_roles_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = bps, public AS $$
DECLARE v_role bps.fnd_roles%ROWTYPE; v_type text; v_multi boolean; v_aud text;
BEGIN
  SELECT * INTO v_role FROM bps.fnd_roles WHERE role_id = NEW.role_id;
  SELECT user_type INTO v_type FROM bps.fnd_users WHERE user_id = NEW.user_id;
  IF v_role.tenant_id IS DISTINCT FROM NEW.tenant_id THEN RAISE EXCEPTION 'Role belongs to another tenant'; END IF;
  IF NOT EXISTS (SELECT 1 FROM bps.fnd_user_tenants WHERE user_id = NEW.user_id AND tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'User is not a member of this tenant'; END IF;
  v_aud := CASE v_type WHEN 'TENANCY_USER' THEN 'TENANT' WHEN 'CUSTOMER_USER' THEN 'CUSTOMER' END;
  IF v_role.role_audience IS DISTINCT FROM v_aud THEN
    RAISE EXCEPTION 'Role audience % does not match the user type %', v_role.role_audience, v_type; END IF;
  SELECT allow_multiple_roles INTO v_multi FROM bps.fnd_tenants WHERE tenant_id = NEW.tenant_id;
  IF NOT v_multi AND EXISTS (SELECT 1 FROM bps.fnd_user_roles WHERE user_id = NEW.user_id AND tenant_id = NEW.tenant_id AND role_id <> NEW.role_id) THEN
    RAISE EXCEPTION 'This tenant allows one role per user'; END IF;
  IF v_role.owner_customer_id IS NOT NULL AND NOT EXISTS (
      WITH RECURSIVE down AS (SELECT v_role.owner_customer_id AS customer_id, 0 AS d
        UNION SELECT c.customer_id, d + 1 FROM down JOIN bps.fnd_customers c ON c.customer_parent_id = down.customer_id WHERE d < 20)
      SELECT 1 FROM bps.fnd_user_customers uc JOIN down ON down.customer_id = uc.customer_id
       WHERE uc.user_id = NEW.user_id AND uc.is_active) THEN
    RAISE EXCEPTION 'User is not attached to the customer that owns this role'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_fnd_user_roles_guard BEFORE INSERT OR UPDATE ON bps.fnd_user_roles
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_user_roles_guard();

-- Group assignment: tenant users only, same tenant.
CREATE OR REPLACE FUNCTION bps.fnd_ucg_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = bps, public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM bps.fnd_users u JOIN bps.fnd_user_tenants ut ON ut.user_id = u.user_id AND ut.tenant_id = NEW.tenant_id
                  WHERE u.user_id = NEW.user_id AND u.user_type = 'TENANCY_USER') THEN
    RAISE EXCEPTION 'Customer groups apply to tenant users who belong to this tenant'; END IF;
  IF NOT EXISTS (SELECT 1 FROM bps.fnd_customer_groups WHERE group_id = NEW.group_id AND tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'Group belongs to another tenant'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_fnd_ucg_guard BEFORE INSERT OR UPDATE ON bps.fnd_user_customer_groups
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_ucg_guard();

-- Access rows: same tenant, audience of area = audience of role, and a customer admin cannot grant what they do not hold.
CREATE OR REPLACE FUNCTION bps.fnd_role_access_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_role bps.fnd_roles%ROWTYPE; v_aud text;
BEGIN
  SELECT * INTO v_role FROM bps.fnd_roles WHERE role_id = NEW.role_id;
  SELECT audience INTO v_aud FROM bps.fnd_areas WHERE area_key = NEW.area_key;
  IF v_role.tenant_id IS DISTINCT FROM NEW.tenant_id THEN RAISE EXCEPTION 'Role belongs to another tenant'; END IF;
  IF v_role.role_audience IS DISTINCT FROM v_aud THEN RAISE EXCEPTION 'Area audience % does not match role audience %', v_aud, v_role.role_audience; END IF;
  IF v_role.owner_customer_id IS NOT NULL AND NOT bps.fnd_is_trusted() THEN   -- grantor must hold every right they hand out
    IF (NEW.can_read    AND NOT bps.fnd_has_access(NEW.area_key,'R')) OR (NEW.can_write  AND NOT bps.fnd_has_access(NEW.area_key,'W'))
    OR (NEW.can_approve AND NOT bps.fnd_has_access(NEW.area_key,'A')) OR (NEW.can_void   AND NOT bps.fnd_has_access(NEW.area_key,'V'))
    OR (NEW.can_delete  AND NOT bps.fnd_has_access(NEW.area_key,'D')) THEN
      RAISE EXCEPTION 'You cannot grant access you do not hold'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_fnd_role_access_guard BEFORE INSERT OR UPDATE ON bps.fnd_role_area_access
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_role_access_guard();

-- updated_at and audit on the single-key tables
CREATE TRIGGER trg_fnd_customer_groups_set_updated BEFORE UPDATE ON bps.fnd_customer_groups FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
CREATE TRIGGER trg_fnd_roles_set_updated BEFORE UPDATE ON bps.fnd_roles FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
CREATE TRIGGER trg_fnd_customer_groups_audit AFTER INSERT OR DELETE OR UPDATE ON bps.fnd_customer_groups FOR EACH ROW EXECUTE FUNCTION bps.fn_audit_log('group_id');
CREATE TRIGGER trg_fnd_roles_audit AFTER INSERT OR DELETE OR UPDATE ON bps.fnd_roles FOR EACH ROW EXECUTE FUNCTION bps.fn_audit_log('role_id');

-- ---------- area registry (from the menus plus the access-admin screens) ----------
INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order) VALUES
 ('dashboard','Dashboard','Dashboard','TENANT',10),
 ('orders.enter','Orders','Enter Orders','TENANT',100),('orders.manage','Orders','Manage Orders','TENANT',101),
 ('orders.import','Orders','Import Orders','TENANT',102),('orders.standing-mgmt','Orders','Standing Order Mgt','TENANT',103),
 ('orders.standing-post','Orders','Post Standing Orders','TENANT',104),('orders.callup','Orders','Call Up List','TENANT',105),
 ('orders.returns','Orders','Returns & Credits','TENANT',106),
 ('production.analysis','Production','Order Analysis','TENANT',200),('production.estimate','Production','Estimate Production','TENANT',201),
 ('production.process','Production','Process Run','TENANT',202),('production.deliveries','Production','Confirm Deliveries','TENANT',203),
 ('production.report','Production',E'Baker\'s Report','TENANT',204),('production.mixing','Production','Mixing Sheets','TENANT',205),
 ('production.labels','Production','Packing Labels','TENANT',206),('production.packaging','Production','Packaging List','TENANT',207),
 ('production.routes','Production','Route Delivery Report','TENANT',208),
 ('customers.profiles','Customers','Customer Profiles','TENANT',300),('customers.pricing','Customers','Pricing Lists','TENANT',301),
 ('customers.reports','Customers','Customer Reports','TENANT',302),('customers.exports','Customers','Customer Exports','TENANT',303),
 ('inventory.manage','Inventory','Manage Items','TENANT',400),('inventory.item-profile','Inventory','Item Profiles','TENANT',401),
 ('inventory.pricing','Inventory','Pricing Lists','TENANT',402),('inventory.recipes','Inventory','Recipes','TENANT',403),
 ('inventory.costing','Inventory','Costing & COGS','TENANT',404),('inventory.waste','Inventory','Waste Tracking','TENANT',405),
 ('inventory.nutrition','Inventory','Nutritional Analysis','TENANT',406),('inventory.labels','Inventory','Nutrition Labels','TENANT',407),
 ('inventory.reports','Inventory','Inventory Reports','TENANT',408),('inventory.analysis','Inventory','Inventory Analysis','TENANT',409),
 ('financials.ar','Financials','AR Open Balances','TENANT',500),('financials.aging','Financials','AR Aging Report','TENANT',501),
 ('financials.statements','Financials','Customer Statements','TENANT',502),('financials.payments','Financials','Manage Payments','TENANT',503),
 ('financials.cash','Financials','Cash Reconciliation','TENANT',504),('financials.credits','Financials','Enter Credits','TENANT',505),
 ('financials.returns','Financials','Enter Returns','TENANT',506),('financials.sales','Financials','Sales Reports','TENANT',507),
 ('financials.forecast','Financials','Revenue Forecasting','TENANT',508),
 ('admin.appearance','Admin','Appearance','TENANT',600),('admin.production','Admin','Production Settings','TENANT',601),
 ('admin.roles','Admin','Roles & Access','TENANT',602),('admin.users','Admin','Users','TENANT',603),
 ('admin.groups','Admin','Customer Groups','TENANT',604),('admin.channels','Admin','Phone & Messaging Numbers','TENANT',605),
 ('portal.dashboard','Portal','Dashboard','CUSTOMER',1000),('portal.orders','Portal','Manage Orders','CUSTOMER',1001),
 ('portal.order-history','Portal','Order History','CUSTOMER',1002),('portal.invoicing','Portal','Statements','CUSTOMER',1003),
 ('portal.invoice-history','Portal','Invoice History','CUSTOMER',1004),('portal.payments','Portal','Manage Payments','CUSTOMER',1005),
 ('portal.payment-history','Portal','Payment History','CUSTOMER',1006),('portal.users','Portal','Users','CUSTOMER',1007),
 ('portal.roles','Portal','Roles & Access','CUSTOMER',1008)
ON CONFLICT (area_key) DO NOTHING;

-- ---------- per-tenant seed: All Customers group, the two system administrator roles with every area of their audience ----------
CREATE OR REPLACE FUNCTION bps.fnd_tenant_access_seed(p_tenant_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = bps, public AS $$
BEGIN
  INSERT INTO bps.fnd_customer_groups (tenant_id, group_name, is_all_customers)
  SELECT p_tenant_id, 'All Customers', true
   WHERE NOT EXISTS (SELECT 1 FROM bps.fnd_customer_groups WHERE tenant_id = p_tenant_id AND is_all_customers);
  INSERT INTO bps.fnd_roles (tenant_id, role_name, role_audience, is_system)
  SELECT p_tenant_id, v.n, v.a, true FROM (VALUES ('Tenant Administrator','TENANT'),('Customer Administrator','CUSTOMER')) v(n,a)
   WHERE NOT EXISTS (SELECT 1 FROM bps.fnd_roles r WHERE r.tenant_id = p_tenant_id AND r.owner_customer_id IS NULL AND r.role_name = v.n);
  INSERT INTO bps.fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write, can_approve, can_void, can_delete)
  SELECT p_tenant_id, r.role_id, a.area_key, true, true, true, true, true
    FROM bps.fnd_roles r JOIN bps.fnd_areas a ON a.audience = r.role_audience
   WHERE r.tenant_id = p_tenant_id AND r.is_system AND r.owner_customer_id IS NULL
  ON CONFLICT (role_id, area_key) DO UPDATE SET can_read = true, can_write = true, can_approve = true, can_void = true, can_delete = true;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_tenants_access_seed_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = bps, public AS
$$ BEGIN PERFORM bps.fnd_tenant_access_seed(NEW.tenant_id); RETURN NULL; END $$;
CREATE TRIGGER trg_fnd_tenants_access_seed AFTER INSERT ON bps.fnd_tenants
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_tenants_access_seed_trg();

DO $$
DECLARE t record;
BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
  PERFORM bps.fnd_customer_group_effective_rebuild(tenant_id) FROM bps.fnd_tenants;
  -- existing users keep working: tenant users become Tenant Administrator + All Customers, customer users Customer Administrator
  INSERT INTO bps.fnd_user_roles (tenant_id, user_id, role_id)
  SELECT ut.tenant_id, u.user_id, r.role_id
    FROM bps.fnd_user_tenants ut JOIN bps.fnd_users u ON u.user_id = ut.user_id
    JOIN bps.fnd_roles r ON r.tenant_id = ut.tenant_id AND r.is_system AND r.owner_customer_id IS NULL
     AND r.role_name = CASE u.user_type WHEN 'TENANCY_USER' THEN 'Tenant Administrator' WHEN 'CUSTOMER_USER' THEN 'Customer Administrator' END
   WHERE ut.is_active ON CONFLICT DO NOTHING;
  INSERT INTO bps.fnd_user_customer_groups (tenant_id, user_id, group_id)
  SELECT ut.tenant_id, u.user_id, g.group_id
    FROM bps.fnd_user_tenants ut JOIN bps.fnd_users u ON u.user_id = ut.user_id AND u.user_type = 'TENANCY_USER'
    JOIN bps.fnd_customer_groups g ON g.tenant_id = ut.tenant_id AND g.is_all_customers
   WHERE ut.is_active ON CONFLICT DO NOTHING;
END $$;

-- ---------- grants and RLS ----------
GRANT SELECT, INSERT, UPDATE, DELETE ON bps.fnd_customer_groups, bps.fnd_customer_group_members, bps.fnd_user_customer_groups,
  bps.fnd_roles, bps.fnd_user_roles, bps.fnd_role_area_access, bps.fnd_tenant_phone_numbers TO authenticated;
GRANT SELECT ON bps.fnd_customer_group_effective, bps.fnd_areas, bps.fnd_user_active_tenant TO authenticated;
GRANT ALL ON bps.fnd_customer_groups, bps.fnd_customer_group_members, bps.fnd_customer_group_effective, bps.fnd_user_customer_groups,
  bps.fnd_roles, bps.fnd_user_roles, bps.fnd_areas, bps.fnd_role_area_access, bps.fnd_user_active_tenant, bps.fnd_tenant_phone_numbers TO bps_dev;

ALTER TABLE bps.fnd_customer_groups        ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_customer_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_customer_group_effective ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_user_customer_groups   ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_roles                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_user_roles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_areas                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_role_area_access       ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_user_active_tenant     ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_tenant_phone_numbers   ENABLE ROW LEVEL SECURITY;

CREATE POLICY pol_fnd_areas_read ON bps.fnd_areas FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_fnd_user_active_tenant_own ON bps.fnd_user_active_tenant FOR SELECT TO authenticated
  USING (bps.fnd_is_trusted() OR user_id = (SELECT bps.fnd_current_user_id()));

-- Same-pattern policies for tables governed by one tenant-side area.
DO $$
DECLARE r record; ok text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('fnd_customer_groups','admin.groups', true), ('fnd_customer_group_members','admin.groups', true),
      ('fnd_customer_group_effective','admin.groups', false), ('fnd_user_customer_groups','admin.groups', true),
      ('fnd_tenant_phone_numbers','admin.channels', true)) v(tbl, area, writable) LOOP
    ok := format('tenant_id = (SELECT bps.fnd_active_tenant_id())');
    EXECUTE format('CREATE POLICY pol_%s_read ON bps.%I FOR SELECT TO authenticated USING (bps.fnd_is_trusted() OR (%s AND (SELECT bps.fnd_has_access(%L,''R''))))', r.tbl, r.tbl, ok, r.area);
    IF r.writable THEN
      EXECUTE format('CREATE POLICY pol_%s_ins ON bps.%I FOR INSERT TO authenticated WITH CHECK (bps.fnd_is_trusted() OR (%s AND (SELECT bps.fnd_has_access(%L,''W''))))', r.tbl, r.tbl, ok, r.area);
      EXECUTE format('CREATE POLICY pol_%s_upd ON bps.%I FOR UPDATE TO authenticated USING (bps.fnd_is_trusted() OR (%s AND (SELECT bps.fnd_has_access(%L,''W'')))) WITH CHECK (bps.fnd_is_trusted() OR (%s AND (SELECT bps.fnd_has_access(%L,''W''))))', r.tbl, r.tbl, ok, r.area, ok, r.area);
      EXECUTE format('CREATE POLICY pol_%s_del ON bps.%I FOR DELETE TO authenticated USING (bps.fnd_is_trusted() OR (%s AND (SELECT bps.fnd_has_access(%L,''D''))))', r.tbl, r.tbl, ok, r.area);
    END IF;
  END LOOP;
END $$;

-- Roles: tenant administrators manage every role; a customer admin sees the tenant's CUSTOMER roles and manages only
-- roles owned by a customer inside their scope.
CREATE POLICY pol_fnd_roles_read ON bps.fnd_roles FOR SELECT TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (
    (SELECT bps.fnd_has_access('admin.roles','R'))
    OR (role_audience = 'CUSTOMER' AND (SELECT bps.fnd_has_access('portal.roles','R'))
        AND (owner_customer_id IS NULL OR bps.fnd_customer_in_scope(owner_customer_id))))));
CREATE POLICY pol_fnd_roles_ins ON bps.fnd_roles FOR INSERT TO authenticated WITH CHECK (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (
    (SELECT bps.fnd_has_access('admin.roles','W'))
    OR (owner_customer_id IS NOT NULL AND (SELECT bps.fnd_has_access('portal.roles','W')) AND bps.fnd_customer_in_scope(owner_customer_id)))));
CREATE POLICY pol_fnd_roles_upd ON bps.fnd_roles FOR UPDATE TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (
    (SELECT bps.fnd_has_access('admin.roles','W'))
    OR (owner_customer_id IS NOT NULL AND (SELECT bps.fnd_has_access('portal.roles','W')) AND bps.fnd_customer_in_scope(owner_customer_id)))))
  WITH CHECK (tenant_id = (SELECT bps.fnd_active_tenant_id()) OR bps.fnd_is_trusted());
CREATE POLICY pol_fnd_roles_del ON bps.fnd_roles FOR DELETE TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (
    (SELECT bps.fnd_has_access('admin.roles','D'))
    OR (owner_customer_id IS NOT NULL AND (SELECT bps.fnd_has_access('portal.roles','D')) AND bps.fnd_customer_in_scope(owner_customer_id)))));

-- Access rows follow the visibility of their role (subselect honours fnd_roles RLS); writes need roles-write on the matching side.
CREATE POLICY pol_fnd_role_access_read ON bps.fnd_role_area_access FOR SELECT TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND role_id IN (SELECT role_id FROM bps.fnd_roles)));
CREATE POLICY pol_fnd_role_access_write ON bps.fnd_role_area_access FOR ALL TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND EXISTS (
    SELECT 1 FROM bps.fnd_roles r WHERE r.role_id = fnd_role_area_access.role_id AND NOT r.is_system AND (
      (SELECT bps.fnd_has_access('admin.roles','W'))
      OR (r.owner_customer_id IS NOT NULL AND (SELECT bps.fnd_has_access('portal.roles','W')) AND bps.fnd_customer_in_scope(r.owner_customer_id))))))
  WITH CHECK (bps.fnd_is_trusted() OR tenant_id = (SELECT bps.fnd_active_tenant_id()));

-- Role assignments: tenant admins for anyone; customer admins only for users attached inside their own scope.
CREATE POLICY pol_fnd_user_roles_read ON bps.fnd_user_roles FOR SELECT TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (
    (SELECT bps.fnd_has_access('admin.users','R'))
    OR ((SELECT bps.fnd_has_access('portal.users','R')) AND bps.fnd_user_in_customer_scope(user_id)))));
CREATE POLICY pol_fnd_user_roles_ins ON bps.fnd_user_roles FOR INSERT TO authenticated WITH CHECK (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (
    (SELECT bps.fnd_has_access('admin.users','W'))
    OR ((SELECT bps.fnd_has_access('portal.users','W')) AND bps.fnd_user_in_customer_scope(user_id)))));
CREATE POLICY pol_fnd_user_roles_del ON bps.fnd_user_roles FOR DELETE TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (
    (SELECT bps.fnd_has_access('admin.users','D'))
    OR ((SELECT bps.fnd_has_access('portal.users','D')) AND bps.fnd_user_in_customer_scope(user_id)))));
