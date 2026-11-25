-- ============================================================
-- fnd_user_last_activity (Admin > Users "Last activity", security signals)
-- When each person of a company last used BPS, and from which approximate place: the latest of their access log, sign-in
-- and page tracking.
-- Who sees what (decided 2026-11-25): a bakery's user administrators see this for their own STAFF. A customer's users'
-- activity, IP address and place belong to that customer: only the customer's own administrator (fnd_portal_can_manage)
-- sees them, and the bakery sees just name, email, role and status (second-level support). For a customer user the bakery
-- gets the row with empty activity.
-- Supersedes the version in migration/add_user_activity_signals.sql. No new table or column.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_user_last_activity(p_tenant_id bigint)
RETURNS TABLE(user_id bigint, last_active_at timestamptz, last_city text, last_region text, last_country text, last_ip text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
  WITH visible AS (
    SELECT u.user_id, u.auth_user_id,
           CASE WHEN bps.fnd_is_trusted() THEN true
                WHEN u.user_type = 'CUSTOMER_USER' THEN bps.fnd_portal_can_manage(p_tenant_id, u.user_id)
                ELSE bps.fnd_has_access_any(ARRAY['admin.users', 'admin.customer-users'], 'R') END AS can_see
      FROM bps.fnd_user_tenants ut
      JOIN bps.fnd_users u ON u.user_id = ut.user_id
     WHERE ut.tenant_id = p_tenant_id
       AND (bps.fnd_is_trusted() OR (p_tenant_id = bps.fnd_active_tenant_id()
            AND (bps.fnd_has_access_any(ARRAY['admin.users', 'admin.customer-users'], 'R') OR cardinality(bps.fnd_portal_admin_accounts()) > 0)))
  )
  SELECT v.user_id,
         CASE WHEN v.can_see THEN NULLIF(GREATEST(COALESCE(l.last_seen_at, '-infinity'), COALESCE(a.last_sign_in_at, '-infinity'),
                                                  COALESCE(m.used, '-infinity'), COALESCE(r.used, '-infinity')), '-infinity') END,
         CASE WHEN v.can_see THEN l.city END, CASE WHEN v.can_see THEN l.region END, CASE WHEN v.can_see THEN l.country END,
         CASE WHEN v.can_see THEN host(l.ip_address) END
    FROM visible v
    LEFT JOIN auth.users a ON a.id = v.auth_user_id
    LEFT JOIN LATERAL (SELECT x.last_seen_at, x.city, x.region, x.country, x.ip_address FROM bps.fnd_user_access_log x
                        WHERE x.tenant_id = p_tenant_id AND x.user_id = v.user_id ORDER BY x.last_seen_at DESC LIMIT 1) l ON v.can_see
    LEFT JOIN LATERAL (SELECT max(ma.last_used_at) AS used FROM bps.fnd_user_menu_actions ma WHERE ma.user_id = v.user_id) m ON v.can_see
    LEFT JOIN LATERAL (SELECT max(rr.last_accessed_at) AS used FROM bps.fnd_user_recent_records rr WHERE rr.user_id = v.user_id) r ON v.can_see
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_user_last_activity(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_user_last_activity(bigint) TO authenticated, service_role, bps_dev;

-- The access log's read rule follows the same line: the bakery's user administrators read their staff's rows; a customer
-- user's rows are readable only by that customer's own administrator.
DROP POLICY IF EXISTS pol_fnd_user_access_log_read ON bps.fnd_user_access_log;
CREATE POLICY pol_fnd_user_access_log_read ON bps.fnd_user_access_log FOR SELECT TO authenticated USING (
  (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (
    (EXISTS (SELECT 1 FROM bps.fnd_users u WHERE u.user_id = fnd_user_access_log.user_id AND u.user_type = 'TENANCY_USER')
       AND (SELECT bps.fnd_has_access_any(ARRAY['admin.users', 'admin.customer-users'], 'R')))
    OR bps.fnd_portal_can_manage(tenant_id, user_id))));
