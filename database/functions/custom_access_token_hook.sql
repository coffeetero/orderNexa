-- ============================================================
-- custom_access_token_hook
-- Purpose:
--   Enriches Supabase JWT claims with app-specific access context:
--   - app_user_id
--   - allowed_tenant_ids
--   - restricted_tenant_ids
--
-- Called from:
--   Supabase Auth "Custom Access Token Hook" during token issuance/refresh.
--   Supabase passes the auth event payload to this function and uses the
--   returned event.claims as the final JWT claims.
-- ============================================================

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
  claims jsonb;
  v_auth_user_id uuid;
  v_app_user_id bigint;
  v_allowed_tenant_ids bigint[];
  v_restricted_tenant_ids bigint[];
begin
  -- existing claims from Supabase
  claims := event->'claims';

  -- auth.users.id from the incoming hook payload
  v_auth_user_id := (event->>'user_id')::uuid;

  -- derive internal app user_id
  select usr.user_id
    into v_app_user_id
  from public.fnd_users usr
  where usr.auth_user_id = v_auth_user_id
    and usr.is_active = true;

  -- no matching app user: still return a valid token with empty claims
  if v_app_user_id is null then
    claims := jsonb_set(claims, '{app_metadata,app_user_id}', 'null'::jsonb, true);
    claims := jsonb_set(claims, '{app_metadata,allowed_tenant_ids}', '[]'::jsonb, true);
    claims := jsonb_set(claims, '{app_metadata,restricted_tenant_ids}', '[]'::jsonb, true);

    event := jsonb_set(event, '{claims}', claims, true);
    return event;
  end if;

  -- all active tenants this user can access
  select coalesce(array_agg(usrTnt.tenant_id order by usrTnt.tenant_id), '{}'::bigint[])
    into v_allowed_tenant_ids
  from public.fnd_user_tenants usrTnt
  where usrTnt.user_id = v_app_user_id
    and usrTnt.is_active = true;

  -- subset of active tenants where customer restriction applies
  select coalesce(array_agg(usrTnt.tenant_id order by usrTnt.tenant_id), '{}'::bigint[])
    into v_restricted_tenant_ids
  from public.fnd_user_tenants usrTnt
  where usrTnt.user_id = v_app_user_id
    and usrTnt.is_active = true
    and usrTnt.is_customer_restricted = true;

  -- inject custom claims under app_metadata
  claims := jsonb_set(
    claims,
    '{app_metadata,app_user_id}',
    to_jsonb(v_app_user_id),
    true
  );

  claims := jsonb_set(
    claims,
    '{app_metadata,allowed_tenant_ids}',
    to_jsonb(v_allowed_tenant_ids),
    true
  );

  claims := jsonb_set(
    claims,
    '{app_metadata,restricted_tenant_ids}',
    to_jsonb(v_restricted_tenant_ids),
    true
  );

  -- write claims back to the event payload
  event := jsonb_set(event, '{claims}', claims, true);

  return event;
end;
$$;