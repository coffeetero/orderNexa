-- ============================================================
-- FND_CONTACTS  –  Person / contact master (tenant-scoped)
-- Target: Supabase (PostgreSQL 15+)
--
-- Polymorphic: one contact can belong to any entity via
-- (entity_id, source_table). e.g. source_table = 'fnd_customers'.
--
-- contact_id uses fnd_entity_id_seq — run fnd_entity_id_seq.sql first.
-- Run after: fnd_tenants.sql
-- Triggers: fn_set_updated_at_ts_only, fn_audit_log
-- RLS: fnd_contacts_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_contacts (
    tenant_id           BIGINT      NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    contact_id          BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    -- ── Polymorphic owner ────────────────────────────────────
    entity_id           BIGINT      NOT NULL,
    source_table        TEXT        NOT NULL,   -- 'fnd_customers' | 'fnd_users' | 'fnd_tenants' | ...

    -- ── Person details ───────────────────────────────────────
    salutation          TEXT,                   -- Mr. Ms. Dr. etc.
    first_name          TEXT,
    last_name           TEXT,
    -- contact_name is the display name; defaults to first + last but
    -- can be overridden (e.g. company name, nickname, single-word name)
    contact_name        TEXT        NOT NULL,
    job_title           TEXT,
    department          TEXT,

    -- ── Flags ────────────────────────────────────────────────
    is_primary          BOOLEAN     NOT NULL DEFAULT FALSE,  -- primary contact for the entity
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    -- ── Preferences ──────────────────────────────────────────
    language_preference TEXT,                   -- ISO 639-1  e.g. 'en'  'fr'
    timezone            TEXT,                   -- IANA  e.g. 'America/New_York'

    -- ── Free-form notes ──────────────────────────────────────
    notes               TEXT,

    -- ── Audit ────────────────────────────────────────────────
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          BIGINT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          BIGINT
);

-- ── Indexes ──────────────────────────────────────────────────────────────────

-- Primary lookup: all contacts for an entity
CREATE INDEX IF NOT EXISTS idx_fnd_contacts_entity
    ON fnd_contacts (tenant_id, source_table, entity_id);

-- Tenant-wide active contacts
CREATE INDEX IF NOT EXISTS idx_fnd_contacts_active
    ON fnd_contacts (tenant_id)
    WHERE is_active = TRUE;

-- Only one primary contact per entity
CREATE UNIQUE INDEX IF NOT EXISTS uq_fnd_contacts_primary
    ON fnd_contacts (tenant_id, source_table, entity_id)
    WHERE is_primary = TRUE;

-- ── Triggers ─────────────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_fnd_contacts_set_updated ON fnd_contacts;
CREATE TRIGGER trg_fnd_contacts_set_updated
    BEFORE UPDATE ON fnd_contacts
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_contacts_audit ON fnd_contacts;
CREATE TRIGGER trg_fnd_contacts_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_contacts
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('contact_id');
