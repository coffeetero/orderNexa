-- Order processing (Phase 2 of order-to-invoice): shipments, invoice drafts per run, numbering settings.
-- Requires add_order_runs.sql first. Generated from the files named below; apply in this order. Local only.
-- om_order_shipments (flat event table, empty) becomes om_shipment_lines under the new om_shipments header.
SET search_path = bps, public;

-- ===== schema/om_shipments.sql =====
-- ============================================================
-- OM_SHIPMENTS  –  Shipment header: how and when goods move to one ship-to customer
--
-- Created PLANNED by "Process run" (om_production_run_process): one per run + ship-to customer + delivery method.
-- Lines: om_shipment_lines. delivery_method_code -> om_delivery_methods (NULL until a method is known).
-- delivery_cost is what the bakery pays (carrier bill, Uber fare); what the customer is billed is om_orders.delivery_charge.
-- shipment_number comes from the tenant sequence 'shipment_number' (fnd_tenant_sequences).
--
-- shipment_id uses fnd_entity_id_seq.
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- Run after: om_production_runs.sql, om_delivery_methods.sql, fnd_customers.sql. Policies: ../policies/om_shipments_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS om_shipments (
    tenant_id             BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    shipment_id           BIGINT        PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    production_run_id     BIGINT        NOT NULL REFERENCES om_production_runs(production_run_id) ON DELETE CASCADE,
    ship_to_customer_id   BIGINT        NOT NULL REFERENCES fnd_customers(customer_id),
    shipment_number       TEXT          NOT NULL,
    delivery_date         DATE          NOT NULL,
    delivery_method_code  TEXT,
    carrier               TEXT,
    tracking_reference    TEXT,
    route                 TEXT,
    delivery_cost         NUMERIC(12,2),
    shipment_status       TEXT          NOT NULL DEFAULT 'PLANNED',
    shipped_at            TIMESTAMPTZ,
    shipped_by            BIGINT,

    created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    created_by            BIGINT,
    updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_by            BIGINT,

    CONSTRAINT fk_om_shipments_delivery_method
        FOREIGN KEY (tenant_id, delivery_method_code) REFERENCES om_delivery_methods (tenant_id, delivery_method_code),
    CONSTRAINT uq_om_shipments_number UNIQUE (tenant_id, shipment_number),
    CONSTRAINT uq_om_shipments_run_ship_to_method
        UNIQUE NULLS NOT DISTINCT (tenant_id, production_run_id, ship_to_customer_id, delivery_method_code),
    CONSTRAINT chk_om_shipments_status CHECK (shipment_status IN ('PLANNED', 'SHIPPED', 'DELIVERED', 'CANCELLED')),
    CONSTRAINT chk_om_shipments_cost CHECK (delivery_cost IS NULL OR delivery_cost >= 0)
);

ALTER TABLE om_shipments OWNER TO bps_owner;

CREATE INDEX IF NOT EXISTS idx_om_shipments_run ON om_shipments (tenant_id, production_run_id);
CREATE INDEX IF NOT EXISTS idx_om_shipments_ship_to ON om_shipments (tenant_id, ship_to_customer_id);

DROP TRIGGER IF EXISTS trg_om_shipments_set_updated ON om_shipments;
CREATE TRIGGER trg_om_shipments_set_updated
    BEFORE UPDATE ON om_shipments
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_om_shipments_audit ON om_shipments;
CREATE TRIGGER trg_om_shipments_audit
    AFTER INSERT OR UPDATE OR DELETE ON om_shipments
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('shipment_id');

COMMENT ON TABLE om_shipments IS
    'Shipment header (one ship-to customer, one delivery method, one run). PLANNED at processing; SHIPPED/DELIVERED at confirmation.';

-- ===== transition: om_order_shipments -> om_shipment_lines =====
DO $$
BEGIN
    IF to_regclass('bps.om_order_shipments') IS NOT NULL AND to_regclass('bps.om_shipment_lines') IS NULL THEN
        IF (SELECT COUNT(*) FROM bps.om_order_shipments) > 0 THEN
            RAISE EXCEPTION 'om_order_shipments has rows; migrate them into om_shipments/om_shipment_lines before renaming';
        END IF;
        DROP TRIGGER IF EXISTS trg_om_order_shipments_set_updated ON bps.om_order_shipments;
        DROP TRIGGER IF EXISTS trg_om_order_shipments_audit ON bps.om_order_shipments;
        DROP POLICY IF EXISTS pol_om_order_shipments_tenant ON bps.om_order_shipments;
        DROP INDEX IF EXISTS bps.idx_om_order_shipments_tenant_order;
        DROP INDEX IF EXISTS bps.idx_om_order_shipments_line;
        ALTER TABLE bps.om_order_shipments RENAME TO om_shipment_lines;
        ALTER TABLE bps.om_shipment_lines RENAME COLUMN order_shipment_id TO shipment_line_id;
        ALTER INDEX bps.om_order_shipments_pkey RENAME TO om_shipment_lines_pkey;
        ALTER TABLE bps.om_shipment_lines
            DROP COLUMN production_date, DROP COLUMN production_code, DROP COLUMN shipment_date, DROP COLUMN shipment_number,
            DROP COLUMN status, DROP COLUMN delivery_type, DROP COLUMN delivery_reference,
            DROP COLUMN ship_from_location_id, DROP COLUMN ship_to_location_id;
        ALTER TABLE bps.om_shipment_lines ADD COLUMN shipment_id BIGINT NOT NULL REFERENCES bps.om_shipments(shipment_id) ON DELETE CASCADE;
        ALTER TABLE bps.om_shipment_lines ADD COLUMN shipped_quantity NUMERIC(14,4) CHECK (shipped_quantity >= 0);
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'bps' AND table_name = 'ar_transaction_lines' AND column_name = 'order_shipment_id') THEN
        ALTER TABLE bps.ar_transaction_lines RENAME COLUMN order_shipment_id TO shipment_line_id;
        ALTER INDEX IF EXISTS bps.idx_ar_transaction_lines_order_shipment RENAME TO idx_ar_transaction_lines_shipment_line;
    END IF;
END $$;

-- ===== schema/om_shipment_lines.sql =====
-- ============================================================
-- OM_SHIPMENT_LINES  –  What a shipment carries: one row per order line
--
-- (Formerly om_order_shipments, a flat per-line event table; the header now lives in om_shipments.)
-- quantity = planned quantity (from the order line at processing); shipped_quantity = confirmed at delivery (NULL until then).
-- AR recognises an invoice line from shipped_quantity once its shipment is SHIPPED/DELIVERED.
--
-- shipment_line_id uses fnd_entity_id_seq.
-- Run after: om_shipments.sql, om_orders.sql, om_order_lines.sql. Policies: ../policies/om_shipment_lines_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS om_shipment_lines (
    tenant_id          BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    shipment_line_id   BIGINT        PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    shipment_id        BIGINT        NOT NULL REFERENCES om_shipments(shipment_id) ON DELETE CASCADE,
    order_id           BIGINT        NOT NULL REFERENCES om_orders(order_id) ON DELETE CASCADE,
    order_line_id      BIGINT        REFERENCES om_order_lines(order_line_id) ON DELETE CASCADE,
    quantity           NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
    shipped_quantity   NUMERIC(14,4) CHECK (shipped_quantity >= 0),
    snapshot_data      JSONB         NOT NULL DEFAULT '{}'::jsonb,

    created_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    created_by         BIGINT,
    updated_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_by         BIGINT
);

-- Ownership: application tables are owned by bps_owner; runtime access is via grants + RLS.
ALTER TABLE om_shipment_lines OWNER TO bps_owner;

CREATE INDEX IF NOT EXISTS idx_om_shipment_lines_shipment ON om_shipment_lines (tenant_id, shipment_id);
CREATE INDEX IF NOT EXISTS idx_om_shipment_lines_order ON om_shipment_lines (tenant_id, order_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_om_shipment_lines_order_line
    ON om_shipment_lines (tenant_id, order_line_id) WHERE order_line_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_om_shipment_lines_set_updated ON om_shipment_lines;
CREATE TRIGGER trg_om_shipment_lines_set_updated
    BEFORE UPDATE ON om_shipment_lines
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_om_shipment_lines_audit ON om_shipment_lines;
CREATE TRIGGER trg_om_shipment_lines_audit
    AFTER INSERT OR UPDATE OR DELETE ON om_shipment_lines
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('shipment_line_id');

COMMENT ON TABLE om_shipment_lines IS
    'Shipment detail: planned quantity per order line (one shipment per order line) and the quantity actually shipped.';

-- ===== schema/ar_transactions.sql (order-to-invoice columns) =====
-- ============================================================
-- Order-to-invoice: invoices are built per production run and numbered when printed.
--   DRAFT  = built by "Process run", no document_number yet (assigned at the Packaging print from the tenant
--            sequence 'invoice_number'); OPEN/PARTIAL/CLOSED/CANCELLED as before (CANCELLED = void, never deleted).
--   production_run_id = the run an INV belongs to (one invoice per customer per run).
--   applies_to_ar_transaction_id = the invoice a credit memo (transaction_type 'CM') corrects.
-- ============================================================
ALTER TABLE ar_transactions ALTER COLUMN document_number DROP NOT NULL;
ALTER TABLE ar_transactions ADD COLUMN IF NOT EXISTS production_run_id BIGINT REFERENCES om_production_runs(production_run_id);
ALTER TABLE ar_transactions ADD COLUMN IF NOT EXISTS applies_to_ar_transaction_id BIGINT REFERENCES ar_transactions(ar_transaction_id);
ALTER TABLE ar_transactions DROP CONSTRAINT IF EXISTS ar_transactions_status_check;
ALTER TABLE ar_transactions DROP CONSTRAINT IF EXISTS chk_ar_transactions_status;
ALTER TABLE ar_transactions ADD CONSTRAINT chk_ar_transactions_status
    CHECK (status IN ('DRAFT', 'OPEN', 'PARTIAL', 'CLOSED', 'CANCELLED'));
ALTER TABLE ar_transactions DROP CONSTRAINT IF EXISTS chk_ar_transactions_number_when_issued;
ALTER TABLE ar_transactions ADD CONSTRAINT chk_ar_transactions_number_when_issued
    CHECK (status = 'DRAFT' OR document_number IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS uq_ar_transactions_invoice_run
    ON ar_transactions (tenant_id, customer_id, production_run_id)
    WHERE transaction_type = 'INV' AND production_run_id IS NOT NULL AND status <> 'CANCELLED';
CREATE INDEX IF NOT EXISTS idx_ar_transactions_run ON ar_transactions (tenant_id, production_run_id) WHERE production_run_id IS NOT NULL;
COMMENT ON COLUMN ar_transactions.status IS
    'Document lifecycle: DRAFT (no number yet), OPEN, PARTIAL, CLOSED, CANCELLED (void).';

-- ===== policies/om_shipments_policies.sql =====
-- ============================================================
-- OM_SHIPMENTS — Row Level Security
-- Read: tenant members; customer-restricted users only see rows for their customers. Write: tenant staff only.
-- Run after: om_shipments.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_shipments TO authenticated;
GRANT ALL ON TABLE om_shipments TO bps_dev;

ALTER TABLE om_shipments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_shipments_tenant ON om_shipments;
DROP POLICY IF EXISTS pol_om_shipments_read ON om_shipments;
CREATE POLICY pol_om_shipments_read ON om_shipments
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR (ship_to_customer_id)::text = ANY (ARRAY(SELECT jsonb_array_elements_text(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_customer_ids')))
        )
    );

DROP POLICY IF EXISTS pol_om_shipments_staff_write ON om_shipments;
CREATE POLICY pol_om_shipments_staff_write ON om_shipments
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    );

-- ===== policies/om_shipment_lines_policies.sql =====
-- ============================================================
-- OM_SHIPMENT_LINES — Row Level Security
-- Read: tenant members; customer-restricted users only see rows for their customers. Write: tenant staff only.
-- Run after: om_shipment_lines.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE om_shipment_lines TO authenticated;
GRANT ALL ON TABLE om_shipment_lines TO bps_dev;

ALTER TABLE om_shipment_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_shipment_lines_tenant ON om_shipment_lines;
DROP POLICY IF EXISTS pol_om_shipment_lines_read ON om_shipment_lines;
CREATE POLICY pol_om_shipment_lines_read ON om_shipment_lines
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR EXISTS (SELECT 1 FROM om_shipments s WHERE s.shipment_id = om_shipment_lines.shipment_id)
        )
    );

DROP POLICY IF EXISTS pol_om_shipment_lines_staff_write ON om_shipment_lines;
CREATE POLICY pol_om_shipment_lines_staff_write ON om_shipment_lines
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    );

-- ===== policies/ar_transactions_policies.sql =====
-- ============================================================
-- AR_TRANSACTIONS — Row Level Security
-- Read: tenant members; customer-restricted users only see rows for their customers. Write: tenant staff only.
-- Run after: ar_transactions.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ar_transactions TO authenticated;
GRANT ALL ON TABLE ar_transactions TO bps_dev;

ALTER TABLE ar_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_transactions_tenant ON ar_transactions;
DROP POLICY IF EXISTS pol_ar_transactions_read ON ar_transactions;
CREATE POLICY pol_ar_transactions_read ON ar_transactions
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR (customer_id)::text = ANY (ARRAY(SELECT jsonb_array_elements_text(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_customer_ids')))
        )
    );

DROP POLICY IF EXISTS pol_ar_transactions_staff_write ON ar_transactions;
CREATE POLICY pol_ar_transactions_staff_write ON ar_transactions
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    );

-- ===== policies/ar_transaction_lines_policies.sql =====
-- ============================================================
-- AR_TRANSACTION_LINES — Row Level Security
-- Read: tenant members; customer-restricted users only see rows for their customers. Write: tenant staff only.
-- Run after: ar_transaction_lines.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ar_transaction_lines TO authenticated;
GRANT ALL ON TABLE ar_transaction_lines TO bps_dev;

ALTER TABLE ar_transaction_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ar_transaction_lines_tenant ON ar_transaction_lines;
DROP POLICY IF EXISTS pol_ar_transaction_lines_read ON ar_transaction_lines;
CREATE POLICY pol_ar_transaction_lines_read ON ar_transaction_lines
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR EXISTS (SELECT 1 FROM ar_transactions t WHERE t.ar_transaction_id = ar_transaction_lines.ar_transaction_id)
        )
    );

DROP POLICY IF EXISTS pol_ar_transaction_lines_staff_write ON ar_transaction_lines;
CREATE POLICY pol_ar_transaction_lines_staff_write ON ar_transaction_lines
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    );

-- ===== policies/fnd_tenant_sequences_policies.sql =====
-- ============================================================
-- FND_TENANT_SEQUENCES — Row Level Security
-- Read: tenant staff (restricted customer users get nothing: numbering is internal). Write: tenant staff only.
-- Run after: fnd_tenant_sequences.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE fnd_tenant_sequences TO authenticated;
GRANT ALL ON TABLE fnd_tenant_sequences TO bps_dev;

ALTER TABLE fnd_tenant_sequences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_tenant_sequences_tenant ON fnd_tenant_sequences;
DROP POLICY IF EXISTS pol_fnd_tenant_sequences_read ON fnd_tenant_sequences;
CREATE POLICY pol_fnd_tenant_sequences_read ON fnd_tenant_sequences
    FOR SELECT
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND (
            NOT (tenant_id::text = ANY (ARRAY(
                SELECT jsonb_array_elements_text(
                    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
            OR FALSE
        )
    );

DROP POLICY IF EXISTS pol_fnd_tenant_sequences_staff_write ON fnd_tenant_sequences;
CREATE POLICY pol_fnd_tenant_sequences_staff_write ON fnd_tenant_sequences
    FOR ALL
    USING (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    )
    WITH CHECK (
        tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
        AND NOT (tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    );

-- ===== functions/fnd_is_tenant_staff.sql =====
-- ============================================================
-- fnd_is_tenant_staff
-- True when the caller may act as staff in the tenant: the tenant is in allowed_tenant_ids and NOT in
-- restricted_tenant_ids. A connection without JWT claims (migrations, tests, admin) is trusted.
-- Used by functions that change production, shipping or billing data.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_is_tenant_staff(p_tenant_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT CASE
        WHEN NULLIF(current_setting('request.jwt.claims', true), '') IS NULL THEN TRUE
        ELSE
            p_tenant_id::text = ANY (ARRAY(SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
            AND NOT (p_tenant_id::text = ANY (ARRAY(SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'restricted_tenant_ids'))))
    END;
$function$;

-- ===== functions/om_customer_invoice_owner.sql =====
-- ============================================================
-- om_customer_invoice_owner
-- Which customer receives the invoice for an order placed by p_customer_id: the nearest ancestor-or-self that is an
-- ACCOUNT, or a DEPARTMENT with is_invoice_required. A SITE never owns an invoice. Falls back to the top ancestor.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_customer_invoice_owner(p_tenant_id bigint, p_customer_id bigint)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    WITH RECURSIVE up AS (
        SELECT c.customer_id, c.customer_parent_id, c.customer_type, c.is_invoice_required, 0 AS depth
          FROM fnd_customers c
         WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
        UNION ALL
        SELECT c.customer_id, c.customer_parent_id, c.customer_type, c.is_invoice_required, up.depth + 1
          FROM fnd_customers c
          JOIN up ON c.customer_id = up.customer_parent_id
         WHERE c.tenant_id = p_tenant_id AND up.depth < 10
    )
    SELECT COALESCE(
        (SELECT customer_id FROM up
          WHERE UPPER(TRIM(customer_type)) = 'ACCOUNT'
             OR (UPPER(TRIM(customer_type)) = 'DEPARTMENT' AND is_invoice_required)
          ORDER BY depth LIMIT 1),
        (SELECT customer_id FROM up ORDER BY depth DESC LIMIT 1)
    );
$function$;

-- ===== functions/om_customer_delivery_method.sql =====
-- ============================================================
-- om_customer_delivery_method
-- Delivery method for a customer: its own delivery_method_code, else the nearest ancestor's (active methods only),
-- else the tenant's first active own-fleet method by code, else NULL.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_customer_delivery_method(p_tenant_id bigint, p_customer_id bigint)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    WITH RECURSIVE up AS (
        SELECT c.customer_id, c.customer_parent_id, c.delivery_method_code, 0 AS depth
          FROM fnd_customers c
         WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
        UNION ALL
        SELECT c.customer_id, c.customer_parent_id, c.delivery_method_code, up.depth + 1
          FROM fnd_customers c
          JOIN up ON c.customer_id = up.customer_parent_id
         WHERE c.tenant_id = p_tenant_id AND up.depth < 10
    )
    SELECT COALESCE(
        (SELECT up.delivery_method_code FROM up
           JOIN om_delivery_methods m ON m.tenant_id = p_tenant_id AND m.delivery_method_code = up.delivery_method_code AND m.is_active
          WHERE up.delivery_method_code IS NOT NULL
          ORDER BY up.depth LIMIT 1),
        (SELECT m.delivery_method_code FROM om_delivery_methods m
          WHERE m.tenant_id = p_tenant_id AND m.is_own_fleet AND m.is_active
          ORDER BY m.delivery_method_code LIMIT 1)
    );
$function$;

-- ===== functions/om_production_run_process.sql =====
-- ============================================================
-- om_production_run_process
-- "Process run": locks one run and prepares everything the reports print from. Staff only. Re-runnable until a
-- shipment has been shipped (it rebuilds the PLANNED shipments and the invoice lines; invoice numbers are kept).
--   1. run_status -> PROCESSED (processed_at/by).
--   2. Shipments: one PLANNED shipment per ship-to customer (the order's customer) and delivery method; one shipment
--      line per order line (quantity > 0). Shipment numbers come from the tenant sequence 'shipment_number'.
--   3. Invoices: one per invoice owner (om_customer_invoice_owner) per run, DRAFT until the Packaging print numbers it.
--      Lines: each order line (ITEM, net of discount) and each order's delivery charge (DELIVERY), ordered by
--      department/event, order number, line. Invoices whose orders are gone are deleted (DRAFT) or CANCELLED (numbered).
--   4. Invoice amounts = sum of lines.
-- Returns { production_run_id, orders, shipments, invoices }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_run_process(p_tenant_id bigint, p_production_run_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_run     om_production_runs%ROWTYPE;
    v_actor   bigint := bps.fnd_nav_app_user_id();
    v_pair    record;
    v_orders  integer;
    v_ships   integer;
    v_invs    integer;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can process a run';
    END IF;
    SELECT * INTO v_run FROM om_production_runs
     WHERE tenant_id = p_tenant_id AND production_run_id = p_production_run_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Run % not found', p_production_run_id;
    END IF;
    IF v_run.run_status = 'CLOSED' THEN
        RAISE EXCEPTION 'Run % % is closed and cannot be processed', v_run.production_date, v_run.production_code;
    END IF;
    IF EXISTS (SELECT 1 FROM om_shipments WHERE production_run_id = p_production_run_id AND shipment_status IN ('SHIPPED', 'DELIVERED')) THEN
        RAISE EXCEPTION 'Run % % has shipped deliveries and cannot be processed again', v_run.production_date, v_run.production_code;
    END IF;

    UPDATE om_production_runs
       SET run_status = 'PROCESSED', processed_at = now(), processed_by = v_actor
     WHERE production_run_id = p_production_run_id;

    -- ── Shipments ────────────────────────────────────────────────────────
    DELETE FROM om_shipment_lines
     WHERE shipment_id IN (SELECT shipment_id FROM om_shipments WHERE production_run_id = p_production_run_id AND shipment_status = 'PLANNED');

    FOR v_pair IN
        SELECT DISTINCT o.customer_id, bps.om_customer_delivery_method(p_tenant_id, o.customer_id) AS method
          FROM om_orders o
         WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_production_run_id AND o.customer_id IS NOT NULL
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM om_shipments s
             WHERE s.tenant_id = p_tenant_id AND s.production_run_id = p_production_run_id
               AND s.ship_to_customer_id = v_pair.customer_id AND s.delivery_method_code IS NOT DISTINCT FROM v_pair.method
        ) THEN
            INSERT INTO om_shipments (tenant_id, production_run_id, ship_to_customer_id, shipment_number, delivery_date, delivery_method_code)
            VALUES (p_tenant_id, p_production_run_id, v_pair.customer_id,
                    bps.fnd_tenant_sequence_next(p_tenant_id, 'shipment_number', v_run.delivery_date),
                    v_run.delivery_date, v_pair.method);
        END IF;
    END LOOP;

    INSERT INTO om_shipment_lines (tenant_id, shipment_id, order_id, order_line_id, quantity)
    SELECT p_tenant_id, s.shipment_id, ol.order_id, ol.order_line_id, ol.quantity
      FROM om_order_lines ol
      JOIN om_orders o ON o.order_id = ol.order_id AND o.tenant_id = ol.tenant_id
      JOIN om_shipments s
        ON s.tenant_id = o.tenant_id AND s.production_run_id = o.production_run_id
       AND s.ship_to_customer_id = o.customer_id
       AND s.delivery_method_code IS NOT DISTINCT FROM bps.om_customer_delivery_method(o.tenant_id, o.customer_id)
       AND s.shipment_status = 'PLANNED'
     WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_production_run_id AND ol.quantity > 0;

    DELETE FROM om_shipments s
     WHERE s.production_run_id = p_production_run_id AND s.shipment_status = 'PLANNED'
       AND NOT EXISTS (SELECT 1 FROM om_shipment_lines l WHERE l.shipment_id = s.shipment_id);

    -- ── Invoices ─────────────────────────────────────────────────────────
    INSERT INTO ar_transactions (tenant_id, customer_id, transaction_type, document_number, transaction_date, amount, status, production_run_id)
    SELECT p_tenant_id, x.owner_id, 'INV', NULL, v_run.delivery_date, 0, 'DRAFT', p_production_run_id
      FROM (SELECT DISTINCT bps.om_customer_invoice_owner(p_tenant_id, o.customer_id) AS owner_id
              FROM om_orders o
             WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_production_run_id AND o.customer_id IS NOT NULL) x
     WHERE x.owner_id IS NOT NULL
    ON CONFLICT (tenant_id, customer_id, production_run_id)
        WHERE transaction_type = 'INV' AND production_run_id IS NOT NULL AND status <> 'CANCELLED'
    DO NOTHING;

    DELETE FROM ar_transaction_lines
     WHERE ar_transaction_id IN (SELECT ar_transaction_id FROM ar_transactions
                                  WHERE tenant_id = p_tenant_id AND production_run_id = p_production_run_id
                                    AND transaction_type = 'INV' AND status <> 'CANCELLED');

    INSERT INTO ar_transaction_lines (tenant_id, ar_transaction_id, line_number, source_type, item_id, item_description,
                                      quantity, unit_price, amount, shipment_line_id, snapshot_data)
    SELECT p_tenant_id, src.ar_transaction_id,
           ROW_NUMBER() OVER (PARTITION BY src.ar_transaction_id ORDER BY src.department_event, src.order_number, src.kind_rank, src.order_line_id),
           src.source_type, src.item_id, src.item_description, src.quantity, src.unit_price, src.amount, src.shipment_line_id,
           jsonb_build_object('order_id', src.order_id, 'order_number', src.order_number, 'order_line_id', src.order_line_id,
                              'department_event', src.department_event, 'customer_id', src.customer_id,
                              'customer_name', src.customer_name, 'po_number', src.po_number)
      FROM (
        SELECT inv.ar_transaction_id, o.order_id, o.order_number, o.department_event, o.customer_id, o.customer_name, o.po_number,
               ol.order_line_id, 1 AS kind_rank, 'ITEM'::text AS source_type, ol.item_id,
               COALESCE(NULLIF(TRIM(ol.item_description), ''), i.item_name) AS item_description,
               ol.quantity, (ol.unit_price - COALESCE(ol.unit_discount, 0)) AS unit_price, ol.extended_amount AS amount,
               sl.shipment_line_id
          FROM om_orders o
          JOIN om_order_lines ol ON ol.order_id = o.order_id AND ol.tenant_id = o.tenant_id
          LEFT JOIN fnd_items i ON i.item_id = ol.item_id
          LEFT JOIN om_shipment_lines sl ON sl.order_line_id = ol.order_line_id AND sl.tenant_id = o.tenant_id
          JOIN ar_transactions inv
            ON inv.tenant_id = o.tenant_id AND inv.production_run_id = o.production_run_id
           AND inv.transaction_type = 'INV' AND inv.status <> 'CANCELLED'
           AND inv.customer_id = bps.om_customer_invoice_owner(o.tenant_id, o.customer_id)
         WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_production_run_id
        UNION ALL
        SELECT inv.ar_transaction_id, o.order_id, o.order_number, o.department_event, o.customer_id, o.customer_name, o.po_number,
               NULL::bigint, 2, 'DELIVERY', NULL::bigint, 'Delivery', 1, o.delivery_charge, o.delivery_charge, NULL::bigint
          FROM om_orders o
          JOIN ar_transactions inv
            ON inv.tenant_id = o.tenant_id AND inv.production_run_id = o.production_run_id
           AND inv.transaction_type = 'INV' AND inv.status <> 'CANCELLED'
           AND inv.customer_id = bps.om_customer_invoice_owner(o.tenant_id, o.customer_id)
         WHERE o.tenant_id = p_tenant_id AND o.production_run_id = p_production_run_id AND o.delivery_charge > 0
      ) src;

    UPDATE ar_transactions t
       SET amount = COALESCE((SELECT SUM(l.amount) FROM ar_transaction_lines l WHERE l.ar_transaction_id = t.ar_transaction_id), 0),
           transaction_date = v_run.delivery_date
     WHERE t.tenant_id = p_tenant_id AND t.production_run_id = p_production_run_id
       AND t.transaction_type = 'INV' AND t.status <> 'CANCELLED';

    -- invoices that no longer have any order: drop drafts, cancel numbered ones (never deleted)
    DELETE FROM ar_transactions t
     WHERE t.tenant_id = p_tenant_id AND t.production_run_id = p_production_run_id AND t.transaction_type = 'INV'
       AND t.status = 'DRAFT' AND NOT EXISTS (SELECT 1 FROM ar_transaction_lines l WHERE l.ar_transaction_id = t.ar_transaction_id);
    UPDATE ar_transactions t SET status = 'CANCELLED'
     WHERE t.tenant_id = p_tenant_id AND t.production_run_id = p_production_run_id AND t.transaction_type = 'INV'
       AND t.status IN ('OPEN', 'PARTIAL') AND NOT EXISTS (SELECT 1 FROM ar_transaction_lines l WHERE l.ar_transaction_id = t.ar_transaction_id);

    SELECT COUNT(*) INTO v_orders FROM om_orders WHERE tenant_id = p_tenant_id AND production_run_id = p_production_run_id;
    SELECT COUNT(*) INTO v_ships  FROM om_shipments WHERE production_run_id = p_production_run_id;
    SELECT COUNT(*) INTO v_invs   FROM ar_transactions
     WHERE tenant_id = p_tenant_id AND production_run_id = p_production_run_id AND transaction_type = 'INV' AND status <> 'CANCELLED';

    RETURN jsonb_build_object('production_run_id', p_production_run_id, 'production_date', v_run.production_date,
                              'production_code', v_run.production_code, 'orders', v_orders, 'shipments', v_ships, 'invoices', v_invs);
END;
$function$;

-- ===== functions/om_production_runs_process.sql =====
-- ============================================================
-- om_production_runs_process
-- Processes every non-closed run whose production date is in [p_from, p_to] (and matches p_production_code when given).
-- Returns an array of om_production_run_process results. Raises when no run matches.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_runs_process(p_tenant_id bigint, p_from date, p_to date, p_production_code text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_run     record;
    v_results jsonb := '[]'::jsonb;
    v_code    text := NULLIF(UPPER(TRIM(p_production_code)), '');
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can process runs';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;
    FOR v_run IN
        SELECT production_run_id FROM om_production_runs
         WHERE tenant_id = p_tenant_id AND production_date BETWEEN p_from AND p_to
           AND run_status <> 'CLOSED' AND (v_code IS NULL OR production_code = v_code)
         ORDER BY production_date, production_code
    LOOP
        v_results := v_results || jsonb_build_array(bps.om_production_run_process(p_tenant_id, v_run.production_run_id));
    END LOOP;
    IF jsonb_array_length(v_results) = 0 THEN
        RAISE EXCEPTION 'No open production runs between % and %', p_from, p_to;
    END IF;
    RETURN v_results;
END;
$function$;

-- ===== functions/fnd_tenant_sequences_get.sql =====
-- ============================================================
-- fnd_tenant_sequences_get  –  numbering settings for order, invoice, shipment and credit memo numbers
-- Returns one row per sequence; a sequence without a row yet comes back with is_configured = false and defaults.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_tenant_sequences_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT jsonb_agg(jsonb_build_object(
               'sequence_name',    n.sequence_name,
               'label',            n.label,
               'is_configured',    s.sequence_name IS NOT NULL,
               'mask',             COALESCE(s.mask, n.default_mask),
               'start_value',      COALESCE(s.start_value, 1000),
               'next_value',       COALESCE(s.next_value, 1000),
               'increment_by',     COALESCE(s.increment_by, 1),
               'reset_period',     COALESCE(s.reset_period, 'NEVER'),
               'requires_gapless', COALESCE(s.requires_gapless, FALSE)
           ) ORDER BY n.ord)
      FROM (VALUES (1, 'order_number',       'Order numbers',       '####-####'),
                   (2, 'invoice_number',     'Invoice numbers',     'INV-######'),
                   (3, 'shipment_number',    'Shipment numbers',    'SHP-######'),
                   (4, 'credit_memo_number', 'Credit memo numbers', 'CM-######')) AS n(ord, sequence_name, label, default_mask)
      LEFT JOIN fnd_tenant_sequences s ON s.tenant_id = p_tenant_id AND s.sequence_name = n.sequence_name;
$function$;

-- ===== functions/fnd_tenant_sequences_save.sql =====
-- ============================================================
-- fnd_tenant_sequences_save
-- Upserts one numbering sequence (order_number, invoice_number, shipment_number or credit_memo_number). Staff only.
-- p_payload: { sequence_name, mask, start_value, next_value, increment_by, reset_period, requires_gapless }
-- next_value is only applied when it is not lower than the current next_value (numbers are never reused).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_tenant_sequences_save(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_name text := p_payload ->> 'sequence_name';
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can change numbering';
    END IF;
    IF v_name IS NULL OR v_name NOT IN ('order_number', 'invoice_number', 'shipment_number', 'credit_memo_number') THEN
        RAISE EXCEPTION 'Unknown sequence %', v_name;
    END IF;
    IF NULLIF(TRIM(p_payload ->> 'mask'), '') IS NULL OR POSITION('#' IN p_payload ->> 'mask') = 0 THEN
        RAISE EXCEPTION 'The mask must contain at least one # (digit placeholder)';
    END IF;

    INSERT INTO fnd_tenant_sequences (tenant_id, sequence_name, start_value, next_value, increment_by, mask, reset_period, requires_gapless)
    VALUES (p_tenant_id, v_name,
            COALESCE((p_payload ->> 'start_value')::bigint, 1000),
            COALESCE((p_payload ->> 'next_value')::bigint, (p_payload ->> 'start_value')::bigint, 1000),
            COALESCE((p_payload ->> 'increment_by')::bigint, 1),
            TRIM(p_payload ->> 'mask'),
            COALESCE(p_payload ->> 'reset_period', 'NEVER'),
            COALESCE((p_payload ->> 'requires_gapless')::boolean, FALSE))
    ON CONFLICT (tenant_id, sequence_name) DO UPDATE SET
        start_value      = EXCLUDED.start_value,
        next_value       = GREATEST(fnd_tenant_sequences.next_value, EXCLUDED.next_value),
        increment_by     = EXCLUDED.increment_by,
        mask             = EXCLUDED.mask,
        reset_period     = EXCLUDED.reset_period,
        requires_gapless = EXCLUDED.requires_gapless;

    RETURN jsonb_build_object('success', TRUE, 'sequence_name', v_name);
END;
$function$;

-- ===== functions/om_orders_save.sql =====
-- ============================================================
-- om_orders_save
-- Atomically saves an order header + lines.
--
-- department_event defaulting (new orders only):
--   1. If department_event is passed in the payload → use it
--   2. Else → the name of the customer the clerk selected (account, department or site)
--   (fallback 'ORDER' when no customer)
--
-- When department_event collides with an existing order for the same
-- slot (customer + production_date + production_code + department_event),
-- a suffix is appended: 'ORDER-01', 'KITCHEN-02', etc.
--
-- delivery_amount (payload) is stored in om_orders.delivery_charge; entered with the order, defaults to 0.
--
-- Customer types: an ACCOUNT or DEPARTMENT order is stored under that customer's own customer_id (own order number).
-- A SITE is a pseudo type: its order is stored under the parent customer_id and the site name is the default
-- department_event (which can always be overridden).
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_orders_save(
    p_tenant_id bigint,
    p_action    text    DEFAULT NULL,
    p_order_id  bigint  DEFAULT NULL,
    p_payload   jsonb   DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_order_id     BIGINT;
    v_order_number TEXT;
    v_po_number    TEXT;
    v_mode         TEXT;
    v_line         JSONB;
    v_line_id      BIGINT;
    v_deleted_line_count INTEGER := 0;
    v_line_refs    JSONB := '[]'::JSONB;
    v_qty          NUMERIC(14,4);
    v_price        NUMERIC(14,4);
    v_discount     NUMERIC(14,4);
    v_extended     NUMERIC(14,4);
    v_total_qty    NUMERIC(14,4) := 0;
    v_total_amt    NUMERIC(14,4) := 0;
    v_total_disc   NUMERIC(14,4) := 0;
    v_payload_customer_id   BIGINT;
    v_order_customer_id     BIGINT;
    v_order_customer_name   TEXT;
    v_is_site               BOOLEAN := FALSE;
    v_payload_customer_name TEXT;
    v_production_date DATE;
    v_production_code TEXT;
    v_department_event TEXT;
    v_base_department_event TEXT;
    v_next_department_event_suffix INTEGER;
    v_requires_gapless BOOLEAN;
    v_constraint_name TEXT;
    v_has_po_number BOOLEAN := FALSE;
    v_delivery_charge NUMERIC(12,2);
    v_run_id        BIGINT;
    v_old_order     om_orders%ROWTYPE;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- ── DELETE ────────────────────────────────────────────────────────────
    IF LOWER(COALESCE(p_action, '')) = 'delete' THEN
        IF p_order_id IS NULL THEN
            RAISE EXCEPTION 'p_order_id is required for delete';
        END IF;
        SELECT * INTO v_old_order FROM om_orders WHERE order_id = p_order_id AND tenant_id = p_tenant_id;
        IF FOUND THEN
            PERFORM bps.om_production_cutoff_assert(p_tenant_id, v_old_order.production_date,
                                                    v_old_order.production_code, v_old_order.customer_id);
        END IF;
        v_requires_gapless := FALSE;
        SELECT COALESCE(seq.requires_gapless, FALSE)
          INTO v_requires_gapless
          FROM fnd_tenant_sequences seq
         WHERE seq.tenant_id = p_tenant_id
           AND seq.sequence_name = 'order_number';
        IF COALESCE(v_requires_gapless, FALSE) THEN
            RAISE EXCEPTION 'Order % cannot be deleted because this tenant requires gapless order numbers. Cancel or void the order instead.', p_order_id;
        END IF;
        DELETE FROM om_orders WHERE order_id = p_order_id AND tenant_id = p_tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order % not found for this tenant', p_order_id;
        END IF;
        RETURN jsonb_build_object('success', TRUE, 'order_id', p_order_id, 'order_number', NULL, 'message', 'Order deleted.');
    END IF;

    IF p_payload IS NULL THEN
        RAISE EXCEPTION 'p_payload is required';
    END IF;

    v_production_date  := NULLIF(TRIM(p_payload->>'production_date'), '')::DATE;
    v_production_code  := NULLIF(UPPER(TRIM(p_payload->>'production_code')), '');
    v_department_event := NULLIF(UPPER(TRIM(p_payload->>'department_event')), '');
    v_po_number        := NULLIF(TRIM(p_payload->>'po_number'), '');

    SELECT EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = 'bps'
           AND table_name = 'om_orders'
           AND column_name = 'po_number'
    ) INTO v_has_po_number;

    v_payload_customer_id := NULLIF((p_payload->>'customer_id')::TEXT, 'null')::BIGINT;
    v_order_customer_id   := v_payload_customer_id;

    -- ── Customer lookup: DEPARTMENT → store order under parent ───────────
    IF v_payload_customer_id IS NOT NULL THEN
        SELECT
            CASE
                WHEN UPPER(TRIM(selected.customer_type)) = 'SITE'
                 AND selected.customer_parent_id IS NOT NULL
                THEN parent.customer_id
                ELSE selected.customer_id
            END,
            CASE
                WHEN UPPER(TRIM(selected.customer_type)) = 'SITE'
                 AND selected.customer_parent_id IS NOT NULL
                THEN parent.customer_name
                ELSE selected.customer_name
            END,
            UPPER(TRIM(selected.customer_type)) = 'SITE',
            selected.customer_name
          INTO v_order_customer_id, v_order_customer_name,
               v_is_site, v_payload_customer_name
          FROM fnd_customers selected
          LEFT JOIN fnd_customers parent
                 ON parent.tenant_id   = selected.tenant_id
                AND parent.customer_id = selected.customer_parent_id
         WHERE selected.tenant_id   = p_tenant_id
           AND selected.customer_id = v_payload_customer_id;
    END IF;

    -- ── Cutoff: customers cannot enter or change orders for a run past its cutoff ──
    IF p_order_id IS NOT NULL THEN
        SELECT * INTO v_old_order FROM om_orders WHERE order_id = p_order_id AND tenant_id = p_tenant_id;
        IF FOUND THEN
            PERFORM bps.om_production_cutoff_assert(p_tenant_id, v_old_order.production_date,
                                                    v_old_order.production_code, v_old_order.customer_id);
        END IF;
    END IF;
    PERFORM bps.om_production_cutoff_assert(p_tenant_id, v_production_date, v_production_code, v_order_customer_id);
    v_run_id := bps.om_production_run_get_or_create(p_tenant_id, v_production_date, v_production_code);
    v_delivery_charge := COALESCE(NULLIF(TRIM(p_payload->>'delivery_amount'), '')::NUMERIC, 0);
    IF v_delivery_charge < 0 THEN
        RAISE EXCEPTION 'delivery_amount cannot be negative';
    END IF;

    -- ── Default department_event when not supplied in payload ─────────────
    -- The selected customer's own name (site name for a site, department name, account name); 'ORDER' without a customer.
    IF v_department_event IS NULL THEN
        v_department_event := COALESCE(NULLIF(UPPER(TRIM(v_payload_customer_name)), ''), 'ORDER');
    END IF;

    -- ── HEADER INSERT (new order) ─────────────────────────────────────────
    IF p_order_id IS NULL THEN
        v_base_department_event := v_department_event;

        v_order_number := TRIM(p_payload->>'order_number');
        IF v_order_number IS NULL OR v_order_number = '' OR v_order_number = 'New Order' THEN
            v_order_number := fnd_tenant_sequence_next(
                p_tenant_id, 'order_number', COALESCE(v_production_date, CURRENT_DATE)
            );
        END IF;

        -- Check for collision; append suffix if needed
        IF EXISTS (
            SELECT 1 FROM om_orders existing
             WHERE existing.tenant_id       = p_tenant_id
               AND existing.customer_id    IS NOT DISTINCT FROM v_order_customer_id
               AND existing.production_date = v_production_date
               AND existing.production_code IS NOT DISTINCT FROM v_production_code
               AND existing.department_event = v_base_department_event
        ) THEN
            SELECT COALESCE(MAX(
                CASE
                    WHEN existing.department_event = v_base_department_event THEN 0
                    WHEN substring(existing.department_event FROM length(v_base_department_event) + 2) ~ '^[0-9]+$'
                    THEN substring(existing.department_event FROM length(v_base_department_event) + 2)::INTEGER
                    ELSE NULL
                END), 0) + 1
              INTO v_next_department_event_suffix
              FROM om_orders existing
             WHERE existing.tenant_id       = p_tenant_id
               AND existing.customer_id    IS NOT DISTINCT FROM v_order_customer_id
               AND existing.production_date = v_production_date
               AND existing.production_code IS NOT DISTINCT FROM v_production_code
               AND (existing.department_event = v_base_department_event
                    OR existing.department_event LIKE v_base_department_event || '-%');
            v_department_event := v_base_department_event || '-' || LPAD(v_next_department_event_suffix::TEXT, 2, '0');
        END IF;

        LOOP
            BEGIN
                IF v_has_po_number THEN
                    INSERT INTO om_orders (
                        order_number, po_number, order_date, production_date, production_code,
                        quantity, amount, discount_amount,
                        customer_id, customer_name, department_event,
                        order_source, tenant_id, snapshot_data,
                        delivery_charge, production_run_id
                    ) VALUES (
                        v_order_number,
                        v_po_number,
                        NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                        v_production_date, v_production_code,
                        0, 0, 0,
                        v_order_customer_id, v_order_customer_name,
                        v_department_event,
                        'Clerk', p_tenant_id,
                        COALESCE(p_payload->'snapshot_data', '{}'::JSONB),
                        v_delivery_charge, v_run_id
                    )
                    RETURNING order_id INTO v_order_id;
                ELSE
                    INSERT INTO om_orders (
                        order_number, order_date, production_date, production_code,
                        quantity, amount, discount_amount,
                        customer_id, customer_name, department_event,
                        order_source, tenant_id, snapshot_data,
                        delivery_charge, production_run_id
                    ) VALUES (
                        v_order_number,
                        NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                        v_production_date, v_production_code,
                        0, 0, 0,
                        v_order_customer_id, v_order_customer_name,
                        v_department_event,
                        'Clerk', p_tenant_id,
                        COALESCE(p_payload->'snapshot_data', '{}'::JSONB),
                        v_delivery_charge, v_run_id
                    )
                    RETURNING order_id INTO v_order_id;
                END IF;
                EXIT;
            EXCEPTION WHEN unique_violation THEN
                GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
                IF v_constraint_name <> 'uq_om_orders_slot_department_event' THEN RAISE; END IF;
                SELECT COALESCE(MAX(
                    CASE
                        WHEN existing.department_event = v_base_department_event THEN 0
                        WHEN substring(existing.department_event FROM length(v_base_department_event) + 2) ~ '^[0-9]+$'
                        THEN substring(existing.department_event FROM length(v_base_department_event) + 2)::INTEGER
                        ELSE NULL
                    END), 0) + 1
                  INTO v_next_department_event_suffix
                  FROM om_orders existing
                 WHERE existing.tenant_id       = p_tenant_id
                   AND existing.customer_id    IS NOT DISTINCT FROM v_order_customer_id
                   AND existing.production_date = v_production_date
                   AND existing.production_code IS NOT DISTINCT FROM v_production_code
                   AND (existing.department_event = v_base_department_event
                        OR existing.department_event LIKE v_base_department_event || '-%');
                v_department_event := v_base_department_event || '-' || LPAD(v_next_department_event_suffix::TEXT, 2, '0');
            END;
        END LOOP;
        v_mode := 'created';

    ELSE
        -- ── HEADER UPDATE ─────────────────────────────────────────────────
        v_order_id := p_order_id;
        IF v_has_po_number THEN
            UPDATE om_orders SET
                order_number     = COALESCE(NULLIF(TRIM(p_payload->>'order_number'), ''), order_number),
                po_number        = CASE WHEN p_payload ? 'po_number' THEN v_po_number ELSE po_number END,
                order_date       = NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                production_date  = v_production_date,
                production_code  = v_production_code,
                production_run_id = v_run_id,
                delivery_charge  = CASE WHEN p_payload ? 'delivery_amount' THEN v_delivery_charge ELSE delivery_charge END,
                customer_id      = v_order_customer_id,
                customer_name    = v_order_customer_name,
                department_event = CASE
                    WHEN p_payload ? 'department_event' THEN v_department_event
                    ELSE department_event
                END
            WHERE order_id = v_order_id AND tenant_id = p_tenant_id;
        ELSE
            UPDATE om_orders SET
                order_number     = COALESCE(NULLIF(TRIM(p_payload->>'order_number'), ''), order_number),
                order_date       = NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                production_date  = v_production_date,
                production_code  = v_production_code,
                production_run_id = v_run_id,
                delivery_charge  = CASE WHEN p_payload ? 'delivery_amount' THEN v_delivery_charge ELSE delivery_charge END,
                customer_id      = v_order_customer_id,
                customer_name    = v_order_customer_name,
                department_event = CASE
                    WHEN p_payload ? 'department_event' THEN v_department_event
                    ELSE department_event
                END
            WHERE order_id = v_order_id AND tenant_id = p_tenant_id;
        END IF;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order % not found for this tenant', v_order_id;
        END IF;
        v_mode := 'updated';
    END IF;

    -- ── LINES UPSERT ──────────────────────────────────────────────────────
    FOR v_line IN SELECT jsonb_array_elements(COALESCE(p_payload->'lines', '[]'::JSONB)) LOOP
        v_qty      := COALESCE((v_line->>'quantity')::NUMERIC,     0);
        v_price    := COALESCE((v_line->>'unit_price')::NUMERIC,   0);
        v_discount := COALESCE((v_line->>'unit_discount')::NUMERIC,0);
        v_extended := v_qty * (v_price - v_discount);
        v_line_id  := NULLIF((v_line->>'order_line_id')::TEXT, 'null')::BIGINT;

        IF v_line_id IS NULL THEN
            INSERT INTO om_order_lines (
                order_id, item_id, item_description,
                quantity, unit_price, unit_discount, extended_amount,
                prep_options, tenant_id
            ) VALUES (
                v_order_id,
                NULLIF((v_line->>'item_id')::TEXT, 'null')::BIGINT,
                COALESCE(TRIM(v_line->>'item_description'), ''),
                v_qty, v_price, v_discount, v_extended,
                COALESCE(v_line->'prep_options', '[]'::JSONB),
                p_tenant_id
            )
            RETURNING order_line_id INTO v_line_id;
        ELSE
            UPDATE om_order_lines SET
                item_id          = NULLIF((v_line->>'item_id')::TEXT, 'null')::BIGINT,
                item_description = COALESCE(TRIM(v_line->>'item_description'), ''),
                quantity         = v_qty,
                unit_price       = v_price,
                unit_discount    = v_discount,
                extended_amount  = v_extended,
                prep_options     = COALESCE(v_line->'prep_options', '[]'::JSONB)
            WHERE order_line_id = v_line_id
              AND order_id      = v_order_id
              AND tenant_id     = p_tenant_id;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Order line % not found for order % and tenant %', v_line_id, v_order_id, p_tenant_id;
            END IF;
        END IF;

        v_line_refs  := v_line_refs || jsonb_build_array(jsonb_build_object(
            'client_temp_id', NULLIF(TRIM(v_line->>'client_temp_id'), ''),
            'order_line_id',  v_line_id
        ));
        v_total_qty  := v_total_qty  + v_qty;
        v_total_amt  := v_total_amt  + v_extended;
        v_total_disc := v_total_disc + (v_qty * v_discount);
    END LOOP;

    -- Remove lines omitted from payload (full-state save contract)
    IF jsonb_array_length(COALESCE(p_payload->'lines', '[]'::JSONB)) = 0 THEN
        DELETE FROM om_order_lines WHERE order_id = v_order_id AND tenant_id = p_tenant_id;
        GET DIAGNOSTICS v_deleted_line_count = ROW_COUNT;
    ELSE
        DELETE FROM om_order_lines l
         WHERE l.order_id  = v_order_id
           AND l.tenant_id = p_tenant_id
           AND NOT EXISTS (
                SELECT 1 FROM jsonb_array_elements(v_line_refs) r
                 WHERE (r->>'order_line_id')::BIGINT = l.order_line_id
           );
        GET DIAGNOSTICS v_deleted_line_count = ROW_COUNT;
    END IF;

    -- Update header rollups
    UPDATE om_orders SET
        quantity        = v_total_qty,
        amount          = v_total_amt,
        discount_amount = v_total_disc
    WHERE order_id = v_order_id;

    IF v_order_number IS NULL THEN
        SELECT order_number INTO v_order_number FROM om_orders WHERE order_id = v_order_id;
    END IF;

    RETURN jsonb_build_object(
        'success',          TRUE,
        'order_id',         v_order_id,
        'order_number',     v_order_number,
        'po_number',        v_po_number,
        'department_event', v_department_event,
        'mode',             v_mode,
        'line_refs',        v_line_refs,
        'deleted_lines',    v_deleted_line_count,
        'message',          'Order saved.'
    );

EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
    IF v_constraint_name = 'uq_om_orders_slot_department_event' THEN
        RAISE EXCEPTION 'An order already exists for this customer, production date, production code, and Department/Event.';
    END IF;
    RAISE EXCEPTION 'Order number % already exists for this tenant.', v_order_number;
END;
$function$;

-- ===== functions/om_orders_get_v2.sql =====
-- ============================================================
-- om_orders_get_v2
-- Fetches order data for the order entry / management screens.
--
-- Modes:
--   Detail (p_order_id set):
--     Returns a single order with or without lines.
--
--   Department/Event suggestions (p_department_events_only = true):
--     Returns distinct department_event values for the combobox.
--     All orders are included regardless of department_event value —
--     the old filter on non-null department_event was removed because
--     orders defaulted to 'ORDER' and departments now always get a
--     department_event value from om_orders_save.
--
--   List (neither of the above):
--     Returns up to 500 order headers matching the filters.
--
-- Customer type: DEPARTMENT customers are looked up via their parent.
-- (LOCATION is no longer used — superseded by DEPARTMENT.)
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_orders_get_v2(
    p_tenant_id              bigint,
    p_order_id               bigint  DEFAULT NULL,
    p_customer_id            bigint  DEFAULT NULL,
    p_production_date_from   date    DEFAULT NULL,
    p_production_date_to     date    DEFAULT NULL,
    p_production_code        text    DEFAULT NULL,
    p_return_headers_only    boolean DEFAULT true,
    p_return_actives_only    boolean DEFAULT true,
    p_department_events_only boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_result                   JSONB;
    v_lookup_customer_id       BIGINT;
    v_production_code          TEXT;
    v_default_department_event TEXT := 'ORDER';
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- ── Detail mode: single order ─────────────────────────────────────────
    IF p_order_id IS NOT NULL THEN
        IF p_return_headers_only THEN
            SELECT jsonb_build_object(
                'order_id',         o.order_id,
                'order_number',     o.order_number,
                'po_number',        o.po_number,
                'order_date',       o.order_date,
                'production_date',  o.production_date,
                'production_code',  o.production_code,
                'delivery_amount',  o.delivery_charge,
                'production_run_id', o.production_run_id,
                'department_event', o.department_event,
                'amount',           o.amount,
                'total_quantity',   o.quantity,
                'discount_amount',  o.discount_amount,
                'customer_id',      o.customer_id,
                'customer_name',    COALESCE(o.customer_name, c.customer_name, o.snapshot_data->>'cus_name', ''),
                'snapshot_data',    o.snapshot_data,
                'lines',            '[]'::JSONB
            ) INTO v_result
            FROM om_orders o
            LEFT JOIN fnd_customers c
                   ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
            LEFT JOIN fnd_customers top_c
                   ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id) AND top_c.tenant_id = o.tenant_id
            WHERE o.order_id = p_order_id AND o.tenant_id = p_tenant_id
              AND (NOT p_return_actives_only OR o.customer_id IS NULL
                   OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE)));
        ELSE
            SELECT jsonb_build_object(
                'order_id',         o.order_id,
                'order_number',     o.order_number,
                'po_number',        o.po_number,
                'order_date',       o.order_date,
                'production_date',  o.production_date,
                'production_code',  o.production_code,
                'delivery_amount',  o.delivery_charge,
                'production_run_id', o.production_run_id,
                'department_event', o.department_event,
                'amount',           o.amount,
                'total_quantity',   o.quantity,
                'discount_amount',  o.discount_amount,
                'customer_id',      o.customer_id,
                'customer_name',    COALESCE(o.customer_name, c.customer_name, o.snapshot_data->>'cus_name', ''),
                'snapshot_data',    o.snapshot_data,
                'lines',            COALESCE(lines_agg.lines, '[]'::JSONB)
            ) INTO v_result
            FROM om_orders o
            LEFT JOIN fnd_customers c
                   ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
            LEFT JOIN fnd_customers top_c
                   ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id) AND top_c.tenant_id = o.tenant_id
            LEFT JOIN LATERAL (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'order_id',             l.order_id,
                        'order_line_id',        l.order_line_id,
                        'item_id',              l.item_id,
                        'item_number',          COALESCE(i.item_number, ''),
                        'item_description',     l.item_description,
                        'quantity',             l.quantity,
                        'unit_price',           COALESCE(l.unit_price, 0),
                        'unit_discount',        l.unit_discount,
                        'extended_amount',      COALESCE(l.extended_amount, 0),
                        'allowed_prep_options', COALESCE(prep_allowed.allowed_prep_options, '[]'::JSONB),
                        'prep_options',         COALESCE(l.prep_options, '[]'::JSONB),
                        'is_scored',            FALSE,
                        'can_score',            FALSE
                    ) ORDER BY l.order_line_id
                ) AS lines
                FROM om_order_lines l
                LEFT JOIN fnd_items i ON i.item_id = l.item_id
                LEFT JOIN LATERAL (
                    SELECT COALESCE(
                        jsonb_agg(jsonb_build_object('value', vv.value, 'label', vv.label) ORDER BY vv.display_order, vv.label),
                        '[]'::JSONB
                    ) AS allowed_prep_options
                    FROM jsonb_array_elements_text(COALESCE(i.allowed_prep_options, '[]'::JSONB)) opt(value)
                    JOIN fnd_valuesets vs
                      ON vs.tenant_id = i.tenant_id AND vs.valueset_code = 'ITEMPREP' AND vs.is_active = TRUE
                    JOIN fnd_valueset_values vv
                      ON vv.tenant_id = vs.tenant_id AND vv.valueset_id = vs.valueset_id
                     AND vv.value = opt.value AND vv.is_disabled = FALSE
                ) prep_allowed ON TRUE
                WHERE l.order_id = o.order_id AND l.tenant_id = o.tenant_id
            ) lines_agg ON TRUE
            WHERE o.order_id = p_order_id AND o.tenant_id = p_tenant_id
              AND (NOT p_return_actives_only OR o.customer_id IS NULL
                   OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE)));
        END IF;
        RETURN COALESCE(v_result, 'null'::JSONB);
    END IF;

    -- ── Resolve lookup customer + default department_event ────────────────
    v_lookup_customer_id := p_customer_id;
    v_production_code    := NULLIF(UPPER(TRIM(p_production_code)), '');

    IF p_customer_id IS NOT NULL THEN
        SELECT
            CASE WHEN UPPER(TRIM(customer_type)) = 'SITE' AND customer_parent_id IS NOT NULL
                 THEN customer_parent_id ELSE customer_id END,
            COALESCE(NULLIF(UPPER(TRIM(customer_name)), ''), 'ORDER')
          INTO v_lookup_customer_id, v_default_department_event
          FROM fnd_customers
         WHERE tenant_id = p_tenant_id AND customer_id = p_customer_id;
    END IF;

    -- ── Department/Event suggestions ──────────────────────────────────────
    -- Returns distinct department_event values for the combobox.
    -- No filter on null/blank department_event — all orders are included.
    IF p_department_events_only THEN
        SELECT jsonb_agg(jsonb_build_object('department_event', department_event) ORDER BY department_event)
          INTO v_result
          FROM (
              SELECT DISTINCT UPPER(TRIM(o.department_event)) AS department_event
                FROM om_orders o
                LEFT JOIN fnd_customers c
                       ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
                LEFT JOIN fnd_customers top_c
                       ON top_c.customer_id = COALESCE(c.top_customer_id, c.customer_id) AND top_c.tenant_id = o.tenant_id
               WHERE o.tenant_id  = p_tenant_id
                 AND v_lookup_customer_id IS NOT NULL
                 AND o.customer_id = v_lookup_customer_id
                 AND (p_production_date_from IS NULL OR o.production_date >= p_production_date_from)
                 AND (p_production_date_to   IS NULL OR o.production_date <= p_production_date_to)
                 AND (NOT p_return_actives_only OR o.customer_id IS NULL
                      OR (COALESCE(c.is_active, FALSE) AND COALESCE(top_c.is_active, c.is_active, FALSE)))
          ) suggestions;
        RETURN COALESCE(v_result, '[]'::JSONB);
    END IF;

    -- ── Order headers list ────────────────────────────────────────────────
    SELECT jsonb_agg(row_data ORDER BY customer_name_sort ASC, department_event_sort ASC, order_id_sort DESC)
      INTO v_result
      FROM (
        SELECT jsonb_build_object(
            'order_id',         o.order_id,
            'order_number',     o.order_number,
            'po_number',        o.po_number,
            'order_date',       o.order_date,
            'production_date',  o.production_date,
            'production_code',  o.production_code,
            'department_event', o.department_event,
            'amount',           o.amount,
            'customer_id',      o.customer_id,
            'customer_name',    o.customer_name
        ) AS row_data,
        o.order_id AS order_id_sort,
        COALESCE(o.customer_name, '') AS customer_name_sort,
        COALESCE(o.department_event, '') AS department_event_sort
        FROM om_orders o
       WHERE o.tenant_id = p_tenant_id
         AND (v_lookup_customer_id IS NULL OR o.customer_id = v_lookup_customer_id)
         AND (p_production_date_from IS NULL OR o.production_date >= p_production_date_from)
         AND (p_production_date_to   IS NULL OR o.production_date <= p_production_date_to)
         AND (v_production_code IS NULL OR o.production_code = v_production_code)
       ORDER BY customer_name_sort ASC, department_event_sort ASC, o.order_id DESC
       LIMIT 500
    ) sub;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$function$;

-- ===== functions/fnd_tenant_time_zone.sql =====
-- ============================================================
-- fnd_tenant_time_zone
-- The tenant's IANA time zone (fnd_tenants.time_zone). SECURITY DEFINER because fnd_tenants is not readable under the
-- app token's row level security; it returns only this one setting, and only to members of the tenant (tenant in
-- allowed_tenant_ids) or a trusted connection without JWT claims. NULL for anyone else.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_tenant_time_zone(p_tenant_id bigint)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT t.time_zone
      FROM fnd_tenants t
     WHERE t.tenant_id = p_tenant_id
       AND (
            NULLIF(current_setting('request.jwt.claims', true), '') IS NULL
            OR p_tenant_id::text = ANY (ARRAY(SELECT jsonb_array_elements_text(
                NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids')))
       );
$function$;

-- ===== functions/om_production_cutoff_calc.sql =====
-- ============================================================
-- om_production_cutoff_calc
-- Default cutoff for a production date + code from om_production_codes:
--   (production_date - cutoff_days_before) at cutoff_time, in the tenant's time zone.
-- Returns NULL when the code has no active settings row.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_cutoff_calc(
    p_tenant_id       bigint,
    p_production_date date,
    p_production_code text
)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT ((p_production_date - pc.cutoff_days_before) + pc.cutoff_time) AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id)
      FROM om_production_codes pc
     WHERE pc.tenant_id       = p_tenant_id
       AND pc.production_code = UPPER(TRIM(p_production_code))
       AND pc.is_active;
$function$;

-- ===== functions/om_production_cutoff_get.sql =====
-- ============================================================
-- om_production_cutoff_get
-- Cutoff status for a production date + code (and optionally a customer, who may have extra minutes).
-- Reads the run when it exists, otherwise the default from om_production_codes. Never creates a run.
-- Returns: { production_run_id, run_status, cutoff_at, extra_minutes, effective_cutoff_at, time_zone, is_open }
-- is_open = run is OPEN (or does not exist yet) and now is before effective_cutoff_at (no settings = open).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_cutoff_get(
    p_tenant_id       bigint,
    p_production_date date,
    p_production_code text,
    p_customer_id     bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code      text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_run       om_production_runs%ROWTYPE;
    v_cutoff    timestamptz;
    v_extra     integer := 0;
    v_effective timestamptz;
    v_status    text;
    v_tz        text;
    v_open      boolean;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;
    v_tz := bps.fnd_tenant_time_zone(p_tenant_id);

    IF p_production_date IS NULL OR v_code IS NULL THEN
        RETURN jsonb_build_object('production_run_id', NULL, 'run_status', NULL, 'cutoff_at', NULL,
            'extra_minutes', 0, 'effective_cutoff_at', NULL, 'time_zone', v_tz, 'is_open', TRUE);
    END IF;

    SELECT * INTO v_run
      FROM om_production_runs
     WHERE tenant_id = p_tenant_id AND production_date = p_production_date AND production_code = v_code;
    IF FOUND THEN
        v_cutoff := v_run.cutoff_at;
        v_status := v_run.run_status;
    ELSE
        v_cutoff := bps.om_production_cutoff_calc(p_tenant_id, p_production_date, v_code);
    END IF;

    IF p_customer_id IS NOT NULL THEN
        v_extra := bps.om_customer_cutoff_extra_minutes(p_tenant_id, p_customer_id);
    END IF;
    IF v_cutoff IS NOT NULL THEN
        v_effective := v_cutoff + make_interval(mins => v_extra);
    END IF;

    v_open := COALESCE(v_status, 'OPEN') = 'OPEN'
          AND (v_effective IS NULL OR clock_timestamp() < v_effective);

    RETURN jsonb_build_object(
        'production_run_id',   v_run.production_run_id,
        'run_status',          v_status,
        'cutoff_at',           v_cutoff,
        'extra_minutes',       v_extra,
        'effective_cutoff_at', v_effective,
        'time_zone',           v_tz,
        'is_open',             v_open
    );
END;
$function$;

-- ===== functions/om_production_runs_get.sql =====
-- ============================================================
-- om_production_runs_get  –  runs in a production-date range with their order counts (newest first).
-- p_upcoming_only = true limits to runs from yesterday (tenant time zone) onward; the date is worked out here, not by the caller.
-- cutoff_local is the cutoff in the tenant's time zone ('YYYY-MM-DDTHH:MI') for editing.
-- ============================================================
DROP FUNCTION IF EXISTS bps.om_production_runs_get(bigint, date, date);

CREATE OR REPLACE FUNCTION bps.om_production_runs_get(p_tenant_id bigint, p_from date, p_to date, p_upcoming_only boolean DEFAULT false)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'production_run_id', r.production_run_id,
               'production_date',   r.production_date,
               'production_code',   r.production_code,
               'delivery_date',     r.delivery_date,
               'cutoff_at',         r.cutoff_at,
               'cutoff_local',      to_char(r.cutoff_at AT TIME ZONE bps.fnd_tenant_time_zone(r.tenant_id), 'YYYY-MM-DD"T"HH24:MI'),
               'time_zone',         bps.fnd_tenant_time_zone(r.tenant_id),
               'run_status',        r.run_status,
               'order_count',       (SELECT COUNT(*) FROM om_orders o WHERE o.production_run_id = r.production_run_id)
           ) ORDER BY r.production_date DESC, r.production_code), '[]'::jsonb)
      FROM om_production_runs r
     WHERE r.tenant_id = p_tenant_id
       AND r.production_date BETWEEN COALESCE(p_from, DATE '0001-01-01') AND COALESCE(p_to, DATE '9999-12-31')
       AND (NOT p_upcoming_only OR r.production_date >= ((now() AT TIME ZONE bps.fnd_tenant_time_zone(r.tenant_id))::date - 1));
$function$;

-- ===== functions/om_production_run_cutoff_save.sql =====
-- ============================================================
-- om_production_run_cutoff_save  –  staff change one run's cutoff (holidays, special runs). OPEN runs only.
-- p_cutoff_local is a wall-clock time in the TENANT's time zone (fnd_tenants.time_zone), e.g. '2026-11-25 12:00'.
-- ============================================================
DROP FUNCTION IF EXISTS bps.om_production_run_cutoff_save(bigint, bigint, timestamptz);

CREATE OR REPLACE FUNCTION bps.om_production_run_cutoff_save(p_tenant_id bigint, p_production_run_id bigint, p_cutoff_local timestamp)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
    IF p_tenant_id IS NULL OR p_production_run_id IS NULL OR p_cutoff_local IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id, p_production_run_id and p_cutoff_local are required';
    END IF;
    UPDATE om_production_runs r
       SET cutoff_at = p_cutoff_local AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id)
     WHERE r.tenant_id = p_tenant_id AND r.production_run_id = p_production_run_id AND r.run_status = 'OPEN';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Run % not found, not open, or you are not allowed to change it', p_production_run_id;
    END IF;
    RETURN jsonb_build_object('success', TRUE, 'production_run_id', p_production_run_id);
END;
$function$;

-- ===== functions/om_report_defaults_get.sql =====
-- ============================================================
-- om_report_defaults_get
-- Defaults for the production pages: the next production date (tenant-local today + 1) as both from and to date,
-- and the production codes (value + label) in display order.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_report_defaults_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT jsonb_build_object(
        'from_date', ((now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC'))::date + 1),
        'to_date',   ((now() AT TIME ZONE COALESCE(bps.fnd_tenant_time_zone(p_tenant_id), 'UTC'))::date + 1),
        'production_codes', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('value', UPPER(v.value), 'label', v.label) ORDER BY v.display_order, v.value)
              FROM fnd_valuesets s
              JOIN fnd_valueset_values v ON v.valueset_id = s.valueset_id
             WHERE s.tenant_id = p_tenant_id AND s.valueset_code = 'PRODUCTIONCODE'
        ), '[]'::jsonb)
    );
$function$;

-- ===== grants =====
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE fnd_tenant_sequences TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ar_transactions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ar_transaction_lines TO authenticated;
GRANT EXECUTE ON FUNCTION bps.fnd_is_tenant_staff(bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_customer_invoice_owner(bigint, bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_customer_delivery_method(bigint, bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_production_run_process(bigint, bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_production_runs_process(bigint, date, date, text) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.fnd_tenant_sequences_get(bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.fnd_tenant_sequences_save(bigint, jsonb) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.om_report_defaults_get(bigint) TO authenticated, bps_dev, service_role;
GRANT EXECUTE ON FUNCTION bps.fnd_tenant_time_zone(bigint) TO authenticated, bps_dev, service_role;

-- ===== migration/seed_om_production_settings.sql (numbering sequences) =====
-- ============================================================
-- Seed production-code cutoffs, delivery methods and invoice/shipment/credit-memo numbering for tenant "Alpine Bakery" (local data).
-- Cutoffs are defaults only (4:00 PM the day before, delivery the day after): adjust in Admin > Production Codes.
-- Idempotent. Prerequisites: om_production_codes.sql, om_delivery_methods.sql, PRODUCTIONCODE valueset seeded.
-- ============================================================
DO $$
DECLARE v_tenant_id BIGINT;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM bps.fnd_tenants WHERE tenant_name = 'Alpine Bakery' LIMIT 1;
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    INSERT INTO bps.om_production_codes (tenant_id, production_code, cutoff_time, cutoff_days_before, delivery_days_after)
    SELECT v_tenant_id, UPPER(v.value), TIME '16:00', 1, 1
      FROM bps.fnd_valuesets s JOIN bps.fnd_valueset_values v ON v.valueset_id = s.valueset_id
     WHERE s.tenant_id = v_tenant_id AND s.valueset_code = 'PRODUCTIONCODE'
    ON CONFLICT (tenant_id, production_code) DO NOTHING;

    INSERT INTO bps.om_delivery_methods (tenant_id, delivery_method_code, delivery_method_name, is_own_fleet, requires_tracking)
    VALUES
        (v_tenant_id, 'OWN_TRUCK', 'Own truck',  TRUE,  FALSE),
        (v_tenant_id, 'CARRIER',   'Carrier (UPS, FedEx)', FALSE, TRUE),
        (v_tenant_id, 'COURIER',   'Courier (Uber)',       FALSE, FALSE),
        (v_tenant_id, 'PICKUP',    'Customer pickup',      FALSE, FALSE)
    ON CONFLICT (tenant_id, delivery_method_code) DO NOTHING;

    -- Numbering (settings are editable in Admin > Production Settings)
    INSERT INTO bps.fnd_tenant_sequences (tenant_id, sequence_name, start_value, next_value, increment_by, mask, reset_period, requires_gapless)
    VALUES
        (v_tenant_id, 'invoice_number',     1000, 1000, 1, 'INV-######', 'NEVER', FALSE),
        (v_tenant_id, 'shipment_number',    1000, 1000, 1, 'SHP-######', 'NEVER', FALSE),
        (v_tenant_id, 'credit_memo_number', 1000, 1000, 1, 'CM-######',  'NEVER', FALSE)
    ON CONFLICT (tenant_id, sequence_name) DO NOTHING;
END $$;
