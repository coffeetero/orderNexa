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
