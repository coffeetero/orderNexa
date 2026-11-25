-- ============================================================
-- Inactive users stay visible to their company's user administrators.
-- fnd_user_in_active_tenant(user) means "a member of the company the session is working in" (the active tenant). It also
-- required the membership to be active, so once a user was deactivated (Admin > Users > Active in this company) even the
-- administrators could no longer read the user record: the person vanished from Admin > Users and could not be reviewed or
-- reactivated. Used only by the fnd_users read/update/delete rules, which also require admin.users (or portal.users within
-- the customer's scope). A deactivated person still has no access themselves: fnd_has_access requires an active membership.
-- No new table or column.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_user_in_active_tenant(p_user_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'bps', 'public'
AS $function$ SELECT EXISTS (SELECT 1 FROM bps.fnd_user_tenants ut WHERE ut.user_id = p_user_id AND ut.tenant_id = bps.fnd_active_tenant_id()) $function$;
