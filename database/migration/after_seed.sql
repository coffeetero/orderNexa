-- ============================================================
-- after_seed: last step of seed_all (run it after any reload of customers, items or orders). 2026-11-24.
-- 1) Restore access.
-- seed_fnd_customers truncates fnd_customers CASCADE, which also empties fnd_roles (owner_customer_id), and with it
-- fnd_user_roles and fnd_role_area_access, plus fnd_user_customers and fnd_customer_group_members. Without this step
-- nobody can use the app after a reload.
-- This puts back what the access model gives every tenant (same as add_access_model_functions.sql):
--   system roles Company Administrator / Customer Administrator with every area, and the All Customers group;
--   tenant users → Company Administrator + All Customers; customer users → Customer Administrator.
-- Not restored (they point at customers whose ids change on a reload): customer-owned roles, customer users' account
-- links (fnd_user_customers), customer group members. Re-attach those in Admin.
-- 2) Refresh fnd_items.last_ordered_date from the order lines (the item reload leaves it empty; the stale-item
--    filters and health checks read it).
-- 3) Inactivate dormant customers (owner decision 2026-11-28): an active account or site with no order (order_date) in the
--    last 2 years, neither its own nor any of its children's, goes inactive. So do its active departments and every active
--    standing order of the customers inactivated. Nothing is reactivated (customers the old system turned off stay off).
--    The health checks only look at active customers.
-- Safe to re-run.
-- ============================================================
SET search_path = bps, public;

DO $$
BEGIN
  PERFORM bps.fnd_tenant_access_seed(tenant_id) FROM bps.fnd_tenants;
  PERFORM bps.fnd_customer_group_effective_rebuild(tenant_id) FROM bps.fnd_tenants;
  INSERT INTO bps.fnd_user_roles (tenant_id, user_id, role_id)
  SELECT ut.tenant_id, u.user_id, r.role_id
    FROM bps.fnd_user_tenants ut JOIN bps.fnd_users u ON u.user_id = ut.user_id
    JOIN bps.fnd_roles r ON r.tenant_id = ut.tenant_id AND r.is_system AND r.owner_customer_id IS NULL
     AND r.role_name = CASE u.user_type WHEN 'TENANCY_USER' THEN 'Company Administrator' WHEN 'CUSTOMER_USER' THEN 'Customer Administrator' END
   WHERE ut.is_active ON CONFLICT DO NOTHING;
  INSERT INTO bps.fnd_user_customer_groups (tenant_id, user_id, group_id)
  SELECT ut.tenant_id, u.user_id, g.group_id
    FROM bps.fnd_user_tenants ut JOIN bps.fnd_users u ON u.user_id = ut.user_id AND u.user_type = 'TENANCY_USER'
    JOIN bps.fnd_customer_groups g ON g.tenant_id = ut.tenant_id AND g.is_all_customers
   WHERE ut.is_active ON CONFLICT DO NOTHING;
END $$;

SELECT bps.fnd_items_last_ordered_refresh(tenant_id) AS items_refreshed FROM bps.fnd_tenants;

SELECT r.role_name, count(ur.user_id) AS users
  FROM bps.fnd_roles r LEFT JOIN bps.fnd_user_roles ur ON ur.role_id = r.role_id
 GROUP BY r.role_name ORDER BY 1;

-- 3) Dormant accounts and sites → inactive, with their departments and standing orders.
DO $$
DECLARE v_customers int; v_departments int; v_standing int;
BEGIN
  CREATE TEMP TABLE tmp_dormant ON COMMIT DROP AS
  WITH RECURSIVE tree AS (            -- every customer with itself and all its descendants
    SELECT customer_id AS root_id, customer_id FROM bps.fnd_customers
    UNION ALL
    SELECT t.root_id, c.customer_id FROM tree t JOIN bps.fnd_customers c ON c.customer_parent_id = t.customer_id
  )
  SELECT c.customer_id FROM bps.fnd_customers c
   WHERE c.is_active AND c.customer_type IN ('ACCOUNT', 'SITE')
     AND NOT EXISTS (SELECT 1 FROM tree t JOIN bps.om_orders o ON o.customer_id = t.customer_id
                      WHERE t.root_id = c.customer_id AND o.order_date >= current_date - interval '2 years');
  UPDATE bps.fnd_customers SET is_active = false WHERE customer_id IN (SELECT customer_id FROM tmp_dormant);
  GET DIAGNOSTICS v_customers = ROW_COUNT;

  INSERT INTO tmp_dormant
  SELECT c.customer_id FROM bps.fnd_customers c
   WHERE c.is_active AND c.customer_type = 'DEPARTMENT' AND c.customer_parent_id IN (SELECT customer_id FROM tmp_dormant);
  UPDATE bps.fnd_customers SET is_active = false
   WHERE is_active AND customer_type = 'DEPARTMENT' AND customer_id IN (SELECT customer_id FROM tmp_dormant);
  GET DIAGNOSTICS v_departments = ROW_COUNT;

  UPDATE bps.om_standing_orders SET is_active = false WHERE is_active AND customer_id IN (SELECT customer_id FROM tmp_dormant);
  GET DIAGNOSTICS v_standing = ROW_COUNT;
  RAISE NOTICE 'Dormant: % accounts/sites, % departments, % standing orders inactivated', v_customers, v_departments, v_standing;
END $$;
