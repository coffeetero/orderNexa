create or replace function public.get_customers(p_tenant_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_app_user_id bigint;
  v_user_id_from_auth bigint;
  v_is_authorized boolean;
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

  select exists(
    select 1
    from public.fnd_user_tenants usr_tnt
    where usr_tnt.user_id = v_app_user_id
      and usr_tnt.tenant_id = p_tenant_id
      and usr_tnt.is_active = true
  )
    into v_is_authorized;

  if not coalesce(v_is_authorized, false) then
    raise exception 'Tenant access denied for tenant_id %', p_tenant_id;
  end if;

  with recursive customer_tree as (
    select
      cus.customer_id,
      cus.tenant_id,
      cus.customer_parent_id,
      cus.customer_number,
      cus.customer_name,
      cus.customer_type,
      cus.legacy_id,
      cus.invoice_copy_count,
      cus.is_standing_order,
      cus.is_signature_required,
      cus.is_active,
      cus.is_label_required,
      cus.is_invoice_required,
      cus.is_cost_on_invoice,
      cus.is_cost_on_bill_of_lading,
      cus.is_returns_allowed,
      0::int as level,
      lpad(coalesce(cus.customer_number, cus.customer_id::text), 20, '0') as sort_path,
      array[cus.customer_id]::bigint[] as path_ids
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
      )

    union all

    select
      ch.customer_id,
      ch.tenant_id,
      ch.customer_parent_id,
      ch.customer_number,
      ch.customer_name,
      ch.customer_type,
      ch.legacy_id,
      ch.invoice_copy_count,
      ch.is_standing_order,
      ch.is_signature_required,
      ch.is_active,
      ch.is_label_required,
      ch.is_invoice_required,
      ch.is_cost_on_invoice,
      ch.is_cost_on_bill_of_lading,
      ch.is_returns_allowed,
      ct.level + 1,
      ct.sort_path || '.' || lpad(coalesce(ch.customer_number, ch.customer_id::text), 20, '0'),
      ct.path_ids || ch.customer_id
    from public.fnd_customers ch
    join customer_tree ct
      on ct.customer_id = ch.customer_parent_id
    where ch.tenant_id = p_tenant_id
      and not (ch.customer_id = any(ct.path_ids))
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'customer_id', customer_id,
        'tenant_id', tenant_id,
        'customer_parent_id', customer_parent_id,
        'customer_number', customer_number,
        'customer_name', customer_name,
        'customer_type', customer_type,
        'legacy_id', legacy_id,
        'invoice_copy_count', invoice_copy_count,
        'is_standing_order', is_standing_order,
        'is_signature_required', is_signature_required,
        'is_active', is_active,
        'is_label_required', is_label_required,
        'is_invoice_required', is_invoice_required,
        'is_cost_on_invoice', is_cost_on_invoice,
        'is_cost_on_bill_of_lading', is_cost_on_bill_of_lading,
        'is_returns_allowed', is_returns_allowed,
        'level', level,
        'sort_path', sort_path
      )
      order by sort_path
    ),
    '[]'::jsonb
  )
    into v_result
  from customer_tree;

  return v_result;
end;
$$;
