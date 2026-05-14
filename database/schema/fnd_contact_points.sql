-- ============================================================
-- FND_CONTACT_POINTS  –  Contact methods for any contact (tenant-scoped)
-- Target: Supabase (PostgreSQL 15+)
--
-- Stores phone, mobile, fax, email, address, website, and other
-- contact methods for a contact. The value column is multiline TEXT —
-- users can add inline context alongside the value (e.g. a phone
-- number with "leave voicemail only" on the next line).
--
-- Address geocoding: rows with type = 'ADDRESS' are picked up by a
-- background job that sends value to Google Geocoding API. The raw
-- JSONB response is stored in google_geocode_response; high-level
-- fields (lat/lng, country, state, city, postal_code) are extracted
-- as proper columns for querying and delivery routing.
--
-- contact_point_id uses fnd_entity_id_seq — run fnd_entity_id_seq.sql first.
-- Run after: fnd_tenants.sql, fnd_contacts.sql
-- Triggers: fn_set_updated_at_ts_only, fn_audit_log
-- RLS: fnd_contact_points_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_contact_points (
    tenant_id               BIGINT      NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    contact_point_id        BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    contact_id              BIGINT      NOT NULL REFERENCES fnd_contacts(contact_id) ON DELETE CASCADE,

    -- ── Core ─────────────────────────────────────────────────
    type                    TEXT        NOT NULL,   -- see CHECK below
    -- Multiline: the contact value itself, plus any inline notes the user adds.
    -- e.g. "407 242-9011\nleave voicemail only"
    value                   TEXT        NOT NULL,
    label                   TEXT,                   -- 'Home' | 'Work' | 'Billing' | 'Delivery' | ...

    -- ── Display name (person for this specific point) ────────
    -- e.g. "Mary Brown", "Bob - Loading Dock", "Accounts Payable"
    -- Auto-derived from contact first+last in the UI; user can override.
    -- Shown as line 2 in the card selector (from the primary point).
    display_name            TEXT,

    -- ── Ordering & flags ─────────────────────────────────────
    sequence                SMALLINT    NOT NULL DEFAULT 1,   -- order within type
    is_primary              BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active               BOOLEAN     NOT NULL DEFAULT TRUE,
    do_not_contact          BOOLEAN     NOT NULL DEFAULT FALSE,
    -- For ADDRESS points labelled 'Billing' on the ADDRESSES contact:
    -- when TRUE the billing address also serves as the shipping address
    use_as_shipping         BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ── Verification & consent ───────────────────────────────
    is_verified             BOOLEAN     NOT NULL DEFAULT FALSE,
    verified_at             TIMESTAMPTZ,
    consent_given_at        TIMESTAMPTZ,            -- marketing / comms opt-in timestamp

    -- ── Phone / fax ──────────────────────────────────────────
    country_dial_code       TEXT,                   -- '+1' | '+44' | '+61' ...

    -- ── Address geocoding ─────────────────────────────────────
    -- Populated by batch job; NULL / SKIPPED for non-ADDRESS types.
    geocode_status          TEXT        NOT NULL DEFAULT 'PENDING',
    geocoded_at             TIMESTAMPTZ,
    geocode_attempts        SMALLINT    NOT NULL DEFAULT 0,
    -- Google-authoritative single-line formatted address
    formatted_address       TEXT,
    -- Stable Google place identifier — avoids re-geocoding on minor edits
    google_place_id         TEXT,
    -- Raw API response — source of truth; extracted columns derived from this
    google_geocode_response JSONB,
    -- Extracted fields for querying, filtering, routing
    latitude                NUMERIC(10,7),
    longitude               NUMERIC(10,7),
    country_code            CHAR(2),                -- ISO 3166-1 alpha-2
    state_province          TEXT,                   -- administrative_area_level_1
    city                    TEXT,                   -- locality / sublocality
    postal_code             TEXT,

    -- ── Audit ────────────────────────────────────────────────
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              BIGINT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              BIGINT,

    -- ── Constraints ──────────────────────────────────────────
    CONSTRAINT chk_fnd_contact_points_type CHECK (
        type IN ('PHONE', 'MOBILE', 'FAX', 'EMAIL', 'ADDRESS', 'WEBSITE', 'OTHER', 'NOTE')
    ),
    CONSTRAINT chk_fnd_contact_points_geocode_status CHECK (
        geocode_status IN ('PENDING', 'PROCESSING', 'OK', 'ZERO_RESULTS', 'FAILED', 'SKIPPED')
    )
);

-- ── Legacy cleanup ────────────────────────────────────────────────────────────

ALTER TABLE fnd_contact_points DROP COLUMN IF EXISTS entity_id;
DROP INDEX IF EXISTS idx_fnd_contact_points_entity_id;

-- Remove any old label-based CHECK constraint (previous deployments)
DO $$
DECLARE v_con TEXT;
BEGIN
    SELECT c.conname INTO v_con
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = current_schema()
      AND t.relname = 'fnd_contact_points'
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%label%'
      AND pg_get_constraintdef(c.oid) ILIKE '%billing%'
    LIMIT 1;
    IF v_con IS NOT NULL THEN
        EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I',
                       current_schema(), 'fnd_contact_points', v_con);
    END IF;
END $$;

-- ── Indexes ───────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_fnd_contact_points_tenant
    ON fnd_contact_points (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_contact_points_contact
    ON fnd_contact_points (tenant_id, contact_id);

-- Fast lookup for a specific type (e.g. all phones for a contact)
CREATE INDEX IF NOT EXISTS idx_fnd_contact_points_type
    ON fnd_contact_points (tenant_id, contact_id, type);

-- One primary per type per contact
CREATE UNIQUE INDEX IF NOT EXISTS uq_fnd_contact_points_primary
    ON fnd_contact_points (tenant_id, contact_id, type)
    WHERE is_primary = TRUE;

-- Geocoding job queue: addresses still needing processing
CREATE INDEX IF NOT EXISTS idx_fnd_contact_points_geocode_pending
    ON fnd_contact_points (tenant_id, geocode_attempts)
    WHERE type = 'ADDRESS' AND geocode_status = 'PENDING';

-- Spatial queries (route optimisation, delivery radius)
CREATE INDEX IF NOT EXISTS idx_fnd_contact_points_latlon
    ON fnd_contact_points (latitude, longitude)
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- ── Trigger: auto-set geocode_status on INSERT ────────────────────────────────
-- Non-ADDRESS rows are SKIPPED immediately; ADDRESS rows stay PENDING.
-- Also resets to PENDING on UPDATE if value changes (re-geocode needed).

CREATE OR REPLACE FUNCTION fn_contact_point_geocode_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.type != 'ADDRESS' THEN
        NEW.geocode_status := 'SKIPPED';
    ELSIF TG_OP = 'UPDATE' AND NEW.value IS DISTINCT FROM OLD.value THEN
        -- Address text changed — queue for re-geocoding
        NEW.geocode_status   := 'PENDING';
        NEW.geocode_attempts := 0;
        NEW.geocoded_at      := NULL;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fnd_contact_points_geocode_status ON fnd_contact_points;
CREATE TRIGGER trg_fnd_contact_points_geocode_status
    BEFORE INSERT OR UPDATE ON fnd_contact_points
    FOR EACH ROW EXECUTE FUNCTION fn_contact_point_geocode_status();

-- ── Standard triggers ─────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trg_fnd_contact_points_set_updated ON fnd_contact_points;
CREATE TRIGGER trg_fnd_contact_points_set_updated
    BEFORE UPDATE ON fnd_contact_points
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_contact_points_audit ON fnd_contact_points;
CREATE TRIGGER trg_fnd_contact_points_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_contact_points
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('contact_point_id');
