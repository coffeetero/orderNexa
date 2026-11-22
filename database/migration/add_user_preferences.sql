-- Per-user preferences (appearance). Generated from the files below; apply in this order.
-- Requires add_user_nav_tracking.sql first (fnd_nav_app_user_id). NOT yet applied to the cloud project.
SET search_path = bps, public;

-- ===== schema/fnd_user_preferences.sql =====
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

-- ===== policies/fnd_user_preferences_policies.sql =====
-- ============================================================
-- FND_USER_PREFERENCES — Row Level Security
-- A user can only see and change their own row (user_id = app_user_id claim).
-- Run after: fnd_user_preferences.sql, functions/fnd_nav_app_user_id.sql
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE fnd_user_preferences TO authenticated;
GRANT ALL ON TABLE fnd_user_preferences TO bps_dev;

ALTER TABLE fnd_user_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fnd_user_preferences_owner ON fnd_user_preferences;
CREATE POLICY pol_fnd_user_preferences_owner ON fnd_user_preferences
    FOR ALL
    USING      (user_id = bps.fnd_nav_app_user_id())
    WITH CHECK (user_id = bps.fnd_nav_app_user_id());

-- ===== functions/fnd_user_preferences_get.sql =====
-- ============================================================
-- fnd_user_preferences_get
-- Returns the signed-in user's preferences as { appearance: {...} } ('{}' appearance when never saved).
-- SECURITY INVOKER: RLS limits the row to the caller. Prerequisites: fnd_user_preferences.sql + policies.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_user_preferences_get()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = bps, public
AS $$
DECLARE
  v_user_id BIGINT := bps.fnd_nav_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No BPS user for this session';
  END IF;

  RETURN jsonb_build_object(
    'appearance',
    COALESCE((SELECT p.appearance FROM fnd_user_preferences p WHERE p.user_id = v_user_id), '{}'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION bps.fnd_user_preferences_get() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_user_preferences_get() TO authenticated, bps_dev, service_role;

-- ===== functions/fnd_user_preferences_save.sql =====
-- ============================================================
-- fnd_user_preferences_save
-- Creates or replaces the signed-in user's appearance preferences (p_appearance must be a JSON object, max 64 KB).
-- SECURITY INVOKER: RLS limits the row to the caller.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_user_preferences_save(p_appearance JSONB)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = bps, public
AS $$
DECLARE
  v_user_id BIGINT := bps.fnd_nav_app_user_id();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No BPS user for this session';
  END IF;

  IF p_appearance IS NULL OR jsonb_typeof(p_appearance) <> 'object' THEN
    RAISE EXCEPTION 'p_appearance must be a JSON object';
  END IF;

  INSERT INTO fnd_user_preferences (user_id, appearance, created_by, updated_by)
  VALUES (v_user_id, p_appearance, v_user_id, v_user_id)
  ON CONFLICT (user_id) DO UPDATE
    SET appearance = EXCLUDED.appearance,
        updated_at = clock_timestamp(),
        updated_by = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION bps.fnd_user_preferences_save(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bps.fnd_user_preferences_save(JSONB) TO authenticated, bps_dev, service_role;
