-- ============================================================
-- Health checks on customer addresses (owner decision 2026-11-28: the Dashboard's address review becomes health checks).
-- One finding per customer:
--   address_suggested  Addresses Google corrects        an address has a Google suggestion waiting (Accept / Reject on Contacts)
--   address_not_found  Addresses Google can't confirm   an address Google could not place (or only the street/area), not verified
--   address_no_bill    Accounts with no Billing address   an account with addresses, none ticked Billing (departments and sites
--                                                       bill to their account; an account with no address at all is left to
--                                                       accounts_without_address)
--   address_no_ship    Delivered customers with no Shipping address  an account or site, not a pickup customer, with no Shipping
--                                                       address of its own (departments are delivered to their account's or
--                                                       site's address; an account with no address at all is left to
--                                                       accounts_without_address; a site with none is listed here)
-- (Owner rules 2026-11-28: departments need neither; sites and accounts need a Shipping address; accounts need a Billing one.)
-- SECURITY DEFINER: app users have no direct access to the contact tables; tenant and Health Checks access are checked first.
-- Also re-creates fnd_health_catalog with these checks added.
-- ============================================================
DROP FUNCTION IF EXISTS bps.fnd_hc_address_rows(bigint);
CREATE OR REPLACE FUNCTION bps.fnd_hc_address_rows(p_tenant_id bigint)
RETURNS TABLE (customer_id bigint, customer_name text, customer_type text, pickup boolean, own_address boolean,
               suggestions integer, not_found integer, own_bill boolean, own_ship boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.health', 'R') THEN RAISE EXCEPTION 'Not authorised to run health checks'; END IF;
  RETURN QUERY
  WITH cust AS (
    SELECT c.customer_id, c.customer_name, c.customer_type, COALESCE(c.delivery_method_code, '') = 'PICKUP' AS pickup
      FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.is_active
  ), pts AS (
    SELECT k.entity_id, cp.use_as_billing, cp.use_as_shipping, cp.suggested_address, cp.is_verified, cp.geocode_status,
           cp.google_geocode_response -> 'validation' ->> 'status' AS vstatus
      FROM fnd_contacts k JOIN fnd_contact_points cp ON cp.contact_id = k.contact_id AND cp.tenant_id = k.tenant_id
     WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.is_active AND cp.type = 'ADDRESS' AND cp.is_active
  )
  SELECT cu.customer_id, cu.customer_name, cu.customer_type, cu.pickup,
         EXISTS (SELECT 1 FROM pts WHERE pts.entity_id = cu.customer_id),
         (SELECT count(*) FROM pts WHERE pts.entity_id = cu.customer_id AND pts.suggested_address IS NOT NULL)::int,
         (SELECT count(*) FROM pts WHERE pts.entity_id = cu.customer_id AND NOT pts.is_verified AND pts.suggested_address IS NULL
            AND (pts.vstatus IN ('NOT_FOUND', 'UNCONFIRMED') OR (pts.vstatus IS NULL AND pts.geocode_status = 'ZERO_RESULTS')))::int,
         EXISTS (SELECT 1 FROM pts WHERE pts.entity_id = cu.customer_id AND pts.use_as_billing),
         EXISTS (SELECT 1 FROM pts WHERE pts.entity_id = cu.customer_id AND pts.use_as_shipping)
    FROM cust cu;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_address_suggested(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', r.customer_name || CASE WHEN r.suggestions = 1 THEN ': Google suggests a correction to an address.' ELSE ': Google suggests corrections to ' || r.suggestions || ' addresses.' END,
         'Accept or Reject Google''s suggestion on the customer''s Contacts tab.', 'CUSTOMER', r.customer_id, r.customer_id, '/customers?customer=' || r.customer_id
    FROM bps.fnd_hc_address_rows(p_tenant_id) r WHERE r.suggestions > 0
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_address_not_found(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', r.customer_name || CASE WHEN r.not_found = 1 THEN ': Google can''t confirm an address.' ELSE ': Google can''t confirm ' || r.not_found || ' addresses.' END,
         'Check the address against the old system, correct it, or tick Validated on the customer''s Contacts tab.', 'CUSTOMER', r.customer_id, r.customer_id, '/customers?customer=' || r.customer_id
    FROM bps.fnd_hc_address_rows(p_tenant_id) r WHERE r.not_found > 0
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_address_no_bill(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', r.customer_name || ' has no Billing address.',
         'Tick Billing Address on one of the account''s addresses on its Contacts tab.', 'CUSTOMER', r.customer_id, r.customer_id, '/customers?customer=' || r.customer_id
    FROM bps.fnd_hc_address_rows(p_tenant_id) r
   WHERE r.customer_type = 'ACCOUNT' AND r.own_address AND NOT r.own_bill
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_address_no_ship(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', r.customer_name || ' is delivered to but has no Shipping address.',
         'Add the delivery address, or tick Shipping Address on it, on the customer''s Contacts tab (confirm it against the old system).', 'CUSTOMER', r.customer_id, r.customer_id, '/customers?customer=' || r.customer_id
    FROM bps.fnd_hc_address_rows(p_tenant_id) r
   WHERE r.customer_type IN ('ACCOUNT', 'SITE') AND NOT r.pickup AND NOT r.own_ship
     AND NOT (r.customer_type = 'ACCOUNT' AND NOT r.own_address)
$$;

REVOKE EXECUTE ON FUNCTION bps.fnd_hc_address_rows(bigint), bps.fnd_hc_address_suggested(bigint), bps.fnd_hc_address_not_found(bigint),
  bps.fnd_hc_address_no_bill(bigint), bps.fnd_hc_address_no_ship(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_hc_address_rows(bigint), bps.fnd_hc_address_suggested(bigint), bps.fnd_hc_address_not_found(bigint),
  bps.fnd_hc_address_no_bill(bigint), bps.fnd_hc_address_no_ship(bigint) TO authenticated, service_role, bps_dev;

CREATE OR REPLACE FUNCTION bps.fnd_health_catalog()
 RETURNS TABLE(check_code text, name text, category text, description text, runs_before_production boolean, sort_order integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'bps', 'public'
AS $function$
  SELECT * FROM (VALUES
    ('users_without_role',          'Users without a role',                     'Setup', 'Active users who have no role and so can open nothing.', false, 10),
    ('accounts_without_pricebook',  'Accounts without a pricing book',          'Setup', 'Active accounts with no active, Approved pricing book assigned.', false, 20),
    ('accounts_without_contact',    'Accounts without a contact',               'Setup', 'Active accounts with no contact person.', false, 30),
    ('accounts_without_address',    'Accounts without an address',              'Setup', 'Active accounts with no address.', false, 40),
    ('compound_without_components', 'Compound items without components',        'Setup', 'Active compound items that have no components, so nothing is produced for them.', false, 50),
    ('compound_inactive_component', 'Compound items with inactive components',  'Setup', 'Active compound items that include an inactive item.', false, 60),
    ('pricebook_unused',            'Pricing books not used',                    'Setup', 'Active pricing books none of whose customers has ordered within the Stale years (Application Settings > Pricing). Also refreshes each book''s last-used date.', false, 70),
    ('orders_without_pricebook',    'Orders without a pricing book',             'Data',  'Upcoming orders whose account has no active, Approved pricing book in effect for the delivery date.', true, 110),
    ('orders_unpriced_lines',       'Orders with unpriced lines',                'Data',  'Upcoming orders with a line that no pricing book priced.', true, 120),
    ('payments_over_applied',       'Payments applied for more than received',   'Data',  'Payments whose applications to invoices add up to more than the payment amount.', false, 130),
    ('items_stale',                 'Items not ordered',                         'Data',  'Active items not ordered within the Stale years (Application Settings > Pricing). Also refreshes each item''s last-ordered date.', false, 140),
    ('ar_open_items_drift',         'Open balances out of step',                 'Data',  'Invoices and payments whose stored open balance (used by the dashboard, aging and statements for today) differs from a full recalculation.', false, 150),
    ('single_user_admin',           'Only one user administrator',              'Setup', 'The company has only one active person who can manage users, so nobody can check their access or clear security To-Dos about them.', false, 80),
    ('invoices_need_reprint',       'Invoices changed after printing',          'Data',  'Invoices posted to AR that got a debit or credit memo (order changes) after they were last printed.', true, 160),
    ('address_suggested',           'Addresses Google corrects',                'Data',  'Customer addresses with a Google suggestion waiting to be accepted or rejected.', false, 170),
    ('address_not_found',           'Addresses Google can''t confirm',          'Data',  'Customer addresses Google could not place exactly and nobody has marked Validated. Statements are mailed to the Billing address.', false, 180),
    ('address_no_bill',             'Accounts with no Billing address',         'Data',  'Active accounts with addresses but none ticked as the Billing address used on invoices and statements (departments and sites bill to their account).', false, 190),
    ('address_no_ship',             'Delivered customers with no Shipping address', 'Data', 'Active accounts and sites that are not pickup customers and have no address of their own ticked as the Shipping address (departments are delivered to their account''s or site''s address).', false, 200)
  ) v(check_code, name, category, description, runs_before_production, sort_order)
$function$;
