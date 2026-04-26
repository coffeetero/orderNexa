create or replace function public.set_customer(
  p_tenant_id bigint,
  p_customer_id bigint default null,
  p_action text default 'update',
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_app_user_id bigint;
  v_user_id_from_auth bigint;
  v_is_authorized boolean;
  v_action text;
  v_customer_id bigint;
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

  v_action := lower(coalesce(trim(p_action), ''));

  if v_action = 'create' then
    insert into public.fnd_customers (
      tenant_id,
      customer_parent_id,
      customer_name,
      customer_number,
      customer_type,
      legacy_id,
      invoice_copy_count,
      is_standing_order,
      is_signature_required,
      is_active,
      is_label_required,
      is_invoice_required,
      is_cost_on_invoice,
      is_cost_on_bill_of_lading,
      is_returns_allowed,
      created_by,
      updated_by
    )
    values (
      p_tenant_id,
      case when p_payload ? 'customer_parent_id' and p_payload ->> 'customer_parent_id' <> '' then (p_payload ->> 'customer_parent_id')::bigint else null end,
      coalesce(nullif(p_payload ->> 'customer_name', ''), 'New Customer'),
      nullif(p_payload ->> 'customer_number', ''),
      coalesce(nullif(p_payload ->> 'customer_type', ''), 'ACCOUNT'),
      case when p_payload ? 'legacy_id' and p_payload ->> 'legacy_id' <> '' then (p_payload ->> 'legacy_id')::int else null end,
      greatest(coalesce((p_payload ->> 'invoice_copy_count')::int, 1), 1),
      coalesce((p_payload ->> 'is_standing_order')::boolean, false),
      coalesce((p_payload ->> 'is_signature_required')::boolean, false),
      coalesce((p_payload ->> 'is_active')::boolean, true),
      coalesce((p_payload ->> 'is_label_required')::boolean, false),
      coalesce((p_payload ->> 'is_invoice_required')::boolean, false),
      coalesce((p_payload ->> 'is_cost_on_invoice')::boolean, false),
      coalesce((p_payload ->> 'is_cost_on_bill_of_lading')::boolean, false),
      coalesce((p_payload ->> 'is_returns_allowed')::boolean, true),
      v_app_user_id,
      v_app_user_id
    )
    returning customer_id into v_customer_id;

    return jsonb_build_object(
      'success', true,
      'action', 'create',
      'customer_id', v_customer_id,
      'message', 'Customer created'
    );
  elsif v_action = 'update' then
    if p_customer_id is null then
      raise exception 'p_customer_id is required for update';
    end if;

    update public.fnd_customers cus
    set
      customer_parent_id = case when p_payload ? 'customer_parent_id' then case when p_payload ->> 'customer_parent_id' = '' then null else (p_payload ->> 'customer_parent_id')::bigint end else cus.customer_parent_id end,
      customer_name = case when p_payload ? 'customer_name' then coalesce(nullif(p_payload ->> 'customer_name', ''), cus.customer_name) else cus.customer_name end,
      customer_number = case when p_payload ? 'customer_number' then nullif(p_payload ->> 'customer_number', '') else cus.customer_number end,
      customer_type = case when p_payload ? 'customer_type' then coalesce(nullif(p_payload ->> 'customer_type', ''), cus.customer_type) else cus.customer_type end,
      legacy_id = case when p_payload ? 'legacy_id' then case when p_payload ->> 'legacy_id' = '' then null else (p_payload ->> 'legacy_id')::int end else cus.legacy_id end,
      invoice_copy_count = case when p_payload ? 'invoice_copy_count' then greatest(coalesce((p_payload ->> 'invoice_copy_count')::int, cus.invoice_copy_count), 1) else cus.invoice_copy_count end,
      is_standing_order = case when p_payload ? 'is_standing_order' then (p_payload ->> 'is_standing_order')::boolean else cus.is_standing_order end,
      is_signature_required = case when p_payload ? 'is_signature_required' then (p_payload ->> 'is_signature_required')::boolean else cus.is_signature_required end,
      is_active = case when p_payload ? 'is_active' then (p_payload ->> 'is_active')::boolean else cus.is_active end,
      is_label_required = case when p_payload ? 'is_label_required' then (p_payload ->> 'is_label_required')::boolean else cus.is_label_required end,
      is_invoice_required = case when p_payload ? 'is_invoice_required' then (p_payload ->> 'is_invoice_required')::boolean else cus.is_invoice_required end,
      is_cost_on_invoice = case when p_payload ? 'is_cost_on_invoice' then (p_payload ->> 'is_cost_on_invoice')::boolean else cus.is_cost_on_invoice end,
      is_cost_on_bill_of_lading = case when p_payload ? 'is_cost_on_bill_of_lading' then (p_payload ->> 'is_cost_on_bill_of_lading')::boolean else cus.is_cost_on_bill_of_lading end,
      is_returns_allowed = case when p_payload ? 'is_returns_allowed' then (p_payload ->> 'is_returns_allowed')::boolean else cus.is_returns_allowed end,
      updated_by = v_app_user_id
    where cus.tenant_id = p_tenant_id
      and cus.customer_id = p_customer_id
    returning cus.customer_id into v_customer_id;

    if v_customer_id is null then
      raise exception 'Customer % not found for tenant %', p_customer_id, p_tenant_id;
    end if;

    return jsonb_build_object(
      'success', true,
      'action', 'update',
      'customer_id', v_customer_id,
      'message', 'Customer updated'
    );
  elsif v_action = 'delete' then
    if p_customer_id is null then
      raise exception 'p_customer_id is required for delete';
    end if;

    delete from public.fnd_customers cus
    where cus.tenant_id = p_tenant_id
      and cus.customer_id = p_customer_id
    returning cus.customer_id into v_customer_id;

    if v_customer_id is null then
      raise exception 'Customer % not found for tenant %', p_customer_id, p_tenant_id;
    end if;

    return jsonb_build_object(
      'success', true,
      'action', 'delete',
      'customer_id', v_customer_id,
      'message', 'Customer deleted'
    );
  end if;

  raise exception 'Invalid action: %. Expected create, update, or delete.', p_action;
end;
$$;
