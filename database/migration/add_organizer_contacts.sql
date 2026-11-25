-- ============================================================
-- Organizer › Contacts: one company-wide address book on the existing contact store.
--
-- Where a contact belongs (fnd_contacts.entity_id + source_table, unchanged):
--   company contact  : source_table = 'fnd_tenants',   entity_id = tenant_id   (not tied to a customer)
--   customer contact : source_table = 'fnd_customers', entity_id = customer_id (shown with a link to the customer)
-- Only contact_type = 'PERSON' rows appear in the address book; the ADDRESSES / OTHER_CONTACTS system rows stay
-- with the customer screens.
--
-- New, all nullable or defaulted so existing inserts (customer screens, migration scripts) keep working:
--   fnd_contacts: name_prefix, middle_name, name_suffix, nickname, company_name, is_favorite, photo_data,
--                 important_dates (birthday and other labelled dates), related_people
--   fnd_contact_tags      : the tenant's contact labels (name + colour)
--   fnd_contact_tag_links : which contact carries which label
-- Phones / emails / addresses / websites / social profiles stay in fnd_contact_points (existing types; social = OTHER
-- with the service as label). Timestamped notes use fnd_notes with source_table = 'fnd_contacts'.
-- New access area organizer.contacts (granted to the system Company Administrator role through fnd_tenant_access_seed).
-- Then load: database/functions/fnd_contact_display_name.sql, org_contact_json.sql, org_contact_check.sql,
--            org_contacts_get.sql, org_contact_get.sql, org_contact_save.sql, org_contact_delete.sql,
--            org_contact_favorite_set.sql, org_contact_tags_get.sql, org_contact_tag_save.sql, org_contact_tag_delete.sql,
--            org_contact_note_save.sql, org_contact_note_delete.sql, org_contact_match_keys.sql, org_contacts_export.sql,
--            org_contacts_import.sql, org_contact_duplicates_get.sql, org_contact_merge.sql
-- ============================================================

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('organizer.contacts', 'Organizer', 'Contacts', 'TENANT', 710)
ON CONFLICT (area_key) DO NOTHING;

DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

-- ── fnd_contacts: extra person fields ──────────────────────────────────────────
ALTER TABLE bps.fnd_contacts
  ADD COLUMN IF NOT EXISTS name_prefix     text,
  ADD COLUMN IF NOT EXISTS middle_name     text,
  ADD COLUMN IF NOT EXISTS name_suffix     text,
  ADD COLUMN IF NOT EXISTS nickname        text,
  ADD COLUMN IF NOT EXISTS company_name    text,
  ADD COLUMN IF NOT EXISTS is_favorite     boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS photo_data      text,
  ADD COLUMN IF NOT EXISTS important_dates jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS related_people  jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN bps.fnd_contacts.company_name    IS 'Organization the person works for (free text; customer contacts also link to their customer).';
COMMENT ON COLUMN bps.fnd_contacts.is_favorite     IS 'Shown under Favourites in Organizer › Contacts (company-wide).';
COMMENT ON COLUMN bps.fnd_contacts.photo_data      IS 'Small contact photo as a data:image/... URL (resized to 160px in the browser, max 200 kB).';
COMMENT ON COLUMN bps.fnd_contacts.important_dates IS 'Labelled dates: [{"label":"birthday","date":"1980-05-12" or "--05-12" (no year)}].';
COMMENT ON COLUMN bps.fnd_contacts.related_people  IS 'Related names: [{"label":"spouse","name":"Ann Smith"}].';

DO $$ BEGIN
  ALTER TABLE bps.fnd_contacts ADD CONSTRAINT chk_fnd_contacts_photo_data
    CHECK (photo_data IS NULL OR (photo_data LIKE 'data:image/%' AND length(photo_data) <= 200000));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE bps.fnd_contacts ADD CONSTRAINT chk_fnd_contacts_important_dates CHECK (jsonb_typeof(important_dates) = 'array');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE bps.fnd_contacts ADD CONSTRAINT chk_fnd_contacts_related_people CHECK (jsonb_typeof(related_people) = 'array');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Address book list: person contacts of a tenant.
CREATE INDEX IF NOT EXISTS idx_fnd_contacts_person ON bps.fnd_contacts (tenant_id) WHERE contact_type = 'PERSON' AND is_active;

-- ── fnd_contact_tags: labels ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bps.fnd_contact_tags (
  tag_id     bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id  bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  tag_name   text   NOT NULL CONSTRAINT chk_fnd_contact_tags_tag_name CHECK (btrim(tag_name) <> '' AND length(tag_name) <= 60),
  tag_color  text   NOT NULL DEFAULT 'gray'
             CONSTRAINT chk_fnd_contact_tags_tag_color CHECK (tag_color IN ('gray', 'red', 'orange', 'amber', 'green', 'teal', 'sky', 'blue', 'violet', 'pink')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by bigint
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_fnd_contact_tags_name ON bps.fnd_contact_tags (tenant_id, lower(tag_name));

-- ── fnd_contact_tag_links: contact ↔ label ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS bps.fnd_contact_tag_links (
  tenant_id  bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  contact_id bigint NOT NULL REFERENCES bps.fnd_contacts(contact_id) ON DELETE CASCADE,
  tag_id     bigint NOT NULL REFERENCES bps.fnd_contact_tags(tag_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by bigint,
  CONSTRAINT pk_fnd_contact_tag_links PRIMARY KEY (contact_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_fnd_contact_tag_links_tag ON bps.fnd_contact_tag_links (tenant_id, tag_id);

DROP TRIGGER IF EXISTS trg_fnd_contact_tags_set_updated ON bps.fnd_contact_tags;
CREATE TRIGGER trg_fnd_contact_tags_set_updated BEFORE UPDATE ON bps.fnd_contact_tags
  FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
DROP TRIGGER IF EXISTS trg_fnd_contact_tags_audit ON bps.fnd_contact_tags;
CREATE TRIGGER trg_fnd_contact_tags_audit AFTER INSERT OR DELETE OR UPDATE ON bps.fnd_contact_tags
  FOR EACH ROW EXECUTE FUNCTION bps.fn_audit_log('tag_id');

-- ── Row security (the Organizer functions are SECURITY DEFINER and check access themselves) ──
ALTER TABLE bps.fnd_contact_tags      ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_contact_tag_links ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON bps.fnd_contact_tags, bps.fnd_contact_tag_links TO authenticated;

DROP POLICY IF EXISTS pol_fnd_contact_tags_read ON bps.fnd_contact_tags;
CREATE POLICY pol_fnd_contact_tags_read ON bps.fnd_contact_tags FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('organizer.contacts', 'R'))));
DROP POLICY IF EXISTS pol_fnd_contact_tags_write ON bps.fnd_contact_tags;
CREATE POLICY pol_fnd_contact_tags_write ON bps.fnd_contact_tags FOR ALL TO authenticated
  USING ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('organizer.contacts', 'W'))))
  WITH CHECK ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('organizer.contacts', 'W'))));

DROP POLICY IF EXISTS pol_fnd_contact_tag_links_read ON bps.fnd_contact_tag_links;
CREATE POLICY pol_fnd_contact_tag_links_read ON bps.fnd_contact_tag_links FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('organizer.contacts', 'R'))));
DROP POLICY IF EXISTS pol_fnd_contact_tag_links_write ON bps.fnd_contact_tag_links;
CREATE POLICY pol_fnd_contact_tag_links_write ON bps.fnd_contact_tag_links FOR ALL TO authenticated
  USING ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('organizer.contacts', 'W'))))
  WITH CHECK ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('organizer.contacts', 'W'))));
