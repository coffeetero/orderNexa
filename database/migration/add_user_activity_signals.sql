-- ============================================================
-- User activity and security signals.
-- Records who uses BPS, when, and from which approximate place, and asks Company Administrators about two things on the
-- Dashboard To-Do list:
--   INACTIVE_USER  a staff member has not used BPS for N working days (Mon-Fri; N in Admin > Security, default 3):
--                  is she still with the company?  Deactivate account | Still with us (hides it for 14 days or until active)
--   NEW_LOCATION   a staff member used BPS from a city not seen for them in the previous 90 days (their first week builds
--                  their usual places without alerts):  Expected (that city becomes known) | Deactivate account
-- Nobody may clear a signal about themselves: signals about a person go to the OTHER user administrators; when someone is
-- the only one, their own signals still show to them, marked, and cannot be cleared (health check single_user_admin).
-- Activity of customer users is recorded too (seen in Admin > Customer Users); their signals come with the customer
-- portal's own Users screen (backlog).
--
-- New table fnd_user_access_log: one row per person, per day, per IP address (first/last seen, page count, approximate
--   city/region/country from the hosting provider), kept 180 days. acknowledged_at/by: who marked a new place Expected.
-- New column fnd_users.inactive_ok_until: set by "Still with us".
-- New column fnd_tenant_security_settings.inactive_alert_days (default 3 working days).
-- Load this first, then: functions/fnd_users_get.sql (Last activity on Admin > Users), functions/fnd_todos_get.sql (the signals on
-- the To-Do list), functions/fnd_hc_single_user_admin.sql (health check).
-- ============================================================
SET search_path = bps, public;

CREATE TABLE IF NOT EXISTS bps.fnd_user_access_log (
  access_log_id   bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id       bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  user_id         bigint NOT NULL REFERENCES bps.fnd_users(user_id) ON DELETE CASCADE,
  access_date     date   NOT NULL,
  ip_address      inet,
  city            text,
  region          text,
  country         text,
  user_agent      text,
  first_seen_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at    timestamptz NOT NULL DEFAULT now(),
  page_count      integer NOT NULL DEFAULT 1,
  acknowledged_at timestamptz,
  acknowledged_by bigint
);
COMMENT ON TABLE bps.fnd_user_access_log IS 'Who used BPS, when and from where (approximate): one row per person, day and IP address; kept 180 days. Written only by fnd_activity_record.';
CREATE UNIQUE INDEX IF NOT EXISTS uq_fnd_user_access_log_day ON bps.fnd_user_access_log (tenant_id, user_id, access_date, COALESCE(ip_address, '0.0.0.0'::inet));
CREATE INDEX IF NOT EXISTS idx_fnd_user_access_log_user ON bps.fnd_user_access_log (tenant_id, user_id, last_seen_at DESC);

ALTER TABLE bps.fnd_user_access_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_fnd_user_access_log_read ON bps.fnd_user_access_log;
CREATE POLICY pol_fnd_user_access_log_read ON bps.fnd_user_access_log FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id())
    AND (SELECT bps.fnd_has_access_any(ARRAY['admin.users', 'admin.customer-users'], 'R'))));
REVOKE ALL ON bps.fnd_user_access_log FROM PUBLIC, anon;
GRANT SELECT ON bps.fnd_user_access_log TO authenticated;
GRANT ALL ON bps.fnd_user_access_log TO service_role, bps_dev;

ALTER TABLE bps.fnd_users ADD COLUMN IF NOT EXISTS inactive_ok_until date;
COMMENT ON COLUMN bps.fnd_users.inactive_ok_until IS 'Set by "Still with us" on the inactivity To-Do: the question is not asked again until after this date (or until the person is active again).';

ALTER TABLE bps.fnd_tenant_security_settings ADD COLUMN IF NOT EXISTS inactive_alert_days integer NOT NULL DEFAULT 3;
ALTER TABLE bps.fnd_tenant_security_settings DROP CONSTRAINT IF EXISTS chk_fnd_tenant_security_settings_inactive_days;
ALTER TABLE bps.fnd_tenant_security_settings ADD CONSTRAINT chk_fnd_tenant_security_settings_inactive_days CHECK (inactive_alert_days BETWEEN 1 AND 60);
COMMENT ON COLUMN bps.fnd_tenant_security_settings.inactive_alert_days IS 'Working days (Mon-Fri) without using BPS before Company Administrators are asked whether a staff member is still with the company.';

-- ------------------------------------------------------------ security settings: get/save gain inactive_alert_days
CREATE OR REPLACE FUNCTION bps.fnd_security_settings_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE s bps.fnd_tenant_security_settings;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  SELECT * INTO s FROM bps.fnd_tenant_security_settings WHERE tenant_id = p_tenant_id;
  IF NOT FOUND THEN  -- defaults come from the column defaults
    s.idle_timeout_minutes := 30; s.min_password_length := 12; s.password_max_age_days := 90; s.password_history_count := 5; s.inactive_alert_days := 3;
  END IF;
  RETURN jsonb_build_object('idle_timeout_minutes', s.idle_timeout_minutes, 'min_password_length', s.min_password_length,
    'password_max_age_days', s.password_max_age_days, 'password_history_count', s.password_history_count,
    'inactive_alert_days', s.inactive_alert_days);
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_security_settings_save(p_tenant_id bigint, p_payload jsonb) RETURNS void
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE cur jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  cur := bps.fnd_security_settings_get(p_tenant_id) || COALESCE(p_payload, '{}'::jsonb);
  INSERT INTO bps.fnd_tenant_security_settings AS s (tenant_id, idle_timeout_minutes, min_password_length, password_max_age_days, password_history_count,
                                                    inactive_alert_days, updated_by)
  VALUES (p_tenant_id, (cur ->> 'idle_timeout_minutes')::int, (cur ->> 'min_password_length')::int,
          (cur ->> 'password_max_age_days')::int, (cur ->> 'password_history_count')::int, (cur ->> 'inactive_alert_days')::int, bps.fnd_current_user_id())
  ON CONFLICT (tenant_id) DO UPDATE SET idle_timeout_minutes = EXCLUDED.idle_timeout_minutes, min_password_length = EXCLUDED.min_password_length,
    password_max_age_days = EXCLUDED.password_max_age_days, password_history_count = EXCLUDED.password_history_count,
    inactive_alert_days = EXCLUDED.inactive_alert_days, updated_at = now(), updated_by = EXCLUDED.updated_by;
END $$;

-- ------------------------------------------------------------ recording activity
-- Called by the website at most every few minutes while someone uses it (staff and customer users alike). The IP address and
-- approximate place come from the request (the hosting provider's location headers); nothing is looked up elsewhere.
CREATE OR REPLACE FUNCTION bps.fnd_activity_record(p_tenant_id bigint, p_ip text, p_city text, p_region text, p_country text, p_user_agent text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_uid   bigint := bps.fnd_current_user_id();
  v_today date;
  v_ip    inet;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF v_uid IS NULL OR NOT EXISTS (SELECT 1 FROM bps.fnd_user_tenants ut WHERE ut.user_id = v_uid AND ut.tenant_id = p_tenant_id) THEN RETURN; END IF;
  v_today := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date;
  BEGIN v_ip := NULLIF(btrim(p_ip), '')::inet; EXCEPTION WHEN others THEN v_ip := NULL; END;
  INSERT INTO bps.fnd_user_access_log (tenant_id, user_id, access_date, ip_address, city, region, country, user_agent)
  VALUES (p_tenant_id, v_uid, v_today, v_ip, NULLIF(left(btrim(p_city), 100), ''), NULLIF(left(btrim(p_region), 100), ''),
          NULLIF(left(btrim(p_country), 10), ''), NULLIF(left(p_user_agent, 300), ''))
  ON CONFLICT (tenant_id, user_id, access_date, COALESCE(ip_address, '0.0.0.0'::inet))
  DO UPDATE SET last_seen_at = now(), page_count = bps.fnd_user_access_log.page_count + 1,
                city = COALESCE(EXCLUDED.city, bps.fnd_user_access_log.city), region = COALESCE(EXCLUDED.region, bps.fnd_user_access_log.region),
                country = COALESCE(EXCLUDED.country, bps.fnd_user_access_log.country), user_agent = COALESCE(EXCLUDED.user_agent, bps.fnd_user_access_log.user_agent);
  DELETE FROM bps.fnd_user_access_log WHERE user_id = v_uid AND tenant_id = p_tenant_id AND access_date < v_today - 180;
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_activity_record(bigint, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_activity_record(bigint, text, text, text, text, text) TO authenticated, service_role, bps_dev;

-- Working days (Mon-Fri) after p_from up to and including p_to.
CREATE OR REPLACE FUNCTION bps.fnd_working_days_between(p_from date, p_to date) RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
  SELECT COUNT(*)::int FROM generate_series(p_from + 1, p_to, interval '1 day') d WHERE extract(isodow FROM d) < 6
$$;

-- When each person of a company last used BPS: the latest of their access log, sign-in and page tracking.
CREATE OR REPLACE FUNCTION bps.fnd_user_last_activity(p_tenant_id bigint)
RETURNS TABLE(user_id bigint, last_active_at timestamptz, last_city text, last_region text, last_country text, last_ip text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
  SELECT u.user_id,
         NULLIF(GREATEST(COALESCE(l.last_seen_at, '-infinity'), COALESCE(a.last_sign_in_at, '-infinity'), COALESCE(m.used, '-infinity'), COALESCE(r.used, '-infinity')), '-infinity'),
         l.city, l.region, l.country, host(l.ip_address)
    FROM bps.fnd_user_tenants ut
    JOIN bps.fnd_users u ON u.user_id = ut.user_id
    LEFT JOIN auth.users a ON a.id = u.auth_user_id
    LEFT JOIN LATERAL (SELECT x.last_seen_at, x.city, x.region, x.country, x.ip_address FROM bps.fnd_user_access_log x
                        WHERE x.tenant_id = p_tenant_id AND x.user_id = u.user_id ORDER BY x.last_seen_at DESC LIMIT 1) l ON true
    LEFT JOIN LATERAL (SELECT max(ma.last_used_at) AS used FROM bps.fnd_user_menu_actions ma WHERE ma.user_id = u.user_id) m ON true
    LEFT JOIN LATERAL (SELECT max(rr.last_accessed_at) AS used FROM bps.fnd_user_recent_records rr WHERE rr.user_id = u.user_id) r ON true
   WHERE ut.tenant_id = p_tenant_id
     AND (bps.fnd_is_trusted() OR (p_tenant_id = bps.fnd_active_tenant_id() AND bps.fnd_has_access_any(ARRAY['admin.users', 'admin.customer-users'], 'R')))
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_user_last_activity(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_user_last_activity(bigint) TO authenticated, service_role, bps_dev;

-- ------------------------------------------------------------ the signals
-- For the caller, if they are a user administrator (admin.users write). Signals about the caller are left out when another
-- user administrator exists; otherwise they are included with "self": true and cannot be cleared.
CREATE OR REPLACE FUNCTION bps.fnd_security_signals_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me     bigint := bps.fnd_current_user_id();
  v_today  date;
  v_days   integer;
  v_others boolean;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_is_trusted() AND NOT bps.fnd_has_access('admin.users', 'W') THEN RETURN '[]'::jsonb; END IF;
  v_today := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date;
  v_days := COALESCE((SELECT s.inactive_alert_days FROM bps.fnd_tenant_security_settings s WHERE s.tenant_id = p_tenant_id), 3);
  v_others := EXISTS (SELECT 1 FROM bps.fnd_user_admin_ids(p_tenant_id) a WHERE a <> v_me);

  RETURN COALESCE((
    WITH staff AS (
      SELECT u.user_id, u.user_name, u.email, u.inactive_ok_until, u.auth_user_id
        FROM bps.fnd_user_tenants ut JOIN bps.fnd_users u ON u.user_id = ut.user_id
       WHERE ut.tenant_id = p_tenant_id AND ut.is_active AND u.is_active AND u.deleted_at IS NULL AND u.user_type = 'TENANCY_USER'
         AND (u.user_id <> v_me OR NOT v_others)
    ), act AS (
      SELECT s.*, la.last_active_at, la.last_city, la.last_region, la.last_country
        FROM staff s JOIN bps.fnd_user_last_activity(p_tenant_id) la ON la.user_id = s.user_id
       WHERE la.last_active_at IS NOT NULL      -- never signed in: the invite status on Admin > Users covers it
    ), inactive AS (
      SELECT jsonb_build_object('kind', 'INACTIVE_USER', 'user_id', a.user_id, 'user_name', COALESCE(a.user_name, a.email), 'email', a.email,
               'last_active_at', a.last_active_at,
               'working_days', bps.fnd_working_days_between((a.last_active_at AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date, v_today),
               'self', a.user_id = v_me) AS j, a.last_active_at AS sort_at
        FROM act a
       WHERE bps.fnd_working_days_between((a.last_active_at AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date, v_today) >= v_days
         AND (a.inactive_ok_until IS NULL OR a.inactive_ok_until < v_today)
    ), places AS (
      -- the first day each person used each place; a place is new when it was not used in the 90 days before and the person
      -- had already been active for a week (their first week builds their usual places)
      SELECT l.user_id, l.city, l.region, l.country, min(l.access_date) AS first_day, min(l.first_seen_at) AS first_at,
             bool_and(l.acknowledged_at IS NULL) AS unacknowledged,
             (array_agg(host(l.ip_address) ORDER BY l.first_seen_at))[1] AS ip
        FROM bps.fnd_user_access_log l JOIN staff s ON s.user_id = l.user_id
       WHERE l.tenant_id = p_tenant_id AND l.city IS NOT NULL AND l.access_date > v_today - 14
       GROUP BY l.user_id, l.city, l.region, l.country
    ), new_places AS (
      SELECT jsonb_build_object('kind', 'NEW_LOCATION', 'user_id', p.user_id, 'user_name', COALESCE(s.user_name, s.email), 'email', s.email,
               'city', p.city, 'region', p.region, 'country', p.country, 'ip', p.ip, 'first_seen_at', p.first_at, 'self', p.user_id = v_me) AS j,
             p.first_at AS sort_at
        FROM places p JOIN staff s ON s.user_id = p.user_id
       WHERE p.unacknowledged
         AND EXISTS (SELECT 1 FROM bps.fnd_user_access_log e WHERE e.tenant_id = p_tenant_id AND e.user_id = p.user_id AND e.access_date <= p.first_day - 7)
         AND NOT EXISTS (SELECT 1 FROM bps.fnd_user_access_log e WHERE e.tenant_id = p_tenant_id AND e.user_id = p.user_id
                           AND e.city = p.city AND e.region IS NOT DISTINCT FROM p.region AND e.country IS NOT DISTINCT FROM p.country
                           AND e.access_date < p.first_day AND e.access_date >= p.first_day - 90)
    )
    , reuse AS (
      -- someone tried to add a user whose email belongs to staff here (fnd_security_events, migration/add_customer_user_admin.sql)
      SELECT jsonb_build_object('kind', 'EMAIL_REUSE', 'event_id', e.event_id, 'user_id', e.user_id, 'user_name', COALESCE(u.user_name, u.email),
               'email', u.email, 'customer_name', e.details ->> 'customer_name', 'attempted_by', e.details ->> 'attempted_by',
               'created_at', e.created_at, 'is_active_here', COALESCE(ut.is_active AND u.is_active, false), 'self', e.user_id = v_me) AS j,
             e.created_at AS sort_at
        FROM bps.fnd_security_events e
        JOIN bps.fnd_users u ON u.user_id = e.user_id
        LEFT JOIN bps.fnd_user_tenants ut ON ut.user_id = u.user_id AND ut.tenant_id = p_tenant_id
       WHERE e.tenant_id = p_tenant_id AND e.event_type = 'EMAIL_REUSE_ATTEMPT' AND e.resolved_at IS NULL
         AND (e.user_id <> v_me OR NOT v_others)
    )
    SELECT jsonb_agg(x.j ORDER BY x.sort_at) FROM (SELECT * FROM reuse UNION ALL SELECT * FROM inactive UNION ALL SELECT * FROM new_places) x), '[]'::jsonb);
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_security_signals_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_security_signals_get(bigint) TO authenticated, service_role, bps_dev;

-- ------------------------------------------------------------ acting on a signal
-- p_action: DEACTIVATE (any signal) | STILL_HERE (INACTIVE_USER, or EMAIL_REUSE with p_event_id: settles that event)
--           | EXPECTED (NEW_LOCATION: p_city/p_region/p_country)
-- Refused for one's own signals, for non-staff, and when it would leave nobody able to manage users. Releasing the email
-- after DEACTIVATE is fnd_user_release_email (the website retires the old sign-in).
DROP FUNCTION IF EXISTS bps.fnd_security_signal_act(bigint, bigint, text, text, text, text);
CREATE OR REPLACE FUNCTION bps.fnd_security_signal_act(p_tenant_id bigint, p_user_id bigint, p_action text,
                                                       p_city text DEFAULT NULL, p_region text DEFAULT NULL, p_country text DEFAULT NULL,
                                                       p_event_id bigint DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_me    bigint := bps.fnd_current_user_id();
  v_today date;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.users', 'W') THEN RAISE EXCEPTION 'Only user administrators can do this' USING ERRCODE = '42501'; END IF;
  IF p_user_id = v_me THEN RAISE EXCEPTION 'Ask another administrator: nobody can clear a signal about themselves' USING ERRCODE = '42501'; END IF;
  IF NOT EXISTS (SELECT 1 FROM bps.fnd_user_tenants ut JOIN bps.fnd_users u ON u.user_id = ut.user_id
                  WHERE ut.tenant_id = p_tenant_id AND ut.user_id = p_user_id AND u.user_type = 'TENANCY_USER') THEN
    RAISE EXCEPTION 'User not found in this company';
  END IF;
  v_today := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date;

  IF p_action = 'DEACTIVATE' THEN
    UPDATE bps.fnd_user_tenants SET is_active = false WHERE tenant_id = p_tenant_id AND user_id = p_user_id;
    PERFORM bps.fnd_assert_user_admin(p_tenant_id);
    UPDATE bps.fnd_security_events SET resolved_at = now(), resolved_by = v_me
     WHERE tenant_id = p_tenant_id AND user_id = p_user_id AND resolved_at IS NULL;
  ELSIF p_action = 'STILL_HERE' AND p_event_id IS NOT NULL THEN
    UPDATE bps.fnd_security_events SET resolved_at = now(), resolved_by = v_me
     WHERE event_id = p_event_id AND tenant_id = p_tenant_id AND user_id = p_user_id AND resolved_at IS NULL;
  ELSIF p_action = 'STILL_HERE' THEN
    UPDATE bps.fnd_users SET inactive_ok_until = v_today + 14 WHERE user_id = p_user_id;
  ELSIF p_action = 'EXPECTED' THEN
    IF btrim(COALESCE(p_city, '')) = '' THEN RAISE EXCEPTION 'The place is missing'; END IF;
  ELSE
    RAISE EXCEPTION 'Unknown action %', p_action;
  END IF;

  -- a decision about a place (or the person) settles its new-place signal
  IF p_action IN ('EXPECTED', 'DEACTIVATE') THEN
    UPDATE bps.fnd_user_access_log SET acknowledged_at = now(), acknowledged_by = v_me
     WHERE tenant_id = p_tenant_id AND user_id = p_user_id AND acknowledged_at IS NULL
       AND (p_action = 'DEACTIVATE' OR (city = p_city AND region IS NOT DISTINCT FROM p_region AND country IS NOT DISTINCT FROM p_country));
  END IF;
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_security_signal_act(bigint, bigint, text, text, text, text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_security_signal_act(bigint, bigint, text, text, text, text, bigint) TO authenticated, service_role, bps_dev;
