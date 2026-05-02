create or replace function public.get_customers_debug(p_tenant_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_jwt_app_user_id bigint;
  v_auth_uid uuid;
  v_resolved_user_id bigint;
  v_is_authorized boolean;
  v_membership_count integer;
  v_total_customers integer;
  v_root_like_customers integer;
  v_customers jsonb;
begin
  v_jwt_app_user_id := nullif(auth.jwt() -> 'app_metadata' ->> 'app_user_id', '')::bigint;
  v_auth_uid := auth.uid();

  if v_auth_uid is not null then
    select usr.user_id
      into v_resolved_user_id
    from public.fnd_users usr
    where usr.auth_user_id = v_auth_uid
      and usr.is_active = true
    limit 1;
  end if;

  if v_resolved_user_id is null then
    v_resolved_user_id := v_jwt_app_user_id;
  end if;

  select count(*)
    into v_membership_count
  from public.fnd_user_tenants usr_tnt
  where usr_tnt.user_id = v_resolved_user_id
    and usr_tnt.tenant_id = p_tenant_id
    and usr_tnt.is_active = true;

  v_is_authorized := v_membership_count > 0;

  select count(*)
    into v_total_customers
  from public.fnd_customers cus
  where cus.tenant_id = p_tenant_id;

  select count(*)
    into v_root_like_customers
  from public.fnd_customers cus
  where cus.tenant_id = p_tenant_id
    and (
      cus.customer_parent_id is null
      or not exists (
        select 1
        from public.fnd_customers parent
        where parent.tenant_id = p_tenant_id
          and parent.customer_id = cus.customer_parent_id
      )
    );

  if v_is_authorized then
    v_customers := bps.fnd_get_customers(
      p_tenant_id,
      null::bigint,
      true,
      true
    );
  else
    v_customers := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'jwt_app_user_id', v_jwt_app_user_id,
    'auth_uid', v_auth_uid,
    'resolved_user_id', v_resolved_user_id,
    'membership_count', v_membership_count,
    'is_authorized', v_is_authorized,
    'total_customers', v_total_customers,
    'root_like_customers', v_root_like_customers,
    'returned_count', coalesce(jsonb_array_length(v_customers), 0),
    'customers_preview', coalesce(
      (
        select jsonb_agg(item)
        from (
          select item
          from jsonb_array_elements(v_customers) as item
          limit 10
        ) preview
      ),
      '[]'::jsonb
    )
  );
end;
$$;
