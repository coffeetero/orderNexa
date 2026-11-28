-- ============================================================
-- Geocoding queue for addresses (fnd_contact_points type ADDRESS). The lookup itself is done by the website's server
-- (/api/geocode/run, Google Geocoding API); the database only hands out addresses to look up and stores the answers.
-- An address is PENDING when added and again whenever its text changes (trigger fn_contact_point_geocode_status).
--
--   fnd_geocode_queue_get(tenant, limit, ids)  → [{ contact_point_id, address }]: PENDING addresses (or FAILED ones with
--                                                fewer than 3 attempts); with ids, only those. Oldest first.
--   fnd_geocode_save(tenant, results)          → number saved. results: [{ contact_point_id, status, latitude, longitude,
--                                                formatted_address, place_id }] with status OK, ZERO_RESULTS or FAILED.
-- Tenant staff only; SECURITY DEFINER because app users have no direct access to the contact tables.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_geocode_queue_get(p_tenant_id bigint, p_limit integer DEFAULT 50, p_ids bigint[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
    RAISE EXCEPTION 'Only tenant staff can look up addresses';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('contact_point_id', x.contact_point_id, 'address', x.value) ORDER BY x.contact_point_id)
      FROM (SELECT cp.contact_point_id, cp.value FROM fnd_contact_points cp
             WHERE cp.tenant_id = p_tenant_id AND cp.type = 'ADDRESS' AND cp.is_active AND btrim(COALESCE(cp.value, '')) <> ''
               AND (cp.geocode_status = 'PENDING' OR (cp.geocode_status = 'FAILED' AND COALESCE(cp.geocode_attempts, 0) < 3))
               AND (p_ids IS NULL OR cp.contact_point_id = ANY(p_ids))
             ORDER BY cp.contact_point_id
             LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)) x), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION bps.fnd_geocode_save(p_tenant_id bigint, p_results jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE r jsonb; n integer := 0; v_status text;
BEGIN
  IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
    RAISE EXCEPTION 'Only tenant staff can look up addresses';
  END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(COALESCE(p_results, '[]'::jsonb)) LOOP
    v_status := upper(COALESCE(r ->> 'status', 'FAILED'));
    IF v_status NOT IN ('OK', 'ZERO_RESULTS', 'FAILED') THEN v_status := 'FAILED'; END IF;
    UPDATE fnd_contact_points cp
       SET geocode_status    = v_status,
           geocode_attempts  = COALESCE(cp.geocode_attempts, 0) + 1,
           geocoded_at       = now(),
           latitude          = CASE WHEN v_status = 'OK' THEN (r ->> 'latitude')::numeric ELSE NULL END,
           longitude         = CASE WHEN v_status = 'OK' THEN (r ->> 'longitude')::numeric ELSE NULL END,
           formatted_address = CASE WHEN v_status = 'OK' THEN r ->> 'formatted_address' ELSE cp.formatted_address END,
           google_place_id   = CASE WHEN v_status = 'OK' THEN r ->> 'place_id' ELSE cp.google_place_id END
     WHERE cp.tenant_id = p_tenant_id AND cp.type = 'ADDRESS' AND cp.contact_point_id = (r ->> 'contact_point_id')::bigint;
    IF FOUND THEN n := n + 1; END IF;
  END LOOP;
  RETURN n;
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_geocode_queue_get(bigint, integer, bigint[]), bps.fnd_geocode_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_geocode_queue_get(bigint, integer, bigint[]), bps.fnd_geocode_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
