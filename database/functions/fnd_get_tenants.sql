CREATE OR REPLACE FUNCTION fnd_get_tenants()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
-- We remove 'auth' from here entirely. No looking at that schema!
SET search_path = bps, public 
AS $$
DECLARE
  v_ctx      record;
  v_result   jsonb;
  v_jwt_raw  text;
  v_claims   jsonb;
BEGIN
  -- 1. Grab the raw string. This is a GUC, not a schema object.
  v_jwt_raw := current_setting('request.jwt.claims', true);
  
  -- 2. Convert to JSONB.
  v_claims := COALESCE(NULLIF(v_jwt_raw, ''), '{}')::jsonb;

  -- 3. Resolve the user from the UUID string in the claims
  WITH resolved AS (
    SELECT 
      u.user_id,
      u.tenant_id AS primary_tenant_id,
      COALESCE(u.can_debug, false) AS can_debug,
      COALESCE(current_setting('request.method.query.debug', true) = 'true', false) AS debug_requested
    FROM fnd_users u
    WHERE u.auth_user_id = (v_claims ->> 'sub')::uuid
      AND u.is_active IS TRUE
    LIMIT 1
  )
  SELECT 
    *, 
    (can_debug AND debug_requested) AS is_debug 
  INTO v_ctx 
  FROM resolved;

  -- 4. Handshake Guard
  IF v_ctx.user_id IS NULL THEN
    RAISE EXCEPTION 'BPS_AUTH_ERROR: User sub % not found in fnd_users', (v_claims ->> 'sub');
  END IF;

  -- 5. Debug Logging (The whole point of today!)
  IF v_ctx.is_debug THEN
    RAISE NOTICE 'BPS_DEBUG: Handshake successful for user_id: %', v_ctx.user_id;
  END IF;

  -- 6. Fetch Tenants
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
  ) INTO v_result
  FROM fnd_user_tenants ut
  JOIN fnd_tenants tnt ON tnt.tenant_id = ut.tenant_id
  WHERE ut.user_id = v_ctx.user_id
    AND ut.is_active IS TRUE;

  IF v_ctx.is_debug THEN
    RAISE NOTICE 'BPS_DEBUG: Found % tenants.', jsonb_array_length(v_result);
  END IF;

  RETURN v_result;
END;
$$;