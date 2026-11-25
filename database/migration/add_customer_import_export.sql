-- Customers > Import Customers and Customers > Export Customers.
-- Export writes one row per customer (ACCOUNT / SITE / DEPARTMENT) with its parent's customer number; Import reads the same
-- layout back: upload -> checked preview (new / changed / unchanged / error per row) -> apply. Matched on customer number;
-- never deletes. Staging tables keep each upload and its rows.
-- Areas: customers.exports (exists; renamed Export Customers) and customers.import (new).
-- Run after: add_access_model_functions.sql. Then load the function files:
--   fnd_customer_import_value, fnd_customer_export_rows, fnd_customer_export_get, fnd_customer_import_get,
--   fnd_customer_import_validate, fnd_customer_import_upload, fnd_customer_import_apply
SET search_path = bps, public;

-- ── access areas ────────────────────────────────────────────────────────────
UPDATE bps.fnd_areas SET area_name = 'Export Customers' WHERE area_key = 'customers.exports';
INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('customers.import', 'Customers', 'Import Customers', 'TENANT', 305)
ON CONFLICT (area_key) DO NOTHING;

DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

-- ── tables ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bps.fnd_customer_imports (
  customer_import_id bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id          bigint NOT NULL CONSTRAINT fk_fnd_customer_imports_tenant REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  file_name          text,
  import_status      text   NOT NULL DEFAULT 'PREVIEW' CONSTRAINT chk_fnd_customer_imports_status CHECK (import_status IN ('PREVIEW', 'APPLIED')),
  row_count          integer NOT NULL DEFAULT 0,
  new_count          integer NOT NULL DEFAULT 0,
  changed_count      integer NOT NULL DEFAULT 0,
  unchanged_count    integer NOT NULL DEFAULT 0,
  error_count        integer NOT NULL DEFAULT 0,
  applied_at         timestamptz,
  applied_by         bigint,
  created_at         timestamptz NOT NULL DEFAULT now(),
  created_by         bigint,
  updated_at         timestamptz NOT NULL DEFAULT now(),
  updated_by         bigint
);
CREATE INDEX IF NOT EXISTS idx_fnd_customer_imports_tenant ON bps.fnd_customer_imports (tenant_id, created_at DESC);

CREATE TABLE IF NOT EXISTS bps.fnd_customer_import_rows (
  customer_import_row_id bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id          bigint NOT NULL CONSTRAINT fk_fnd_customer_import_rows_tenant REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  customer_import_id bigint NOT NULL CONSTRAINT fk_fnd_customer_import_rows_import REFERENCES bps.fnd_customer_imports(customer_import_id) ON DELETE CASCADE,
  row_number         integer NOT NULL,
  data               jsonb   NOT NULL,              -- the file's values, as text, keyed like the export
  customer_number    text,                          -- normalised customer no (mask characters removed)
  parent_number      text,                          -- normalised parent no
  customer_id        bigint CONSTRAINT fk_fnd_customer_import_rows_customer REFERENCES bps.fnd_customers(customer_id) ON DELETE SET NULL,
  hierarchy_depth    integer,                       -- 0 = parent not in the file; children are applied after their parents
  row_action         text CONSTRAINT chk_fnd_customer_import_rows_action CHECK (row_action IN ('NEW', 'CHANGED', 'UNCHANGED', 'ERROR')),
  changes            jsonb,                         -- [{field, from, to}] for CHANGED rows
  current_data       jsonb,                         -- the customer's current export values and contact ids (internal)
  issue              text,                          -- errors, or notes on good rows
  created_at         timestamptz NOT NULL DEFAULT now(),
  created_by         bigint,
  updated_at         timestamptz NOT NULL DEFAULT now(),
  updated_by         bigint,
  CONSTRAINT uq_fnd_customer_import_rows_number UNIQUE (customer_import_id, row_number)
);
CREATE INDEX IF NOT EXISTS idx_fnd_customer_import_rows_customer ON bps.fnd_customer_import_rows (customer_id) WHERE customer_id IS NOT NULL;

-- ── row security: staff with Import Customers access, own tenancy ───────────
ALTER TABLE bps.fnd_customer_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_customer_import_rows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON bps.fnd_customer_imports, bps.fnd_customer_import_rows FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON bps.fnd_customer_imports, bps.fnd_customer_import_rows TO authenticated;
GRANT ALL ON bps.fnd_customer_imports, bps.fnd_customer_import_rows TO bps_dev;

DROP POLICY IF EXISTS pol_fnd_customer_imports_read ON bps.fnd_customer_imports;
CREATE POLICY pol_fnd_customer_imports_read ON bps.fnd_customer_imports FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('customers.import', 'R'))));
DROP POLICY IF EXISTS pol_fnd_customer_imports_write ON bps.fnd_customer_imports;
CREATE POLICY pol_fnd_customer_imports_write ON bps.fnd_customer_imports FOR ALL TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('customers.import', 'W'))))
  WITH CHECK ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('customers.import', 'W'))));
DROP POLICY IF EXISTS pol_fnd_customer_import_rows_read ON bps.fnd_customer_import_rows;
CREATE POLICY pol_fnd_customer_import_rows_read ON bps.fnd_customer_import_rows FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('customers.import', 'R'))));
DROP POLICY IF EXISTS pol_fnd_customer_import_rows_write ON bps.fnd_customer_import_rows;
CREATE POLICY pol_fnd_customer_import_rows_write ON bps.fnd_customer_import_rows FOR ALL TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('customers.import', 'W'))))
  WITH CHECK ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('customers.import', 'W'))));
