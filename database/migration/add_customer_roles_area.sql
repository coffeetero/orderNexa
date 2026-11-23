-- =====================================================================================
-- Tenant roles and customer roles become two separate areas, so support staff can be given one without the other.
--   admin.roles           : tenant roles (for the tenant's own staff)
--   admin.customer-roles  : customer roles (new area; the Company Administrator role receives it automatically)
-- Customers still see only CUSTOMER roles (portal.roles) and never a tenant role. No new table or column: one new row in fnd_areas.
-- Apply after add_access_my_areas.sql.
-- =====================================================================================
SET search_path = bps, public;

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('admin.customer-roles', 'Admin', 'Customer Roles', 'TENANT', 606)
ON CONFLICT (area_key) DO NOTHING;
UPDATE bps.fnd_areas SET area_name = 'Company Roles' WHERE area_key = 'admin.roles';

DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

DROP POLICY IF EXISTS pol_fnd_roles_read ON bps.fnd_roles;
DROP POLICY IF EXISTS pol_fnd_roles_ins  ON bps.fnd_roles;
DROP POLICY IF EXISTS pol_fnd_roles_upd  ON bps.fnd_roles;
DROP POLICY IF EXISTS pol_fnd_roles_del  ON bps.fnd_roles;

-- Who may act on a role row for an action: tenant roles need admin.roles, customer roles need admin.customer-roles, or a customer
-- administrator (portal.roles) acting inside their own scope on a customer role.
CREATE OR REPLACE FUNCTION bps.fnd_can_manage_role(p_audience text, p_owner_customer_id bigint, p_action text) RETURNS boolean
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT CASE p_audience
    WHEN 'TENANT' THEN bps.fnd_has_access('admin.roles', p_action)
    ELSE bps.fnd_has_access('admin.customer-roles', p_action)
         OR (p_action = 'R' AND bps.fnd_has_access('portal.roles', 'R') AND (p_owner_customer_id IS NULL OR bps.fnd_customer_in_scope(p_owner_customer_id)))
         OR (p_action <> 'R' AND p_owner_customer_id IS NOT NULL AND bps.fnd_has_access('portal.roles', p_action) AND bps.fnd_customer_in_scope(p_owner_customer_id))
  END
$$;
REVOKE EXECUTE ON FUNCTION bps.fnd_can_manage_role(text, bigint, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION bps.fnd_can_manage_role(text, bigint, text) TO authenticated, service_role, bps_dev;

CREATE POLICY pol_fnd_roles_read ON bps.fnd_roles FOR SELECT TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND bps.fnd_can_manage_role(role_audience, owner_customer_id, 'R')));
CREATE POLICY pol_fnd_roles_ins ON bps.fnd_roles FOR INSERT TO authenticated WITH CHECK (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND bps.fnd_can_manage_role(role_audience, owner_customer_id, 'W')));
CREATE POLICY pol_fnd_roles_upd ON bps.fnd_roles FOR UPDATE TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND bps.fnd_can_manage_role(role_audience, owner_customer_id, 'W')))
  WITH CHECK (tenant_id = (SELECT bps.fnd_active_tenant_id()) OR bps.fnd_is_trusted());
CREATE POLICY pol_fnd_roles_del ON bps.fnd_roles FOR DELETE TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND bps.fnd_can_manage_role(role_audience, owner_customer_id, 'D')));

DROP POLICY IF EXISTS pol_fnd_role_access_write ON bps.fnd_role_area_access;
CREATE POLICY pol_fnd_role_access_write ON bps.fnd_role_area_access FOR ALL TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND EXISTS (
    SELECT 1 FROM bps.fnd_roles r WHERE r.role_id = fnd_role_area_access.role_id AND NOT r.is_system
      AND bps.fnd_can_manage_role(r.role_audience, r.owner_customer_id, 'W'))))
  WITH CHECK (bps.fnd_is_trusted() OR tenant_id = (SELECT bps.fnd_active_tenant_id()));
