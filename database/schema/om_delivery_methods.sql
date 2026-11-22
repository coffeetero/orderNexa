-- ============================================================
-- OM_DELIVERY_METHODS  –  Per-tenant, table-driven delivery methods
--
-- e.g. OWN_TRUCK (is_own_fleet), CARRIER (UPS/FedEx, requires_tracking), COURIER (Uber), PICKUP.
-- is_own_fleet = true means the method appears on the driver's delivery sheet.
-- fnd_customers.delivery_method_code points here (null = inherit from the parent customer).
--
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- Run after: fnd_customers.sql, fnd_tenants.sql. Policies: ../policies/om_delivery_methods_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS om_delivery_methods (
    tenant_id              BIGINT       NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    delivery_method_code   TEXT         NOT NULL,
    delivery_method_name   TEXT         NOT NULL,
    is_own_fleet           BOOLEAN      NOT NULL DEFAULT FALSE,
    requires_tracking      BOOLEAN      NOT NULL DEFAULT FALSE,
    is_active              BOOLEAN      NOT NULL DEFAULT TRUE,

    created_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_by             BIGINT,
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_by             BIGINT,

    PRIMARY KEY (tenant_id, delivery_method_code),
    CONSTRAINT chk_om_delivery_methods_code CHECK (delivery_method_code = UPPER(TRIM(delivery_method_code)) AND delivery_method_code <> '')
);

ALTER TABLE om_delivery_methods OWNER TO bps_owner;

DROP TRIGGER IF EXISTS trg_om_delivery_methods_set_updated ON om_delivery_methods;
CREATE TRIGGER trg_om_delivery_methods_set_updated
    BEFORE UPDATE ON om_delivery_methods
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

COMMENT ON TABLE om_delivery_methods IS
    'Per-tenant delivery methods (own truck, carrier, courier, pickup). Referenced by customers and, later, shipments.';

-- Customer default delivery method (added here because fnd_customers is created before this table).
ALTER TABLE fnd_customers ADD COLUMN IF NOT EXISTS delivery_method_code TEXT;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_fnd_customers_delivery_method') THEN
        ALTER TABLE fnd_customers
            ADD CONSTRAINT fk_fnd_customers_delivery_method
            FOREIGN KEY (tenant_id, delivery_method_code)
            REFERENCES om_delivery_methods (tenant_id, delivery_method_code);
    END IF;
END $$;

COMMENT ON COLUMN fnd_customers.delivery_method_code IS
    'Default delivery method. NULL = inherit from the nearest ancestor customer that has one.';
