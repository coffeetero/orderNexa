-- ============================================================
-- fnd_users_get (Admin > Users / Customer Users)
-- Users of the tenancy with their roles, groups and customers, plus invite status:
--   is_user_admin: can manage users (see fnd_user_admin_ids);
--   status: ACTIVE (has signed in) | INVITED (invite sent, not accepted yet) | NOT_INVITED; invited_at.
-- Supersedes the version in migration/add_access_admin_functions.sql.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_users_get(p_tenant_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'user_id', u.user_id, 'user_name', u.user_name, 'email', u.email, 'user_type', u.user_type,
      'is_active', ut.is_active AND u.is_active,
      'invited_at', u.invited_at,
      'is_user_admin', u.user_id IN (SELECT bps.fnd_user_admin_ids(p_tenant_id)),
      'status', CASE WHEN bps.fnd_auth_user_signed_in(u.auth_user_id) THEN 'ACTIVE'
                     WHEN u.invited_at IS NOT NULL THEN 'INVITED' ELSE 'NOT_INVITED' END,
      'role_ids', COALESCE((SELECT jsonb_agg(ur.role_id ORDER BY ur.role_id) FROM bps.fnd_user_roles ur WHERE ur.user_id = u.user_id AND ur.tenant_id = p_tenant_id), '[]'::jsonb),
      'group_ids', COALESCE((SELECT jsonb_agg(g.group_id ORDER BY g.group_id) FROM bps.fnd_user_customer_groups g WHERE g.user_id = u.user_id AND g.tenant_id = p_tenant_id), '[]'::jsonb),
      'customer_id', (SELECT uc.customer_id FROM bps.fnd_user_customers uc WHERE uc.user_id = u.user_id AND uc.tenant_id = p_tenant_id AND uc.is_active ORDER BY uc.user_customer_id LIMIT 1),
      'customers', COALESCE((SELECT jsonb_agg(c.customer_name ORDER BY c.customer_name) FROM bps.fnd_user_customers uc JOIN bps.fnd_customers c ON c.customer_id = uc.customer_id
                              WHERE uc.user_id = u.user_id AND uc.tenant_id = p_tenant_id AND uc.is_active), '[]'::jsonb))
    ORDER BY u.user_type, u.user_name), '[]'::jsonb)
  FROM bps.fnd_user_tenants ut JOIN bps.fnd_users u ON u.user_id = ut.user_id
  WHERE ut.tenant_id = p_tenant_id
$function$;
