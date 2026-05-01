-- Resolves the current user from JWT GUCs only.
-- Unqualified object names resolve via search_path (bps first).
CREATE OR REPLACE FUNCTION fnd_get_tenants()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = bps, auth, public
AS $$
DECLARE
  v_ctx    record;
  v_result jsonb;
BEGIN
  /*
   * Context Resolve: Build user record including debug permission and request state.
   */
  WITH jwt AS (
    SELECT NULLIF(current_setting('request.jwt.claims', true), '')::jsonb AS claims
  ),
  resolved AS (
    SELECT 
      COALESCE(
        usr.user_id,
        NULLIF(j.claims -> 'app_metadata' ->> 'app_user_id', '')::bigint
      ) AS app_user_id,
      usr.tenant_id AS primary_tenant_id,
      usr.can_debug AS can_debug,
      COALESCE(current_setting('request.method.query.debug', true) = 'true', false) AS debug_requested
    FROM jwt j
    LEFT JOIN fnd_users usr
      ON usr.auth_user_id = NULLIF(j.claims ->> 'sub', '')::uuid
      AND usr.is_active IS TRUE
  )
  SELECT 
    *, 
    (can_debug AND debug_requested) AS is_debug 
  INTO v_ctx 
  FROM resolved;

  -- Security Check
  IF v_ctx.app_user_id IS NULL THEN
    RAISE EXCEPTION 'Missing app user context (app_metadata.app_user_id or JWT sub)';
  END IF;

  -- Debug Logging
  IF v_ctx.is_debug THEN
    RAISE NOTICE 'BPS_DEBUG: fnd_get_tenants started. User: %, Primary Tenant: %', 
      v_ctx.app_user_id, v_ctx.primary_tenant_id;
  END IF;

  -- Fetch associated tenants
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'tenant_id', tnt.tenant_id,
        'tenant_name', tnt.tenant_name,
        'is_primary', (tnt.tenant_id = v_ctx.primary_tenant_id)
      )
      ORDER BY tnt.tenant_name, tnt.tenant_id
    ),
    '[]'::jsonb
  )
    INTO v_result
  FROM fnd_user_tenants usr_tnt
  JOIN fnd_tenants tnt
    ON tnt.tenant_id = usr_tnt.tenant_id
  WHERE usr_tnt.user_id = v_ctx.app_user_id
    AND usr_tnt.is_active IS TRUE;

  IF v_ctx.is_debug THEN
    RAISE NOTICE 'BPS_DEBUG: fnd_get_tenants complete. Records found: %', jsonb_array_length(v_result);
  END IF;

  RETURN v_result;
END;
$$;