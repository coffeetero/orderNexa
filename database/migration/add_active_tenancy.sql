-- =====================================================================================
-- Access model, step (b): one active tenancy per auth session.
-- * bps_access_token_hook now adds app_metadata.tenant_id (+ tenant_slug) from fnd_user_active_tenant, keyed by the
--   auth session id. A user with exactly one tenancy is selected automatically; with two or more, no tenant_id is issued
--   until they pick one. The old allowed/restricted lists are still issued for the policies not yet rewritten (step c).
-- * fnd_user_tenancies_get()  lists the caller's tenancies for the picker.
-- * fnd_user_select_tenant()  records the choice for the caller's session (optionally checked against the host slug).
-- =====================================================================================
SET search_path = bps, public;

CREATE OR REPLACE FUNCTION bps.bps_access_token_hook(event jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'bps', 'public' AS $$
DECLARE
  claims jsonb := event->'claims';
  v_auth_user_id uuid := (event->>'user_id')::uuid;
  v_app_user_id bigint;
  v_allowed bigint[]; v_restricted bigint[]; v_customers bigint[];
  v_tenant bigint; v_slug text; v_session uuid;
BEGIN
  SELECT usr.user_id INTO v_app_user_id FROM fnd_users usr WHERE usr.auth_user_id = v_auth_user_id AND usr.is_active = true;

  IF v_app_user_id IS NULL THEN
    claims := jsonb_set(claims, '{app_metadata,app_user_id}', 'null'::jsonb, true);
    claims := jsonb_set(claims, '{app_metadata,allowed_tenant_ids}', '[]'::jsonb, true);
    claims := jsonb_set(claims, '{app_metadata,restricted_tenant_ids}', '[]'::jsonb, true);
    RETURN jsonb_set(event, '{claims}', claims, true);
  END IF;

  SELECT COALESCE(array_agg(ut.tenant_id ORDER BY ut.tenant_id), '{}') INTO v_allowed
    FROM fnd_user_tenants ut JOIN fnd_tenants t ON t.tenant_id = ut.tenant_id AND t.is_active
   WHERE ut.user_id = v_app_user_id AND ut.is_active = true;
  SELECT COALESCE(array_agg(ut.tenant_id ORDER BY ut.tenant_id), '{}') INTO v_restricted
    FROM fnd_user_tenants ut WHERE ut.user_id = v_app_user_id AND ut.is_active = true AND ut.is_customer_restricted = true;
  SELECT COALESCE(array_agg(uc.customer_id), '{}') INTO v_customers
    FROM fnd_user_customers uc WHERE uc.user_id = v_app_user_id AND uc.is_active = true;

  -- active tenancy: this session's recorded choice if still a valid membership, else the only tenancy, else none
  BEGIN v_session := NULLIF(claims->>'session_id', '')::uuid; EXCEPTION WHEN OTHERS THEN v_session := NULL; END;
  IF v_session IS NOT NULL THEN
    SELECT a.tenant_id INTO v_tenant FROM fnd_user_active_tenant a
     WHERE a.auth_session_id = v_session AND a.user_id = v_app_user_id AND a.tenant_id = ANY (v_allowed);
  END IF;
  IF v_tenant IS NULL AND cardinality(v_allowed) = 1 THEN v_tenant := v_allowed[1]; END IF;
  IF v_tenant IS NOT NULL THEN SELECT tenant_slug INTO v_slug FROM fnd_tenants WHERE tenant_id = v_tenant; END IF;

  claims := jsonb_set(claims, '{app_metadata,app_user_id}', to_jsonb(v_app_user_id), true);
  claims := jsonb_set(claims, '{app_metadata,allowed_tenant_ids}', to_jsonb(v_allowed), true);
  claims := jsonb_set(claims, '{app_metadata,restricted_tenant_ids}', to_jsonb(v_restricted), true);
  claims := jsonb_set(claims, '{app_metadata,allowed_customer_ids}', to_jsonb(v_customers), true);
  claims := jsonb_set(claims, '{app_metadata}', (claims->'app_metadata') - 'tenant_id' - 'tenant_slug', true);
  IF v_tenant IS NOT NULL THEN
    claims := jsonb_set(claims, '{app_metadata,tenant_id}', to_jsonb(v_tenant), true);
    claims := jsonb_set(claims, '{app_metadata,tenant_slug}', to_jsonb(v_slug), true);
  END IF;
  RETURN jsonb_set(event, '{claims}', claims, true);
END $$;

-- Tenancies of the signed-in user (works before a tenancy is selected: needs only app_user_id).
CREATE OR REPLACE FUNCTION bps.fnd_user_tenancies_get()
RETURNS TABLE (tenant_id bigint, tenant_name text, tenant_slug text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = bps, public AS $$
  SELECT t.tenant_id, t.tenant_name, t.tenant_slug
    FROM bps.fnd_user_tenants ut
    JOIN bps.fnd_users u ON u.user_id = ut.user_id AND u.is_active AND u.deleted_at IS NULL
    JOIN bps.fnd_tenants t ON t.tenant_id = ut.tenant_id AND t.is_active
   WHERE ut.user_id = bps.fnd_current_user_id() AND ut.is_active
   ORDER BY t.tenant_name
$$;

-- Records the caller's choice for THIS auth session. The browser then refreshes its session to receive the claim.
CREATE OR REPLACE FUNCTION bps.fnd_user_select_tenant(p_tenant_id bigint, p_host_slug text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = bps, public AS $$
DECLARE v_uid bigint := bps.fnd_current_user_id(); v_session uuid; v_slug text;
BEGIN
  BEGIN v_session := NULLIF(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id', '')::uuid;
  EXCEPTION WHEN OTHERS THEN v_session := NULL; END;
  IF v_uid IS NULL OR v_session IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  SELECT t.tenant_slug INTO v_slug FROM bps.fnd_user_tenants ut
    JOIN bps.fnd_users u ON u.user_id = ut.user_id AND u.is_active AND u.deleted_at IS NULL
    JOIN bps.fnd_tenants t ON t.tenant_id = ut.tenant_id AND t.is_active
   WHERE ut.user_id = v_uid AND ut.tenant_id = p_tenant_id AND ut.is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'You do not have access to that tenancy'; END IF;
  IF p_host_slug IS NOT NULL AND v_slug IS DISTINCT FROM p_host_slug THEN
    RAISE EXCEPTION 'This web address belongs to a different tenancy'; END IF;
  INSERT INTO bps.fnd_user_active_tenant (auth_session_id, user_id, tenant_id) VALUES (v_session, v_uid, p_tenant_id)
  ON CONFLICT (auth_session_id) DO UPDATE SET tenant_id = EXCLUDED.tenant_id, selected_at = now()
    WHERE bps.fnd_user_active_tenant.user_id = v_uid;
END $$;

REVOKE ALL ON FUNCTION bps.fnd_user_tenancies_get(), bps.fnd_user_select_tenant(bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_user_tenancies_get(), bps.fnd_user_select_tenant(bigint, text) TO authenticated;

-- The token hook runs as the function owner (bps_dev locally), which is subject to RLS on this table: let it read.
CREATE POLICY pol_fnd_user_active_tenant_hook ON bps.fnd_user_active_tenant FOR SELECT TO bps_dev USING (true);
