-- ============================================================
-- FND_USER_RECENT_RECORDS  –  Per-user, per-tenant recently accessed records
--
-- Drives the sidebar "Recent ..." lists. label/sublabel are snapshots taken when the record was last
-- opened, so the sidebar needs no joins. The functions keep at most 20 rows per (user, tenant, type).
-- record_key is text: ids for customer/order/item, 'YYYY-MM-DD|CODE' for production_run.
--
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- Run after: fnd_users.sql, fnd_tenants.sql. Policies: ../policies/fnd_user_recent_records_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_user_recent_records (
    user_id           BIGINT       NOT NULL REFERENCES fnd_users(user_id)     ON DELETE CASCADE,
    tenant_id         BIGINT       NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    record_type       TEXT         NOT NULL,
    record_key        TEXT         NOT NULL,
    label             TEXT         NOT NULL,
    sublabel          TEXT,
    access_count      INTEGER      NOT NULL DEFAULT 1,
    last_accessed_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_fnd_user_recent_records PRIMARY KEY (user_id, tenant_id, record_type, record_key),
    CONSTRAINT ck_fnd_user_recent_records_type CHECK (record_type IN ('customer', 'order', 'item', 'production_run')),
    CONSTRAINT ck_fnd_user_recent_records_key CHECK (length(record_key) BETWEEN 1 AND 64),
    CONSTRAINT ck_fnd_user_recent_records_label CHECK (length(label) BETWEEN 1 AND 200),
    CONSTRAINT ck_fnd_user_recent_records_sublabel CHECK (sublabel IS NULL OR length(sublabel) <= 200)
);

CREATE INDEX IF NOT EXISTS idx_fnd_user_recent_records_lookup
    ON fnd_user_recent_records (user_id, tenant_id, record_type, last_accessed_at DESC);

COMMENT ON TABLE fnd_user_recent_records IS
    'Recently opened customers/orders/items/production runs per user and tenant (max 20 per type).';
