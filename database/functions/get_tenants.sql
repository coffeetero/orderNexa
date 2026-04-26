create or replace function public.get_tenants()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_app_user_id bigint;
  v_user_id_from_auth bigint;
  v_result jsonb;
begin
  v_app_user_id := nullif(auth.jwt() -> 'app_metadata' ->> 'app_user_id', '')::bigint;

  if auth.uid() is not null then
    select usr.user_id
      into v_user_id_from_auth
    from public.fnd_users usr
    where usr.auth_user_id = auth.uid()
      and usr.is_active = true
    limit 1;
  end if;

  if v_user_id_from_auth is not null then
    v_app_user_id := v_user_id_from_auth;
  end if;

  if v_app_user_id is null then
    raise exception 'Missing app_user_id in JWT claims';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'tenant_id', tnt.tenant_id,
        'tenant_name', tnt.tenant_name
      )
      order by tnt.tenant_name, tnt.tenant_id
    ),
    '[]'::jsonb
  )
    into v_result
  from public.fnd_user_tenants usr_tnt
  join public.fnd_tenants tnt
    on tnt.tenant_id = usr_tnt.tenant_id
  where usr_tnt.user_id = v_app_user_id
    and usr_tnt.is_active = true;

  return v_result;
end;
$$;
