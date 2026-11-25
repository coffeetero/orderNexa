-- ============================================================
-- Financials › Manage Payments: enter, apply, unapply and void customer payments.
-- Posted payments and applications are never deleted:
--   * ar_payments.voided_at / voided_by / void_reason          a voided payment (e.g. bounced check) keeps its row
--   * ar_payment_applications.reversed_at / reversed_by / reversal_reason
--                                                              an unapplied (or voided) application keeps its row
--   * ar_credit_applications                                   a credit memo (or negative invoice) applied to an invoice,
--                                                              textbook credit application (docs/backlog.md section 4);
--                                                              entered with a payment (often a $0 payment) and reversed with it
-- Reports count an application up to the day it was reversed, and a payment up to the day it was voided, so earlier
-- statements do not change. All new columns are nullable: the migration seed scripts keep working unchanged.
-- Then load: functions/ar_transaction_open_amount.sql, ar_report_open_items.sql, ar_customer_balance_get.sql, fnd_hc_payments_over_applied.sql,
--            ar_payment_open_items_get.sql, ar_payment_allocate.sql, ar_payment_apply.sql, ar_payment_post.sql,
--            ar_payment_unapply.sql, ar_payment_void.sql, ar_payments_search.sql, ar_payment_get.sql
-- ============================================================
SET search_path = bps, public;

ALTER TABLE bps.ar_payments ADD COLUMN IF NOT EXISTS voided_at   timestamptz;
ALTER TABLE bps.ar_payments ADD COLUMN IF NOT EXISTS voided_by   bigint;
ALTER TABLE bps.ar_payments ADD COLUMN IF NOT EXISTS void_reason text;
ALTER TABLE bps.ar_payments DROP CONSTRAINT IF EXISTS chk_ar_payments_void_reason;
ALTER TABLE bps.ar_payments ADD CONSTRAINT chk_ar_payments_void_reason
  CHECK (voided_at IS NULL OR btrim(COALESCE(void_reason, '')) <> '');
COMMENT ON COLUMN bps.ar_payments.voided_at IS 'Set when the payment is voided (bounced check, entered in error). The row is kept; its applications are reversed.';
COMMENT ON COLUMN bps.ar_payments.reference_number IS 'Check number or bank reference. A second live payment of the same customer with the same reference needs confirmation.';

ALTER TABLE bps.ar_payment_applications ADD COLUMN IF NOT EXISTS reversed_at     timestamptz;
ALTER TABLE bps.ar_payment_applications ADD COLUMN IF NOT EXISTS reversed_by     bigint;
ALTER TABLE bps.ar_payment_applications ADD COLUMN IF NOT EXISTS reversal_reason text;
COMMENT ON COLUMN bps.ar_payment_applications.reversed_at IS 'Set when the application is unapplied or its payment voided. Counts in as-of reports before this date only.';

CREATE INDEX IF NOT EXISTS idx_ar_payments_tenant_date ON bps.ar_payments (tenant_id, payment_date DESC);

CREATE TABLE IF NOT EXISTS bps.ar_credit_applications (
  ar_credit_application_id bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id                bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  ar_payment_id            bigint NOT NULL CONSTRAINT fk_ar_credit_applications_payment REFERENCES bps.ar_payments(ar_payment_id) ON DELETE RESTRICT,
  credit_ar_transaction_id bigint NOT NULL CONSTRAINT fk_ar_credit_applications_credit REFERENCES bps.ar_transactions(ar_transaction_id) ON DELETE RESTRICT,
  ar_transaction_id        bigint NOT NULL CONSTRAINT fk_ar_credit_applications_invoice REFERENCES bps.ar_transactions(ar_transaction_id) ON DELETE RESTRICT,
  applied_amount           numeric(14,4) NOT NULL CONSTRAINT chk_ar_credit_applications_amount CHECK (applied_amount > 0),
  applied_at               timestamptz NOT NULL DEFAULT now(),
  reversed_at              timestamptz,
  reversed_by              bigint,
  reversal_reason          text,
  created_at               timestamptz NOT NULL DEFAULT now(),
  created_by               bigint,
  updated_at               timestamptz NOT NULL DEFAULT now(),
  updated_by               bigint,
  CONSTRAINT chk_ar_credit_applications_docs CHECK (credit_ar_transaction_id <> ar_transaction_id)
);
ALTER TABLE bps.ar_credit_applications OWNER TO bps_owner;
COMMENT ON TABLE bps.ar_credit_applications IS
  'A credit memo (or negative invoice) applied to an invoice. Entered with a payment (ar_payment_id, often $0) and reversed with it. Replaces negative payment applications for new entries.';
CREATE INDEX IF NOT EXISTS idx_ar_credit_applications_invoice ON bps.ar_credit_applications (tenant_id, ar_transaction_id);
CREATE INDEX IF NOT EXISTS idx_ar_credit_applications_credit  ON bps.ar_credit_applications (tenant_id, credit_ar_transaction_id);
CREATE INDEX IF NOT EXISTS idx_ar_credit_applications_payment ON bps.ar_credit_applications (tenant_id, ar_payment_id);

DROP TRIGGER IF EXISTS trg_ar_credit_applications_set_updated ON bps.ar_credit_applications;
CREATE TRIGGER trg_ar_credit_applications_set_updated BEFORE UPDATE ON bps.ar_credit_applications
  FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
DROP TRIGGER IF EXISTS trg_ar_credit_applications_audit ON bps.ar_credit_applications;
CREATE TRIGGER trg_ar_credit_applications_audit AFTER INSERT OR UPDATE OR DELETE ON bps.ar_credit_applications
  FOR EACH ROW EXECUTE FUNCTION bps.fn_audit_log('ar_credit_application_id');

-- RLS like ar_payment_applications; no delete policy: credit applications are reversed, never deleted.
ALTER TABLE bps.ar_credit_applications ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON bps.ar_credit_applications TO authenticated;
GRANT ALL ON bps.ar_credit_applications TO bps_dev, service_role;

DROP POLICY IF EXISTS pol_ar_credit_applications_read ON bps.ar_credit_applications;
CREATE POLICY pol_ar_credit_applications_read ON bps.ar_credit_applications FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access_any('{financials.payments,financials.cash,financials.ar,financials.credits}'::text[], 'R'))
    AND EXISTS (SELECT 1 FROM bps.ar_payments p WHERE p.ar_payment_id = ar_credit_applications.ar_payment_id)));

DROP POLICY IF EXISTS pol_ar_credit_applications_ins ON bps.ar_credit_applications;
CREATE POLICY pol_ar_credit_applications_ins ON bps.ar_credit_applications FOR INSERT TO authenticated WITH CHECK (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('financials.payments', 'W'))
    AND EXISTS (SELECT 1 FROM bps.ar_payments p WHERE p.ar_payment_id = ar_credit_applications.ar_payment_id)));

DROP POLICY IF EXISTS pol_ar_credit_applications_upd ON bps.ar_credit_applications;
CREATE POLICY pol_ar_credit_applications_upd ON bps.ar_credit_applications FOR UPDATE TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('financials.payments', 'W'))
    AND EXISTS (SELECT 1 FROM bps.ar_payments p WHERE p.ar_payment_id = ar_credit_applications.ar_payment_id)))
  WITH CHECK ((SELECT bps.fnd_is_trusted()) OR tenant_id = (SELECT bps.fnd_active_tenant_id()));
