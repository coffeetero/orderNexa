-- ============================================================
-- Post Orders to Production / Post Orders to AR (2026-11-27).
--   Post Orders to Production (om_production_run_process, was "Process run") builds shipments and DRAFT invoices and can
--   be run again any time before shipping. Post Orders to AR (om_invoices_post_to_ar) is the only step that gives an
--   invoice its number. Printing no longer numbers invoices: drafts print marked DRAFT (for customer approval).
--   fnd_tenants.accounting_rules  STRICT (default): an invoice posted to AR is never changed; order changes found when
--                                 posting to production again become debit memos (DM, more) and credit memos (CM, less)
--                                 applied to the invoice. RELAXED: the invoice itself is updated.
--   ar_transactions.printed_at    last time the invoice was printed (Packaging List or Print Invoices).
--   Sequence debit_memo_number    DM-###### for every company.
--   Health check invoices_need_reprint: invoices with a memo made after they were last printed.
-- Then load: functions/om_production_run_process.sql, om_invoices_post_to_ar.sql, om_report_packaging_issue.sql,
--   ar_invoices_print_get.sql, ar_invoices_mark_printed.sql, fnd_accounting_settings_get.sql, fnd_accounting_settings_save.sql,
--   fnd_hc_invoices_need_reprint.sql
-- ============================================================
SET search_path = bps, public;

ALTER TABLE bps.fnd_tenants ADD COLUMN IF NOT EXISTS accounting_rules text NOT NULL DEFAULT 'STRICT';
ALTER TABLE bps.fnd_tenants DROP CONSTRAINT IF EXISTS chk_fnd_tenants_accounting_rules;
ALTER TABLE bps.fnd_tenants ADD CONSTRAINT chk_fnd_tenants_accounting_rules CHECK (accounting_rules IN ('STRICT', 'RELAXED'));
COMMENT ON COLUMN bps.fnd_tenants.accounting_rules IS
  'STRICT: invoices posted to AR are never changed; order changes become debit/credit memos applied to the invoice. RELAXED: the invoice is updated.';

ALTER TABLE bps.ar_transactions ADD COLUMN IF NOT EXISTS printed_at timestamptz;
COMMENT ON COLUMN bps.ar_transactions.printed_at IS 'Last time the invoice was printed (Packaging List or Print Invoices).';

INSERT INTO bps.fnd_tenant_sequences (tenant_id, sequence_name, start_value, next_value, mask)
SELECT t.tenant_id, 'debit_memo_number', 1000, 1000, 'DM-######' FROM bps.fnd_tenants t
ON CONFLICT (tenant_id, sequence_name) DO NOTHING;

-- ---------- Accounting rules setting (Admin > Production Settings) ----------
CREATE OR REPLACE FUNCTION bps.fnd_accounting_settings_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN (SELECT jsonb_build_object('accounting_rules', accounting_rules) FROM bps.fnd_tenants WHERE tenant_id = p_tenant_id);
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_accounting_settings_save(p_tenant_id bigint, p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_rules text := UPPER(NULLIF(TRIM(p_payload ->> 'accounting_rules'), ''));
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.production', 'W') THEN RAISE EXCEPTION 'Not authorised to change application settings'; END IF;
  IF v_rules IS NULL OR v_rules NOT IN ('STRICT', 'RELAXED') THEN RAISE EXCEPTION 'Accounting rules must be Strict or Relaxed'; END IF;
  UPDATE bps.fnd_tenants SET accounting_rules = v_rules WHERE tenant_id = p_tenant_id;
  RETURN bps.fnd_accounting_settings_get(p_tenant_id);
END $$;

REVOKE EXECUTE ON FUNCTION bps.fnd_accounting_settings_get(bigint), bps.fnd_accounting_settings_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_accounting_settings_get(bigint), bps.fnd_accounting_settings_save(bigint, jsonb) TO authenticated, service_role, bps_dev;

-- ---------- Health check: invoices changed after printing ----------
CREATE OR REPLACE FUNCTION bps.fnd_hc_invoices_need_reprint(p_tenant_id bigint)
 RETURNS TABLE(type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
  SELECT 'Warning',
         'Invoice ' || t.document_number || ' (' || c.customer_name || ') changed after it was printed: '
           || string_agg(m.document_number, ', ' ORDER BY m.ar_transaction_id) || '.',
         'Print the invoice again (Production > Print Invoices) so the customer gets the full picture.',
         'AR_TRANSACTION', t.ar_transaction_id, t.customer_id, '/production/invoices'
    FROM bps.ar_transactions t
    JOIN bps.fnd_customers c ON c.customer_id = t.customer_id
    JOIN bps.ar_transactions m ON m.applies_to_ar_transaction_id = t.ar_transaction_id AND m.tenant_id = t.tenant_id
                              AND m.transaction_type IN ('DM', 'CM') AND m.status <> 'CANCELLED'
   WHERE t.tenant_id = p_tenant_id AND t.transaction_type = 'INV' AND t.status <> 'CANCELLED'
     AND t.printed_at IS NOT NULL AND m.created_at > t.printed_at
   GROUP BY t.ar_transaction_id, t.document_number, c.customer_name, t.customer_id
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_hc_invoices_need_reprint(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_hc_invoices_need_reprint(bigint) TO authenticated, service_role, bps_dev;

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

DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_health_checks_ensure(r.tenant_id); END LOOP;
END $$;

-- ---------- Screens: Process Run is now Post Orders to Production; new Post Orders to AR (own area, for separation of duties) ----------
UPDATE bps.fnd_areas SET area_name = 'Post Orders to Production' WHERE area_key = 'production.process';
INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('production.post-to-ar', 'Production', 'Post Orders to AR', 'TENANT', 202)
ON CONFLICT (area_key) DO NOTHING;
DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;
