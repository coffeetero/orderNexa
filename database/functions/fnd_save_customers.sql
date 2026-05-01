SET search_path TO bps, public;

DROP FUNCTION IF EXISTS set_customer(bigint, bigint, text, jsonb);

CREATE OR REPLACE FUNCTION fnd_save_customers(
  p_tenant_id bigint,
  p_customer_id bigint default null,
  p_action text default 'update',
  p_payload jsonb default '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
  v_jwt_raw text;
  v_claims jsonb;
  v_app_user_id bigint;
  v_user_id_from_auth bigint;
  v_is_authorized boolean;
  v_action text;
  v_customer_id bigint;
BEGIN
  -- Same pattern as fnd_get_tenants: read JWT from GUC so we never call auth.* (no USAGE on schema auth).
  v_jwt_raw := current_setting('request.jwt.claims', true);
  v_claims := COALESCE(NULLIF(v_jwt_raw, ''), '{}')::jsonb;

  v_app_user_id := nullif(v_claims -> 'app_metadata' ->> 'app_user_id', '')::bigint;

  IF nullif(trim(v_claims ->> 'sub'), '') IS NOT NULL THEN
    SELECT usr.user_id
      INTO v_user_id_from_auth
    FROM fnd_users usr
    WHERE usr.auth_user_id = (v_claims ->> 'sub')::uuid
      AND usr.is_active = true
    LIMIT 1;
  END IF;

  IF v_user_id_from_auth IS NOT NULL THEN
    v_app_user_id := v_user_id_from_auth;
  END IF;

  IF v_app_user_id IS NULL THEN
    RAISE EXCEPTION 'Missing app_user_id in JWT claims';
  END IF;

  SELECT EXISTS(
    SELECT 1
    FROM fnd_user_tenants usr_tnt
    WHERE usr_tnt.user_id = v_app_user_id
      AND usr_tnt.tenant_id = p_tenant_id
      AND usr_tnt.is_active = true
  )
    INTO v_is_authorized;

  IF NOT COALESCE(v_is_authorized, false) THEN
    RAISE EXCEPTION 'Tenant access denied for tenant_id %', p_tenant_id;
  END IF;

  v_action := lower(coalesce(trim(p_action), ''));

  IF v_action = 'create' THEN
    INSERT INTO fnd_customers (
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
    VALUES (
      p_tenant_id,
      CASE WHEN p_payload ? 'customer_parent_id' AND p_payload ->> 'customer_parent_id' <> '' THEN (p_payload ->> 'customer_parent_id')::bigint ELSE NULL END,
      coalesce(nullif(p_payload ->> 'customer_name', ''), 'New Customer'),
      nullif(p_payload ->> 'customer_number', ''),
      coalesce(nullif(p_payload ->> 'customer_type', ''), 'ACCOUNT'),
      CASE WHEN p_payload ? 'legacy_id' AND p_payload ->> 'legacy_id' <> '' THEN (p_payload ->> 'legacy_id')::int ELSE NULL END,
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
    RETURNING customer_id INTO v_customer_id;

    RETURN jsonb_build_object(
      'success', true,
      'action', 'create',
      'customer_id', v_customer_id,
      'message', 'Customer created'
    );
  ELSIF v_action = 'update' THEN
    IF p_customer_id IS NULL THEN
      RAISE EXCEPTION 'p_customer_id is required for update';
    END IF;

    UPDATE fnd_customers cus
    SET
      customer_parent_id = CASE WHEN p_payload ? 'customer_parent_id' THEN CASE WHEN p_payload ->> 'customer_parent_id' = '' THEN NULL ELSE (p_payload ->> 'customer_parent_id')::bigint END ELSE cus.customer_parent_id END,
      customer_name = CASE WHEN p_payload ? 'customer_name' THEN coalesce(nullif(p_payload ->> 'customer_name', ''), cus.customer_name) ELSE cus.customer_name END,
      customer_number = CASE WHEN p_payload ? 'customer_number' THEN nullif(p_payload ->> 'customer_number', '') ELSE cus.customer_number END,
      customer_type = CASE WHEN p_payload ? 'customer_type' THEN coalesce(nullif(p_payload ->> 'customer_type', ''), cus.customer_type) ELSE cus.customer_type END,
      legacy_id = CASE WHEN p_payload ? 'legacy_id' THEN CASE WHEN p_payload ->> 'legacy_id' = '' THEN NULL ELSE (p_payload ->> 'legacy_id')::int END ELSE cus.legacy_id END,
      invoice_copy_count = CASE WHEN p_payload ? 'invoice_copy_count' THEN greatest(coalesce((p_payload ->> 'invoice_copy_count')::int, cus.invoice_copy_count), 1) ELSE cus.invoice_copy_count END,
      is_standing_order = CASE WHEN p_payload ? 'is_standing_order' THEN (p_payload ->> 'is_standing_order')::boolean ELSE cus.is_standing_order END,
      is_signature_required = CASE WHEN p_payload ? 'is_signature_required' THEN (p_payload ->> 'is_signature_required')::boolean ELSE cus.is_signature_required END,
      is_active = CASE WHEN p_payload ? 'is_active' THEN (p_payload ->> 'is_active')::boolean ELSE cus.is_active END,
      is_label_required = CASE WHEN p_payload ? 'is_label_required' THEN (p_payload ->> 'is_label_required')::boolean ELSE cus.is_label_required END,
      is_invoice_required = CASE WHEN p_payload ? 'is_invoice_required' THEN (p_payload ->> 'is_invoice_required')::boolean ELSE cus.is_invoice_required END,
      is_cost_on_invoice = CASE WHEN p_payload ? 'is_cost_on_invoice' THEN (p_payload ->> 'is_cost_on_invoice')::boolean ELSE cus.is_cost_on_invoice END,
      is_cost_on_bill_of_lading = CASE WHEN p_payload ? 'is_cost_on_bill_of_lading' THEN (p_payload ->> 'is_cost_on_bill_of_lading')::boolean ELSE cus.is_cost_on_bill_of_lading END,
      is_returns_allowed = CASE WHEN p_payload ? 'is_returns_allowed' THEN (p_payload ->> 'is_returns_allowed')::boolean ELSE cus.is_returns_allowed END,
      updated_by = v_app_user_id
    WHERE cus.tenant_id = p_tenant_id
      AND cus.customer_id = p_customer_id
    RETURNING cus.customer_id INTO v_customer_id;

    IF v_customer_id IS NULL THEN
      RAISE EXCEPTION 'Customer % not found for tenant %', p_customer_id, p_tenant_id;
    END IF;

    RETURN jsonb_build_object(
      'success', true,
      'action', 'update',
      'customer_id', v_customer_id,
      'message', 'Customer updated'
    );
  ELSIF v_action = 'delete' THEN
    IF p_customer_id IS NULL THEN
      RAISE EXCEPTION 'p_customer_id is required for delete';
    END IF;

    DELETE FROM fnd_customers cus
    WHERE cus.tenant_id = p_tenant_id
      AND cus.customer_id = p_customer_id
    RETURNING cus.customer_id INTO v_customer_id;

    IF v_customer_id IS NULL THEN
      RAISE EXCEPTION 'Customer % not found for tenant %', p_customer_id, p_tenant_id;
    END IF;

    RETURN jsonb_build_object(
      'success', true,
      'action', 'delete',
      'customer_id', v_customer_id,
      'message', 'Customer deleted'
    );
  END IF;

  RAISE EXCEPTION 'Invalid action: %. Expected create, update, or delete.', p_action;
END;
$$;
