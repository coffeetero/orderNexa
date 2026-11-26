-- ============================================================
-- Organizer › Calendar: company and private calendars with events, simple repeats, and a read-only overlay of the
-- production runs (om_production_runs).
--
-- org_calendars          : a named, coloured calendar. SHARED = everyone at the company with Calendar access sees it;
--                          PRIVATE = only its owner. An event is private by being on a private calendar.
-- org_events             : an event (or a repeating series). Dates and times are wall-clock in the company's time zone
--                          (fnd_tenant_time_zone), so "every Monday 7:00 AM" stays 7:00 AM across daylight saving.
--                          All-day: start_date..end_date inclusive, no times. Timed: start_date + start_time to
--                          end_date + end_time (end_date may be the next day for a night shift).
--                          Repeat: repeat_freq DAILY / WEEKLY (repeat_days = ISO weekdays 1 Mon .. 7 Sun) / MONTHLY
--                          (same day of month; months without that day are skipped) / YEARLY, every repeat_interval,
--                          ending at repeat_until or after repeat_count occurrences (or never).
-- org_event_exceptions   : occurrences of a series that were removed ("delete this event" / edited separately).
-- Occurrences are expanded in the database for the visible range only (org_event_occurrences).
-- New access area organizer.calendar (granted to the system Company Administrator role through fnd_tenant_access_seed).
-- Every existing tenant gets four shared calendars: Company, Deliveries & catering, Staff, Closed & holidays.
-- Then load: database/functions/org_calendar_check.sql, org_event_occurrences.sql, org_calendar_seed.sql,
--            org_calendars_get.sql, org_calendar_save.sql, org_calendar_delete.sql, org_calendar_view_get.sql,
--            org_event_get.sql, org_event_save.sql, org_event_delete.sql
-- and run the seed block at the end of this file again after loading them.
-- ============================================================

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('organizer.calendar', 'Organizer', 'Calendar', 'TENANT', 720)
ON CONFLICT (area_key) DO NOTHING;

DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

-- ── org_calendars ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bps.org_calendars (
  calendar_id    bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id      bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  calendar_name  text   NOT NULL CONSTRAINT chk_org_calendars_name CHECK (btrim(calendar_name) <> '' AND length(calendar_name) <= 60),
  calendar_color text   NOT NULL DEFAULT 'accent'
                 CONSTRAINT chk_org_calendars_color CHECK (calendar_color IN ('accent', 'blue', 'green', 'amber', 'red', 'gray')),
  visibility     text   NOT NULL DEFAULT 'SHARED' CONSTRAINT chk_org_calendars_visibility CHECK (visibility IN ('SHARED', 'PRIVATE')),
  owner_user_id  bigint REFERENCES bps.fnd_users(user_id) ON DELETE CASCADE,
  display_order  integer NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     bigint,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  updated_by     bigint,
  CONSTRAINT chk_org_calendars_private_owner CHECK (visibility = 'SHARED' OR owner_user_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_org_calendars_tenant ON bps.org_calendars (tenant_id, display_order);
CREATE INDEX IF NOT EXISTS idx_org_calendars_owner  ON bps.org_calendars (owner_user_id);
COMMENT ON TABLE bps.org_calendars IS 'Organizer › Calendar: named, coloured calendars. SHARED = whole company (with Calendar access); PRIVATE = owner only.';
COMMENT ON COLUMN bps.org_calendars.calendar_color IS 'Theme colour key: accent, blue (info), green (success), amber (warning), red (destructive), gray (muted).';

-- ── org_events ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bps.org_events (
  event_id        bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id       bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  calendar_id     bigint NOT NULL REFERENCES bps.org_calendars(calendar_id) ON DELETE CASCADE,
  title           text   NOT NULL CONSTRAINT chk_org_events_title CHECK (btrim(title) <> '' AND length(title) <= 200),
  location        text   CONSTRAINT chk_org_events_location CHECK (length(location) <= 200),
  notes           text   CONSTRAINT chk_org_events_notes CHECK (length(notes) <= 4000),
  all_day         boolean NOT NULL DEFAULT false,
  start_date      date   NOT NULL,
  start_time      time,
  end_date        date   NOT NULL,
  end_time        time,
  repeat_freq     text   NOT NULL DEFAULT 'NONE'
                  CONSTRAINT chk_org_events_repeat_freq CHECK (repeat_freq IN ('NONE', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY')),
  repeat_interval smallint NOT NULL DEFAULT 1 CONSTRAINT chk_org_events_repeat_interval CHECK (repeat_interval BETWEEN 1 AND 99),
  repeat_days     smallint[] CONSTRAINT chk_org_events_repeat_days CHECK (repeat_days <@ ARRAY[1,2,3,4,5,6,7]::smallint[]),
  repeat_until    date,
  repeat_count    smallint CONSTRAINT chk_org_events_repeat_count CHECK (repeat_count BETWEEN 1 AND 999),
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      bigint,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      bigint,
  CONSTRAINT chk_org_events_times CHECK (
    (all_day AND start_time IS NULL AND end_time IS NULL AND end_date >= start_date)
    OR (NOT all_day AND start_time IS NOT NULL AND end_time IS NOT NULL
        AND (end_date > start_date OR (end_date = start_date AND end_time >= start_time)))),
  CONSTRAINT chk_org_events_span CHECK (end_date - start_date <= 366),
  CONSTRAINT chk_org_events_repeat_end CHECK (repeat_until IS NULL OR repeat_until >= start_date)
);
CREATE INDEX IF NOT EXISTS idx_org_events_calendar ON bps.org_events (calendar_id, start_date);
CREATE INDEX IF NOT EXISTS idx_org_events_tenant   ON bps.org_events (tenant_id, start_date);
COMMENT ON TABLE bps.org_events IS 'Organizer › Calendar events. Dates/times are wall-clock in the company time zone. repeat_* describe a series, expanded by org_event_occurrences.';
COMMENT ON COLUMN bps.org_events.repeat_days IS 'WEEKLY repeats: ISO weekdays (1 = Monday .. 7 = Sunday). NULL = the weekday of start_date.';

-- ── org_event_exceptions ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bps.org_event_exceptions (
  tenant_id       bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  event_id        bigint NOT NULL REFERENCES bps.org_events(event_id) ON DELETE CASCADE,
  occurrence_date date   NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      bigint,
  CONSTRAINT pk_org_event_exceptions PRIMARY KEY (event_id, occurrence_date)
);
COMMENT ON TABLE bps.org_event_exceptions IS 'Occurrences removed from a repeating event (deleted, or edited as a separate event).';

DROP TRIGGER IF EXISTS trg_org_calendars_set_updated ON bps.org_calendars;
CREATE TRIGGER trg_org_calendars_set_updated BEFORE UPDATE ON bps.org_calendars
  FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
DROP TRIGGER IF EXISTS trg_org_events_set_updated ON bps.org_events;
CREATE TRIGGER trg_org_events_set_updated BEFORE UPDATE ON bps.org_events
  FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();

-- ── Row security. A row is visible when its calendar is shared or owned by the caller. ──
ALTER TABLE bps.org_calendars        ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.org_events           ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.org_event_exceptions ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON bps.org_calendars, bps.org_events, bps.org_event_exceptions TO authenticated;

DROP POLICY IF EXISTS pol_org_calendars_read ON bps.org_calendars;
CREATE POLICY pol_org_calendars_read ON bps.org_calendars FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.calendar', 'R'))
    AND (visibility = 'SHARED' OR owner_user_id = (SELECT bps.fnd_current_user_id()))));
DROP POLICY IF EXISTS pol_org_calendars_write ON bps.org_calendars;
CREATE POLICY pol_org_calendars_write ON bps.org_calendars FOR ALL TO authenticated
  USING ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.calendar', 'W'))
    AND (visibility = 'SHARED' OR owner_user_id = (SELECT bps.fnd_current_user_id()))))
  WITH CHECK ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.calendar', 'W'))
    AND (visibility = 'SHARED' OR owner_user_id = (SELECT bps.fnd_current_user_id()))));

DROP POLICY IF EXISTS pol_org_events_read ON bps.org_events;
CREATE POLICY pol_org_events_read ON bps.org_events FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.calendar', 'R'))
    AND EXISTS (SELECT 1 FROM bps.org_calendars c WHERE c.calendar_id = org_events.calendar_id
                  AND (c.visibility = 'SHARED' OR c.owner_user_id = (SELECT bps.fnd_current_user_id())))));
DROP POLICY IF EXISTS pol_org_events_write ON bps.org_events;
CREATE POLICY pol_org_events_write ON bps.org_events FOR ALL TO authenticated
  USING ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.calendar', 'W'))
    AND EXISTS (SELECT 1 FROM bps.org_calendars c WHERE c.calendar_id = org_events.calendar_id
                  AND (c.visibility = 'SHARED' OR c.owner_user_id = (SELECT bps.fnd_current_user_id())))))
  WITH CHECK ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.calendar', 'W'))
    AND EXISTS (SELECT 1 FROM bps.org_calendars c WHERE c.calendar_id = org_events.calendar_id AND c.tenant_id = org_events.tenant_id
                  AND (c.visibility = 'SHARED' OR c.owner_user_id = (SELECT bps.fnd_current_user_id())))));

DROP POLICY IF EXISTS pol_org_event_exceptions_read ON bps.org_event_exceptions;
CREATE POLICY pol_org_event_exceptions_read ON bps.org_event_exceptions FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND EXISTS (SELECT 1 FROM bps.org_events e WHERE e.event_id = org_event_exceptions.event_id)));
DROP POLICY IF EXISTS pol_org_event_exceptions_write ON bps.org_event_exceptions;
CREATE POLICY pol_org_event_exceptions_write ON bps.org_event_exceptions FOR ALL TO authenticated
  USING ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.calendar', 'W'))
    AND EXISTS (SELECT 1 FROM bps.org_events e WHERE e.event_id = org_event_exceptions.event_id)))
  WITH CHECK ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access('organizer.calendar', 'W'))
    AND EXISTS (SELECT 1 FROM bps.org_events e WHERE e.event_id = org_event_exceptions.event_id AND e.tenant_id = org_event_exceptions.tenant_id)));

-- ── Default calendars for every tenant (needs org_calendar_seed loaded; harmless before) ──
DO $$ DECLARE t record; BEGIN
  IF to_regprocedure('bps.org_calendar_seed(bigint)') IS NOT NULL THEN
    FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.org_calendar_seed(t.tenant_id); END LOOP;
  END IF;
END $$;
