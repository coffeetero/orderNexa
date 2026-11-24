-- ============================================================
-- Organizer › Sheets: spreadsheets kept in the database.
-- org_sheets holds one workbook per row (the spreadsheet component's JSON snapshot).
-- Visibility: PRIVATE (owner only) or SHARED (every staff user of the tenant with Sheets access).
-- Anyone who can see a sheet and has Sheets write access may edit it; only the owner may rename it, change its
-- visibility or delete it. version increases on every save so a stale save is refused instead of overwriting.
-- New access area organizer.sheets (granted to the system Company Administrator role through fnd_tenant_access_seed).
-- Then load: database/functions/org_sheets_get.sql, org_sheet_get.sql, org_sheet_save.sql, org_sheet_delete.sql,
--            org_sheet_bps_eval.sql
-- ============================================================

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('organizer.sheets', 'Organizer', 'Sheets', 'TENANT', 700)
ON CONFLICT (area_key) DO NOTHING;

DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

CREATE TABLE IF NOT EXISTS bps.org_sheets (
  sheet_id      bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id     bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  owner_user_id bigint NOT NULL REFERENCES bps.fnd_users(user_id),
  sheet_name    text   NOT NULL CONSTRAINT chk_org_sheets_name CHECK (btrim(sheet_name) <> '' AND length(sheet_name) <= 200),
  visibility    text   NOT NULL DEFAULT 'PRIVATE' CONSTRAINT chk_org_sheets_visibility CHECK (visibility IN ('PRIVATE', 'SHARED')),
  workbook      jsonb  NOT NULL,
  version       integer NOT NULL DEFAULT 1,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    bigint,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  updated_by    bigint
);
CREATE INDEX IF NOT EXISTS idx_org_sheets_tenant ON bps.org_sheets (tenant_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_org_sheets_owner  ON bps.org_sheets (owner_user_id);

ALTER TABLE bps.org_sheets ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON bps.org_sheets TO authenticated;

DROP POLICY IF EXISTS pol_org_sheets_read ON bps.org_sheets;
CREATE POLICY pol_org_sheets_read ON bps.org_sheets FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.sheets', 'R'))
    AND (visibility = 'SHARED' OR owner_user_id = (SELECT bps.fnd_current_user_id()))));

DROP POLICY IF EXISTS pol_org_sheets_insert ON bps.org_sheets;
CREATE POLICY pol_org_sheets_insert ON bps.org_sheets FOR INSERT TO authenticated WITH CHECK (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.sheets', 'W'))
    AND owner_user_id = (SELECT bps.fnd_current_user_id())));

DROP POLICY IF EXISTS pol_org_sheets_update ON bps.org_sheets;
CREATE POLICY pol_org_sheets_update ON bps.org_sheets FOR UPDATE TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.sheets', 'W'))
    AND (visibility = 'SHARED' OR owner_user_id = (SELECT bps.fnd_current_user_id()))))
  WITH CHECK ((SELECT bps.fnd_is_trusted()) OR tenant_id = (SELECT bps.fnd_active_tenant_id()));

DROP POLICY IF EXISTS pol_org_sheets_delete ON bps.org_sheets;
CREATE POLICY pol_org_sheets_delete ON bps.org_sheets FOR DELETE TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.sheets', 'W'))
    AND owner_user_id = (SELECT bps.fnd_current_user_id())));
