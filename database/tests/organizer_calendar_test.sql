-- ============================================================
-- SQL tests for Organizer › Calendar: starting calendars, view ranges, repeat expansion (daily / weekly / monthly /
-- yearly, until, count), changing and deleting one / following / all occurrences, private calendars, access,
-- validation, search and the production-run overlay. One transaction, ROLLED BACK; local DB only:
--   docker exec -i supabase_db_bps-local psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < database/tests/organizer_calendar_test.sql
-- Assumes the Alpine Bakery migration: staff user 200000174045 (Company Administrator). Creates two staff users inside
-- the transaction: "zz cal two" (Company Administrator) and "zz cal none" (no role).
-- ============================================================
BEGIN;
SET search_path = bps, public;
CREATE TEMP TABLE _t (name text, ok boolean);
CREATE TEMP TABLE _v (k text PRIMARY KEY, v text);
GRANT ALL ON _t, _v TO PUBLIC;

DO $$
DECLARE t bigint := 200000000002; u2 bigint; u3 bigint;
BEGIN
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (t, 'aaaaaaaa-0000-4000-8000-0000000000c2', 'zz cal two', 'TENANCY_USER') RETURNING user_id INTO u2;
  INSERT INTO fnd_users (tenant_id, auth_user_id, user_name, user_type) VALUES (t, 'aaaaaaaa-0000-4000-8000-0000000000c3', 'zz cal none', 'TENANCY_USER') RETURNING user_id INTO u3;
  INSERT INTO fnd_user_tenants (tenant_id, user_id) VALUES (t, u2), (t, u3);
  INSERT INTO fnd_user_roles (tenant_id, user_id, role_id)
  SELECT t, u2, role_id FROM fnd_roles WHERE tenant_id = t AND is_system AND role_name = 'Company Administrator';
  -- start from no calendars so the seed can be tested
  DELETE FROM org_calendars WHERE tenant_id = t;
END $$;

CREATE TEMP TABLE _as (k text PRIMARY KEY, auth uuid);
GRANT ALL ON _as TO PUBLIC;
INSERT INTO _as VALUES ('one', '9b9b43b7-5a4c-4cbd-b5f4-b0585cbc393b'), ('two', 'aaaaaaaa-0000-4000-8000-0000000000c2'),
                       ('none', 'aaaaaaaa-0000-4000-8000-0000000000c3');

-- helper: occurrence dates of an event in a range, as text
CREATE OR REPLACE FUNCTION pg_temp.occ(p_id bigint, p_from date, p_to date) RETURNS text LANGUAGE sql AS $$
  SELECT string_agg(to_char(d, 'MM-DD'), ',' ORDER BY d) FROM bps.org_events e, bps.org_event_occurrences(e, p_from, p_to) d WHERE e.event_id = p_id $$;

-- 1) admin: seed, view ranges, repeats, changes
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'one' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  t bigint := 200000000002; r jsonb; cal bigint; priv bigint; e bigint; e2 bigint; d boolean; v jsonb;
BEGIN
  r := bps.org_calendars_get(t);
  INSERT INTO _t VALUES ('first open adds the four starting calendars', jsonb_array_length(r -> 'calendars') = 4
     AND r -> 'calendars' -> 0 ->> 'calendar_name' = 'Company' AND (r ->> 'can_edit')::boolean);
  INSERT INTO _t VALUES ('today is in the company time zone', (r ->> 'today')::date = (now() AT TIME ZONE 'America/New_York')::date);
  r := bps.org_calendars_get(t);
  INSERT INTO _t VALUES ('opening again adds nothing', jsonb_array_length(r -> 'calendars') = 4);
  cal := (r -> 'calendars' -> 0 ->> 'calendar_id')::bigint;
  INSERT INTO _v VALUES ('cal', cal);

  -- view ranges
  v := bps.org_calendar_view_get(t, 'month', '2026-11-25');
  INSERT INTO _t VALUES ('month view: whole weeks Sun 11/01 to Sat 12/05, title November 2026',
     v ->> 'from' = '2026-11-01' AND v ->> 'to' = '2026-12-05' AND jsonb_array_length(v -> 'days') = 35 AND v ->> 'title' = 'November 2026'
     AND v ->> 'prev' = '2026-10-25' AND v ->> 'next' = '2026-12-25');
  v := bps.org_calendar_view_get(t, 'month', '2026-08-10');
  INSERT INTO _t VALUES ('month view: August 2026 needs six weeks', jsonb_array_length(v -> 'days') = 42 AND v ->> 'from' = '2026-07-26');
  v := bps.org_calendar_view_get(t, 'week', '2026-12-30');
  INSERT INTO _t VALUES ('week view across a year', v ->> 'from' = '2026-12-27' AND v ->> 'to' = '2027-01-02' AND v ->> 'title' = 'Dec 27, 2026 – Jan 2, 2027');
  v := bps.org_calendar_view_get(t, 'day', '2026-11-25');
  INSERT INTO _t VALUES ('day view title', v ->> 'title' = 'Wed, Nov 25, 2026' AND v ->> 'prev' = '2026-11-24');
  v := bps.org_calendar_view_get(t, 'mini', '2026-11-25');
  INSERT INTO _t VALUES ('mini view: days without events', jsonb_array_length(v -> 'events') = 0 AND jsonb_array_length(v -> 'days') = 35);

  -- weekly on Mon + Wed, every 2 weeks, 5 times
  e := (bps.org_event_save(t, jsonb_build_object('calendar_id', cal, 'title', 'Staff meeting', 'start_date', '2026-11-02',
          'start_time', '07:00', 'end_date', '2026-11-02', 'end_time', '08:00', 'repeat_freq', 'WEEKLY', 'repeat_interval', 2,
          'repeat_days', jsonb_build_array(1, 3), 'repeat_count', 5)) ->> 'event_id')::bigint;
  INSERT INTO _t VALUES ('weekly Mon+Wed every 2 weeks, 5 times', pg_temp.occ(e, '2026-11-01', '2027-03-01') = '11-02,11-04,11-16,11-18,11-30');
  -- monthly on the 31st skips short months; until
  e2 := (bps.org_event_save(t, jsonb_build_object('calendar_id', cal, 'title', 'Month end count', 'all_day', true,
          'start_date', '2026-10-31', 'repeat_freq', 'MONTHLY', 'repeat_until', '2027-05-31')) ->> 'event_id')::bigint;
  INSERT INTO _t VALUES ('monthly on the 31st skips short months, ends at until', pg_temp.occ(e2, '2026-10-01', '2027-12-31') = '10-31,12-31,01-31,03-31,05-31');
  e2 := (bps.org_event_save(t, jsonb_build_object('calendar_id', cal, 'title', 'Leap day', 'all_day', true,
          'start_date', '2028-02-29', 'repeat_freq', 'YEARLY')) ->> 'event_id')::bigint;
  INSERT INTO _t VALUES ('yearly on Feb 29 only in leap years', pg_temp.occ(e2, '2028-01-01', '2036-12-31') = '02-29,02-29,02-29');
  e2 := (bps.org_event_save(t, jsonb_build_object('calendar_id', cal, 'title', 'Oven clean', 'start_date', '2026-11-20',
          'start_time', '22:00', 'end_date', '2026-11-21', 'end_time', '02:00', 'repeat_freq', 'DAILY', 'repeat_interval', 3)) ->> 'event_id')::bigint;
  INSERT INTO _t VALUES ('every 3 days; an overnight occurrence shows on the day it ends', pg_temp.occ(e2, '2026-11-21', '2026-11-30') = '11-20,11-23,11-26,11-29');
  v := bps.org_calendar_view_get(t, 'day', '2026-11-23');
  INSERT INTO _t VALUES ('overnight time label shows both dates',
     EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'events') x WHERE x ->> 'title' = 'Oven clean' AND x ->> 'time_label' = '11/23 10:00 PM – 11/24 2:00 AM'));
  INSERT INTO _t VALUES ('a day view lists the occurrence with its time label',
     EXISTS (SELECT 1 FROM jsonb_array_elements(bps.org_calendar_view_get(t, 'day', '2026-11-16') -> 'events') x
              WHERE (x ->> 'event_id')::bigint = e AND x ->> 'time_label' = '7:00 – 8:00 AM' AND x ->> 'short_label' = '7am' AND (x ->> 'is_recurring')::boolean));
  INSERT INTO _t VALUES ('repeat label', bps.org_event_get(t, e) ->> 'repeat_label' = 'Every 2 weeks on Mon, Wed, 5 times');

  -- delete one occurrence, then this-and-following
  PERFORM bps.org_event_delete(t, e, 'ONE', '2026-11-04');
  INSERT INTO _t VALUES ('deleting one occurrence removes only that date', pg_temp.occ(e, '2026-11-01', '2027-03-01') = '11-02,11-16,11-18,11-30');
  PERFORM bps.org_event_delete(t, e, 'FOLLOWING', '2026-11-18');
  INSERT INTO _t VALUES ('deleting this and following ends the series', pg_temp.occ(e, '2026-11-01', '2027-03-01') = '11-02,11-16');

  -- change one occurrence of a weekly series
  e := (bps.org_event_save(t, jsonb_build_object('calendar_id', cal, 'title', 'Flour delivery', 'start_date', '2026-11-04',
          'start_time', '10:00', 'end_date', '2026-11-04', 'end_time', '11:00', 'repeat_freq', 'WEEKLY')) ->> 'event_id')::bigint;
  e2 := (bps.org_event_save(t, jsonb_build_object('event_id', e, 'scope', 'ONE', 'occurrence_date', '2026-11-25', 'calendar_id', cal,
          'title', 'Flour delivery (early)', 'start_date', '2026-11-24', 'start_time', '09:00', 'end_date', '2026-11-24', 'end_time', '10:00',
          'repeat_freq', 'WEEKLY')) ->> 'event_id')::bigint;
  INSERT INTO _t VALUES ('changing one occurrence makes it a separate, non-repeating event',
     e2 <> e AND pg_temp.occ(e, '2026-11-15', '2026-12-05') = '11-18,12-02' AND pg_temp.occ(e2, '2026-11-01', '2026-12-31') = '11-24'
     AND bps.org_event_get(t, e2) ->> 'repeat_freq' = 'NONE');
  -- change all, moving the opened occurrence one day later moves the series
  PERFORM bps.org_event_save(t, jsonb_build_object('event_id', e, 'scope', 'ALL', 'occurrence_date', '2026-12-02', 'calendar_id', cal,
          'title', 'Flour delivery', 'start_date', '2026-12-03', 'start_time', '10:00', 'end_date', '2026-12-03', 'end_time', '11:30',
          'repeat_freq', 'WEEKLY', 'repeat_days', jsonb_build_array(4)));
  INSERT INTO _t VALUES ('changing all moves the series start by the same days', (SELECT start_date FROM org_events WHERE event_id = e) = '2026-11-05'
     AND pg_temp.occ(e, '2026-11-01', '2026-11-30') = '11-05,11-12,11-19,11-26');
  -- change this and following
  e2 := (bps.org_event_save(t, jsonb_build_object('event_id', e, 'scope', 'FOLLOWING', 'occurrence_date', '2026-11-19', 'calendar_id', cal,
          'title', 'Flour delivery (new supplier)', 'start_date', '2026-11-19', 'start_time', '08:00', 'end_date', '2026-11-19', 'end_time', '09:00',
          'repeat_freq', 'WEEKLY', 'repeat_days', jsonb_build_array(4))) ->> 'event_id')::bigint;
  INSERT INTO _t VALUES ('changing this and following splits the series',
     pg_temp.occ(e, '2026-11-01', '2026-12-31') = '11-05,11-12' AND pg_temp.occ(e2, '2026-11-01', '2026-12-10') = '11-19,11-26,12-03,12-10');
  BEGIN PERFORM bps.org_event_save(t, jsonb_build_object('event_id', e2, 'scope', 'ONE', 'occurrence_date', '2026-11-20', 'calendar_id', cal,
          'title', 'x', 'all_day', true, 'start_date', '2026-11-20')); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'That date is not part%'; END;
  INSERT INTO _t VALUES ('a date outside the series is refused', d);

  -- search
  v := bps.org_calendar_view_get(t, 'month', NULL, 'flour SUPPLIER');
  INSERT INTO _t VALUES ('search matches every word, ignoring case', v ->> 'view' = 'search'
     AND (SELECT bool_and(x ->> 'title' = 'Flour delivery (new supplier)') FROM jsonb_array_elements(v -> 'events') x)
     AND jsonb_array_length(v -> 'events') > 0);
  -- calendar filter and production overlay
  INSERT INTO _t VALUES ('a hidden calendar is left out',
     jsonb_array_length(bps.org_calendar_view_get(t, 'week', '2026-11-25', NULL, ARRAY[-1]::bigint[], false) -> 'events') = 0);
  v := bps.org_calendar_view_get(t, 'month', '2026-11-25');
  INSERT INTO _t VALUES ('production runs show on their production and delivery dates',
     (SELECT count(*) FROM jsonb_array_elements(v -> 'events') x WHERE x ->> 'kind' IN ('PRODUCTION', 'DELIVERY'))
       = (SELECT count(*) FROM om_production_runs WHERE tenant_id = t AND production_date BETWEEN '2026-11-01' AND '2026-12-05')
       + (SELECT count(*) FROM om_production_runs WHERE tenant_id = t AND delivery_date BETWEEN '2026-11-01' AND '2026-12-05'));
  INSERT INTO _t VALUES ('production overlay can be turned off',
     NOT EXISTS (SELECT 1 FROM jsonb_array_elements(bps.org_calendar_view_get(t, 'month', '2026-11-25', NULL, NULL, false) -> 'events') x
                  WHERE x ->> 'kind' <> 'EVENT'));

  -- validation
  BEGIN PERFORM bps.org_event_save(t, jsonb_build_object('calendar_id', cal, 'title', ' ', 'all_day', true, 'start_date', '2026-11-20')); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM = 'Give the event a title'; END;
  INSERT INTO _t VALUES ('a blank title is refused', d);
  BEGIN PERFORM bps.org_event_save(t, jsonb_build_object('calendar_id', cal, 'title', 'x', 'start_date', '2026-11-20', 'start_time', '10:00',
          'end_date', '2026-11-20', 'end_time', '09:00')); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM = 'The event ends before it starts'; END;
  INSERT INTO _t VALUES ('an end before the start is refused', d);
  BEGIN PERFORM bps.org_event_save(t, jsonb_build_object('calendar_id', cal, 'title', 'x', 'start_date', '2026-11-20')); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'Give the event a start and end time%'; END;
  INSERT INTO _t VALUES ('a timed event without times is refused', d);
  BEGIN PERFORM bps.org_event_save(t, jsonb_build_object('title', 'x', 'all_day', true, 'start_date', '2026-11-20')); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM = 'Pick a calendar'; END;
  INSERT INTO _t VALUES ('an event needs a calendar', d);
  BEGIN PERFORM bps.org_calendar_save(t, jsonb_build_object('calendar_name', 'staff')); d := false;
  EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'A calendar named%'; END;
  INSERT INTO _t VALUES ('calendar names are unique ignoring case', d);

  -- private calendar
  priv := (bps.org_calendar_save(t, jsonb_build_object('calendar_name', 'My notes', 'calendar_color', 'amber', 'visibility', 'private')) ->> 'calendar_id')::bigint;
  PERFORM bps.org_event_save(t, jsonb_build_object('calendar_id', priv, 'title', 'Dentist', 'start_date', '2026-11-27', 'start_time', '15:00',
          'end_date', '2026-11-27', 'end_time', '16:00'));
  INSERT INTO _v VALUES ('priv', priv);
  INSERT INTO _t VALUES ('the owner sees their private calendar', EXISTS (SELECT 1 FROM jsonb_array_elements(bps.org_calendars_get(t) -> 'calendars') x
                                                                          WHERE (x ->> 'calendar_id')::bigint = priv AND (x ->> 'is_owner')::boolean));
END $$;

-- 2) another staff user: shared calendars yes, private no
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'two' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE t bigint := 200000000002; priv bigint := (SELECT v FROM _v WHERE k = 'priv'); cal bigint := (SELECT v FROM _v WHERE k = 'cal'); d boolean; v jsonb;
BEGIN
  INSERT INTO _t VALUES ('another user sees the shared calendars, not the private one',
     jsonb_array_length(bps.org_calendars_get(t) -> 'calendars') = 4
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(bps.org_calendars_get(t) -> 'calendars') x WHERE (x ->> 'calendar_id')::bigint = priv));
  v := bps.org_calendar_view_get(t, 'week', '2026-11-25');
  INSERT INTO _t VALUES ('another user sees shared events but not private ones',
     EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'events') x WHERE x ->> 'title' LIKE 'Flour delivery%')
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'events') x WHERE x ->> 'title' = 'Dentist'));
  BEGIN PERFORM bps.org_event_save(t, jsonb_build_object('calendar_id', priv, 'title', 'x', 'all_day', true, 'start_date', '2026-11-20')); d := false;
  EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('another user cannot add to a private calendar', d);
  INSERT INTO _t VALUES ('another user can add to a shared calendar',
     (bps.org_event_save(t, jsonb_build_object('calendar_id', cal, 'title', 'Two''s event', 'all_day', true, 'start_date', '2026-11-20')) ->> 'event_id') IS NOT NULL);
END $$;

-- 3) a staff user without Calendar access
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'none' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$
DECLARE t bigint := 200000000002; d boolean;
BEGIN
  BEGIN PERFORM bps.org_calendars_get(t); d := false; EXCEPTION WHEN OTHERS THEN d := SQLERRM LIKE 'You do not have access%'; END;
  INSERT INTO _t VALUES ('no Calendar access: cannot open the calendar', d);
  BEGIN PERFORM bps.org_calendar_view_get(t, 'month'); d := false; EXCEPTION WHEN OTHERS THEN d := true; END;
  INSERT INTO _t VALUES ('no Calendar access: no events', d);
  INSERT INTO _t VALUES ('no Calendar access: row security hides the tables', (SELECT count(*) FROM org_events) = 0 AND (SELECT count(*) FROM org_calendars) = 0);
END $$;

-- 4) admin deletes a calendar with its events
RESET ROLE;
SELECT set_config('request.jwt.claims', (bps.bps_access_token_hook(jsonb_build_object('user_id', auth,
  'claims', jsonb_build_object('role', 'authenticated', 'sub', auth, 'app_metadata', '{}'::jsonb))) -> 'claims')::text, true) FROM _as WHERE k = 'one' \g /dev/null
SET LOCAL ROLE authenticated;
DO $$ DECLARE t bigint := 200000000002; cal bigint := (SELECT v FROM _v WHERE k = 'cal'); r jsonb; BEGIN
  r := bps.org_calendar_delete(t, cal);
  INSERT INTO _t VALUES ('deleting a calendar deletes its events', (r ->> 'events_deleted')::int > 0
     AND NOT EXISTS (SELECT 1 FROM org_events WHERE calendar_id = cal));
END $$;

RESET ROLE;
SELECT CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name AS result FROM _t;
DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT ok OR ok IS NULL), count(*) INTO bad, total FROM _t;
  IF bad > 0 THEN RAISE EXCEPTION '% of % calendar tests failed', bad, total; END IF;
  RAISE NOTICE 'all % calendar tests passed', total;
END $$;
ROLLBACK;
