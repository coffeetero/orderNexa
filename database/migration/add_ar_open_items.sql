-- ============================================================
-- Open AR items: bps.ar_open_items holds only the invoices, credit memos and payments with money still open, and what is open on each.
-- The dashboard, AR aging and statements for today read it (a few hundred rows) instead of recalculating every document since 2000.
-- A row appears when a document is issued or a payment posted, changes as payments and credits are applied, unapplied or voided,
-- and is deleted when the balance reaches 0 (or the invoice is cancelled). Triggers on ar_transactions, ar_payments,
-- ar_payment_applications and ar_credit_applications keep it current, so every screen, function and data load that writes those tables
-- is covered. Never edited by hand. Reports for an earlier date still recalculate from the documents (ar_report_open_items_full).
-- The health check ar_open_items_drift compares the table with a full recalculation.
--
-- Load first: functions/ar_open_items_refresh.sql, ar_report_open_items.sql, fnd_hc_ar_open_items_drift.sql
-- Then this file. It fills the table for every company (about 1 s for Alpine locally).
-- ============================================================
SET search_path = bps, public;

CREATE TABLE IF NOT EXISTS bps.ar_open_items (
  ar_open_item_id   bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id         bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  ar_transaction_id bigint REFERENCES bps.ar_transactions(ar_transaction_id) ON DELETE CASCADE,
  ar_payment_id     bigint REFERENCES bps.ar_payments(ar_payment_id) ON DELETE CASCADE,
  customer_id       bigint NOT NULL,
  open_amount       numeric(14,4) NOT NULL CONSTRAINT chk_ar_open_items_amount CHECK (open_amount <> 0),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_ar_open_items_one_document CHECK ((ar_transaction_id IS NULL) <> (ar_payment_id IS NULL))
);
COMMENT ON TABLE bps.ar_open_items IS 'Invoices, credit memos and payments with money still open, and how much (positive = owed, negative = credit). Kept by triggers (ar_open_items_refresh); never edited by hand.';
CREATE UNIQUE INDEX IF NOT EXISTS uq_ar_open_items_transaction ON bps.ar_open_items (tenant_id, ar_transaction_id) WHERE ar_transaction_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_ar_open_items_payment ON bps.ar_open_items (tenant_id, ar_payment_id) WHERE ar_payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ar_open_items_customer ON bps.ar_open_items (tenant_id, customer_id);

-- Read like invoices; no write policies (only the SECURITY DEFINER refresh writes it).
ALTER TABLE bps.ar_open_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_ar_open_items_read ON bps.ar_open_items;
CREATE POLICY pol_ar_open_items_read ON bps.ar_open_items FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access_any('{financials.ar,financials.aging,financials.statements,financials.credits,financials.payments,financials.sales,production.packaging,production.process,production.deliveries,portal.invoicing,portal.invoice-history}'::text[], 'R'::text))
    AND ((SELECT bps.fnd_scope_is_all()) OR customer_id = ANY (COALESCE((SELECT bps.fnd_scope_customer_ids()), '{}'::bigint[])))));
REVOKE ALL ON bps.ar_open_items FROM PUBLIC, anon;
GRANT SELECT ON bps.ar_open_items TO authenticated;
GRANT ALL ON bps.ar_open_items TO service_role, bps_dev;

-- Triggers: one per event (a statement trigger with transition tables takes a single event).
DO $$
DECLARE t record; ev text;
BEGIN
  FOR t IN SELECT * FROM (VALUES ('ar_transactions', 'ar_open_items_trg_transactions'), ('ar_payments', 'ar_open_items_trg_payments'),
                                 ('ar_payment_applications', 'ar_open_items_trg_payment_applications'),
                                 ('ar_credit_applications', 'ar_open_items_trg_credit_applications')) v(tbl, fn)
  LOOP
    FOREACH ev IN ARRAY ARRAY['insert', 'update', 'delete'] LOOP
      EXECUTE format('DROP TRIGGER IF EXISTS trg_%1$s_open_items_%2$s ON bps.%1$s', t.tbl, ev);
      EXECUTE format('CREATE TRIGGER trg_%1$s_open_items_%2$s AFTER %3$s ON bps.%1$s REFERENCING %4$s FOR EACH STATEMENT EXECUTE FUNCTION bps.%5$s()',
                     t.tbl, ev, upper(ev),
                     CASE ev WHEN 'insert' THEN 'NEW TABLE AS new_rows' WHEN 'delete' THEN 'OLD TABLE AS old_rows'
                             ELSE 'OLD TABLE AS old_rows NEW TABLE AS new_rows' END, t.fn);
    END LOOP;
  END LOOP;
END $$;

-- Health check entry.
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
    ('ar_open_items_drift',         'Open balances out of step',                 'Data',  'Invoices and payments whose stored open balance (used by the dashboard, aging and statements for today) differs from a full recalculation.', false, 150)
  ) v(check_code, name, category, description, runs_before_production, sort_order)
$function$;

-- Fill for every company.
DO $$
DECLARE r record;
BEGIN
  PERFORM set_config('statement_timeout', '0', true);
  FOR r IN SELECT tenant_id FROM bps.fnd_tenants LOOP
    PERFORM bps.ar_open_items_refresh(r.tenant_id,
      (SELECT array_agg(ar_transaction_id) FROM bps.ar_transactions WHERE tenant_id = r.tenant_id),
      (SELECT array_agg(ar_payment_id) FROM bps.ar_payments WHERE tenant_id = r.tenant_id));
  END LOOP;
END $$;
