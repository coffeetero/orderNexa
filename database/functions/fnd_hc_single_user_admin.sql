-- ============================================================
-- fnd_hc_single_user_admin
-- Health check: the company has fewer than two active user administrators (fnd_user_admin_ids). With one, nobody can clear
-- security To-Dos about that person or check their access (nobody may clear a signal about themselves).
-- Also re-creates fnd_health_catalog with this check added.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_hc_single_user_admin(p_tenant_id bigint)
 RETURNS TABLE(type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
  SELECT 'Warning',
         CASE WHEN n = 0 THEN 'Nobody can manage users.' ELSE 'Only one person can manage users.' END,
         'Give a second trusted person a role that can manage users (Admin > Users), so each can check the other.',
         'TENANT', p_tenant_id, NULL::bigint, '/admin/users'
    FROM (SELECT count(*) AS n FROM bps.fnd_user_admin_ids(p_tenant_id)) a
   WHERE a.n < 2
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_hc_single_user_admin(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_hc_single_user_admin(bigint) TO authenticated, service_role, bps_dev;

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
    ('invoices_need_reprint',       'Invoices changed after printing',          'Data',  'Invoices posted to AR that got a debit or credit memo (order changes) after they were last printed.', true, 160)
  ) v(check_code, name, category, description, runs_before_production, sort_order)
$function$;
