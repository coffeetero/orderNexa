-- ============================================================
-- FND_USER_PREFERENCES  –  Per-user app preferences (one row per user)
--
-- Follows the PERSON (not the tenant), so there is no tenant_id (same as fnd_user_menu_actions).
-- appearance: jsonb { mode: 'light'|'dark'|'system', themeId, custom: [ {id,label,inputs} ... ] } — colours only,
--   validated by the app (website/lib/theme/prefs.ts); the database only guarantees a bounded JSON object.
-- user_preference_id uses fnd_entity_id_seq (run fnd_entity_id_seq.sql before this file).
--
-- Schema: unqualified identifiers — set search_path before apply, e.g. SET search_path = bps, public;
-- Run after: fnd_users.sql. Policies: ../policies/fnd_user_preferences_policies.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_user_preferences (
    user_preference_id  BIGINT       PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    user_id             BIGINT       NOT NULL REFERENCES fnd_users(user_id) ON DELETE CASCADE,
    appearance          JSONB        NOT NULL DEFAULT '{}'::jsonb,

    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_by          BIGINT,
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_by          BIGINT,

    CONSTRAINT uq_fnd_user_preferences_user UNIQUE (user_id),
    CONSTRAINT chk_fnd_user_preferences_appearance CHECK (
        jsonb_typeof(appearance) = 'object' AND pg_column_size(appearance) <= 65536
    )
);

COMMENT ON TABLE fnd_user_preferences IS
    'Per-user preferences (appearance: mode, selected theme, own themes). One row per user; not tenant-scoped.';
