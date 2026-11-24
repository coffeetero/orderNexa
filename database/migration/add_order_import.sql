-- Import Orders (Orders > Import Orders). Staff pick an account, production date and code and upload the customer's CSV
-- (cus no, item number, item desc, qty). Each row is checked; good rows become orders (one per cus no, through om_orders_save)
-- and every row is kept with its issue. Imported orders stay out of production until the import is approved.
-- Approved names: om_orders.import_status, om_orders.order_import_id, tables om_order_imports and om_order_import_rows.
-- Run after: add_rls_access_model.sql, fix_rls_performance.sql. Then load the om_production_run_process / om_report_* /
-- om_run_item_quantities / om_production_runs_get function files (they skip orders whose import is not approved).
SET search_path = bps, public;

-- ── tables ──────────────────────────────────────────────────────────────────
CREATE TABLE bps.om_order_imports (
  order_import_id   bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id         bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  customer_id       bigint NOT NULL REFERENCES bps.fnd_customers(customer_id),
  production_date   date   NOT NULL,
  production_code   text   NOT NULL,
  file_name         text,
  import_status     text   NOT NULL CONSTRAINT chk_om_order_imports_status CHECK (import_status IN ('IMPORTED', 'ISSUES', 'APPROVED')),
  row_count         integer NOT NULL DEFAULT 0,
  order_count       integer NOT NULL DEFAULT 0,
  error_count       integer NOT NULL DEFAULT 0,
  warning_count     integer NOT NULL DEFAULT 0,
  total_amount      numeric(14,2) NOT NULL DEFAULT 0,
  approved_at       timestamptz,
  approved_by       bigint,
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        bigint,
  updated_at        timestamptz NOT NULL DEFAULT now(),
  updated_by        bigint
);
CREATE INDEX idx_om_order_imports_slot ON bps.om_order_imports (tenant_id, customer_id, production_date, production_code);
CREATE INDEX idx_om_order_imports_date ON bps.om_order_imports (tenant_id, production_date DESC);

CREATE TABLE bps.om_order_import_rows (
  order_import_row_id bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id           bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  order_import_id     bigint NOT NULL REFERENCES bps.om_order_imports(order_import_id) ON DELETE CASCADE,
  row_number          integer NOT NULL,
  cus_no              text,
  item_number         text,
  item_desc           text,
  qty_text            text,
  customer_id         bigint REFERENCES bps.fnd_customers(customer_id),
  item_id             bigint REFERENCES bps.fnd_items(item_id),
  quantity            numeric(14,4),
  unit_price          numeric(14,4),
  severity            text CONSTRAINT chk_om_order_import_rows_severity CHECK (severity IN ('ERROR', 'WARNING')),
  issue               text,
  order_id            bigint REFERENCES bps.om_orders(order_id) ON DELETE SET NULL,
  order_line_id       bigint REFERENCES bps.om_order_lines(order_line_id) ON DELETE SET NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_om_order_import_rows_number UNIQUE (order_import_id, row_number)
);
CREATE INDEX idx_om_order_import_rows_order ON bps.om_order_import_rows (order_id) WHERE order_id IS NOT NULL;
CREATE INDEX idx_om_order_import_rows_line ON bps.om_order_import_rows (order_line_id) WHERE order_line_id IS NOT NULL;

ALTER TABLE bps.om_orders
  ADD COLUMN import_status text CONSTRAINT chk_om_orders_import_status CHECK (import_status IN ('IMPORTED', 'ISSUES', 'APPROVED')),
  ADD COLUMN order_import_id bigint REFERENCES bps.om_order_imports(order_import_id) ON DELETE SET NULL;
CREATE INDEX idx_om_orders_order_import ON bps.om_orders (order_import_id) WHERE order_import_id IS NOT NULL;

-- ── row security: staff with order entry access, own tenancy ────────────────
ALTER TABLE bps.om_order_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.om_order_import_rows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON bps.om_order_imports, bps.om_order_import_rows FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON bps.om_order_imports, bps.om_order_import_rows TO authenticated;
GRANT ALL ON bps.om_order_imports, bps.om_order_import_rows TO bps_dev;

CREATE POLICY pol_om_order_imports_read ON bps.om_order_imports FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access_any('{orders.enter,orders.manage}'::text[], 'R'))));
CREATE POLICY pol_om_order_imports_write ON bps.om_order_imports FOR ALL TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access_any('{orders.enter,orders.manage}'::text[], 'W'))))
  WITH CHECK ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access_any('{orders.enter,orders.manage}'::text[], 'W'))));
CREATE POLICY pol_om_order_import_rows_read ON bps.om_order_import_rows FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access_any('{orders.enter,orders.manage}'::text[], 'R'))));
CREATE POLICY pol_om_order_import_rows_write ON bps.om_order_import_rows FOR ALL TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access_any('{orders.enter,orders.manage}'::text[], 'W'))))
  WITH CHECK ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access_any('{orders.enter,orders.manage}'::text[], 'W'))));
