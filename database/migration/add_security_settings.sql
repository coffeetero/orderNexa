-- =====================================================================================
-- Company-level security settings (Admin > Application Settings > Security): idle timeout, minimum password length,
-- password expiry and password history. This step stores and edits the settings; enforcement is built separately.
-- New table fnd_tenant_security_settings (one row per company; a company with no row uses the defaults below).
-- New area admin.security. Apply after add_customer_roles_area.sql.
-- =====================================================================================
SET search_path = bps, public;

CREATE TABLE bps.fnd_tenant_security_settings (
  tenant_id             BIGINT PRIMARY KEY REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  idle_timeout_minutes  INTEGER NOT NULL DEFAULT 30  CHECK (idle_timeout_minutes  BETWEEN 0 AND 1440),   -- 0 = never time out
  min_password_length   INTEGER NOT NULL DEFAULT 12  CHECK (min_password_length   BETWEEN 8 AND 128),
  password_max_age_days INTEGER NOT NULL DEFAULT 90  CHECK (password_max_age_days BETWEEN 0 AND 730),    -- 0 = never force a change
  password_history_count INTEGER NOT NULL DEFAULT 5  CHECK (password_history_count BETWEEN 0 AND 24),    -- 0 = reuse allowed
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by            BIGINT
);
COMMENT ON TABLE bps.fnd_tenant_security_settings IS 'Per-company sign-in security rules. No row = defaults. Read and written through fnd_security_settings_get/save.';

REVOKE ALL ON bps.fnd_tenant_security_settings FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE ON bps.fnd_tenant_security_settings TO authenticated;
GRANT ALL ON bps.fnd_tenant_security_settings TO bps_dev, service_role;
ALTER TABLE bps.fnd_tenant_security_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY pol_fnd_tenant_security_settings_read ON bps.fnd_tenant_security_settings FOR SELECT TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.security','R'))));
CREATE POLICY pol_fnd_tenant_security_settings_ins ON bps.fnd_tenant_security_settings FOR INSERT TO authenticated WITH CHECK (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.security','W'))));
CREATE POLICY pol_fnd_tenant_security_settings_upd ON bps.fnd_tenant_security_settings FOR UPDATE TO authenticated
  USING (bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.security','W'))))
  WITH CHECK (bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.security','W'))));

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('admin.security', 'Admin', 'Security', 'TENANT', 607) ON CONFLICT (area_key) DO NOTHING;
DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_security_settings_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE s bps.fnd_tenant_security_settings;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  SELECT * INTO s FROM bps.fnd_tenant_security_settings WHERE tenant_id = p_tenant_id;
  IF NOT FOUND THEN  -- defaults come from the column defaults
    s.idle_timeout_minutes := 30; s.min_password_length := 12; s.password_max_age_days := 90; s.password_history_count := 5;
  END IF;
  RETURN jsonb_build_object('idle_timeout_minutes', s.idle_timeout_minutes, 'min_password_length', s.min_password_length,
    'password_max_age_days', s.password_max_age_days, 'password_history_count', s.password_history_count);
END $$;

-- payload: {idle_timeout_minutes, min_password_length, password_max_age_days, password_history_count}; the table checks give the range errors.
CREATE OR REPLACE FUNCTION bps.fnd_security_settings_save(p_tenant_id bigint, p_payload jsonb) RETURNS void
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE cur jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  cur := bps.fnd_security_settings_get(p_tenant_id) || COALESCE(p_payload, '{}'::jsonb);
  INSERT INTO bps.fnd_tenant_security_settings AS s (tenant_id, idle_timeout_minutes, min_password_length, password_max_age_days, password_history_count, updated_by)
  VALUES (p_tenant_id, (cur ->> 'idle_timeout_minutes')::int, (cur ->> 'min_password_length')::int,
          (cur ->> 'password_max_age_days')::int, (cur ->> 'password_history_count')::int, bps.fnd_current_user_id())
  ON CONFLICT (tenant_id) DO UPDATE SET idle_timeout_minutes = EXCLUDED.idle_timeout_minutes, min_password_length = EXCLUDED.min_password_length,
    password_max_age_days = EXCLUDED.password_max_age_days, password_history_count = EXCLUDED.password_history_count,
    updated_at = now(), updated_by = EXCLUDED.updated_by;
END $$;

REVOKE EXECUTE ON FUNCTION bps.fnd_security_settings_get(bigint), bps.fnd_security_settings_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION bps.fnd_security_settings_get(bigint), bps.fnd_security_settings_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
