-- ============================================================
-- FND_NOTES  –  Polymorphic notes for any entity
-- Target: Supabase (PostgreSQL 15+)
--
-- Stores notes for items, customers, orders, tenants, etc.
-- Entity is identified by entity_id (from fnd_entity_id_seq) +
-- source_table (e.g. 'fnd_items', 'fnd_customers').
--
-- visibility controls customer access:
--   'tenant_only' – tenant staff only
--   'shared'      – visible to both tenant and customer users
--
-- note_id uses global fnd_entity_id_seq.
-- created_by / updated_by are BIGINT app user ids (fnd_users.user_id).
--
-- Run after: fnd_tenants.sql, fnd_entity_id_seq.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_notes (
    tenant_id      BIGINT        NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    note_id        BIGINT        PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    -- Entity link
    entity_id      BIGINT        NOT NULL,
    source_table   TEXT          NOT NULL,   -- e.g. 'fnd_items', 'fnd_customers', 'om_orders'

    -- Content
    note_title     TEXT,
    note_text      TEXT          NOT NULL,
    note_type      TEXT,                     -- fnd_valuesets controlled; unused initially

    -- Flags
    is_important   BOOLEAN       NOT NULL DEFAULT FALSE,
    is_pinned      BOOLEAN       NOT NULL DEFAULT FALSE,
    visibility     TEXT          NOT NULL DEFAULT 'tenant_only'
                                 CHECK (visibility IN ('tenant_only', 'shared')),

    -- Soft delete
    deleted_at     TIMESTAMPTZ,

    -- Audit
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    created_by     BIGINT,
    updated_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_by     BIGINT
);

-- Ownership: application tables are owned by bps_owner; runtime access is via grants + RLS.
ALTER TABLE fnd_notes OWNER TO bps_owner;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_fnd_notes_entity
    ON fnd_notes (tenant_id, entity_id)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_fnd_notes_entity_source
    ON fnd_notes (tenant_id, entity_id, source_table)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_fnd_notes_source_table
    ON fnd_notes (tenant_id, source_table)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_fnd_notes_pinned
    ON fnd_notes (tenant_id, entity_id)
    WHERE is_pinned = TRUE AND deleted_at IS NULL;

-- Triggers
DROP TRIGGER IF EXISTS trg_fnd_notes_set_updated ON fnd_notes;
CREATE TRIGGER trg_fnd_notes_set_updated
    BEFORE UPDATE ON fnd_notes
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_notes_audit ON fnd_notes;
CREATE TRIGGER trg_fnd_notes_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_notes
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('note_id');

-- RLS policies: fnd_notes_policies.sql
