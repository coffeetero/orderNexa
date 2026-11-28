-- ============================================================
-- Google address verification for customer addresses. The website's server (/api/address/validate) sends each address
-- to the Google Address Validation API; the database hands out the addresses and decides what Google's answer means.
--
--   fnd_address_norm(text)                     → a line in a comparable form (upper case, no punctuation, USPS
--                                                abbreviations, ZIP+4 cut to the ZIP)
--   fnd_address_validation_queue_get(tenant, limit, ids) → [{contact_point_id, address}]: active customer addresses not
--                                                verified and not yet checked; with ids, only those
--   fnd_address_validation_save(tenant, results) → counts. results: [{contact_point_id, status 'OK'|'FAILED',
--                                                granularity, street, city_line, verdict}] where street is Google's
--                                                first address line and city_line its "City, ST ZIP" line.
-- An address is name or attention lines, then the street, then "City, ST ZIP" (delivery directions live in
-- instructions). Only the last two lines are sent to Google, compared and corrected; the name lines are kept:
--   VERIFIED     Google found the building and both lines match → is_verified
--   SUGGESTED    Google found it and corrects a line → suggested_address, waiting for staff
--   UNCONFIRMED  Google found only the street or area → suggested_address when it differs
--   NOT_FOUND    Google could not place it
-- Tenant staff only; SECURITY DEFINER because app users have no direct access to the contact tables.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_address_norm(p_line text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(
           (SELECT string_agg(CASE w
                    WHEN 'STREET' THEN 'ST' WHEN 'AVENUE' THEN 'AVE' WHEN 'AV' THEN 'AVE' WHEN 'BOULEVARD' THEN 'BLVD'
                    WHEN 'ROAD' THEN 'RD' WHEN 'DRIVE' THEN 'DR' WHEN 'PLACE' THEN 'PL' WHEN 'PARKWAY' THEN 'PKWY'
                    WHEN 'LANE' THEN 'LN' WHEN 'COURT' THEN 'CT' WHEN 'HIGHWAY' THEN 'HWY' WHEN 'TERRACE' THEN 'TER'
                    WHEN 'PLAZA' THEN 'PLZ' WHEN 'SQUARE' THEN 'SQ' WHEN 'TURNPIKE' THEN 'TPKE' WHEN 'EXPRESSWAY' THEN 'EXPY'
                    WHEN 'CIRCLE' THEN 'CIR' WHEN 'SUITE' THEN 'STE' WHEN 'FLOOR' THEN 'FL' WHEN 'APARTMENT' THEN 'APT'
                    WHEN 'BUILDING' THEN 'BLDG' WHEN 'ROOM' THEN 'RM' WHEN 'DEPARTMENT' THEN 'DEPT'
                    WHEN 'EAST' THEN 'E' WHEN 'WEST' THEN 'W' WHEN 'NORTH' THEN 'N' WHEN 'SOUTH' THEN 'S'
                    ELSE w END, ' ' ORDER BY n)
              FROM regexp_split_to_table(
                     regexp_replace(regexp_replace(upper(COALESCE(p_line, '')), '(\d{5})-\d{4}', '\1', 'g'), '[^A-Z0-9]+', ' ', 'g'),
                     '\s+') WITH ORDINALITY x(w, n)
             WHERE w <> ''),
           '\s+', ' ', 'g'));
$function$;

CREATE OR REPLACE FUNCTION bps.fnd_address_validation_queue_get(p_tenant_id bigint, p_limit integer DEFAULT 50, p_ids bigint[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN RAISE EXCEPTION 'Only tenant staff can verify addresses'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('contact_point_id', x.contact_point_id, 'address', x.value) ORDER BY x.contact_point_id)
      FROM (SELECT cp.contact_point_id, cp.value
              FROM fnd_contact_points cp JOIN fnd_contacts k ON k.contact_id = cp.contact_id AND k.tenant_id = cp.tenant_id
             WHERE cp.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.is_active
               AND cp.type = 'ADDRESS' AND cp.is_active AND btrim(COALESCE(cp.value, '')) <> ''
               AND NOT cp.is_verified AND cp.google_geocode_response -> 'validation' IS NULL
               AND (p_ids IS NULL OR cp.contact_point_id = ANY (p_ids))
             ORDER BY cp.contact_point_id
             LIMIT GREATEST(LEAST(COALESCE(p_limit, 50), 200), 1)) x), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION bps.fnd_address_validation_save(p_tenant_id bigint, p_results jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  r jsonb; v_pt fnd_contact_points; v_lines text[]; v_n int; v_street text; v_city text; v_gran text;
  v_suggest text; v_match boolean; v_status text; v_counts jsonb := '{"VERIFIED":0,"SUGGESTED":0,"UNCONFIRMED":0,"NOT_FOUND":0}';
BEGIN
  IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN RAISE EXCEPTION 'Only tenant staff can verify addresses'; END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(COALESCE(p_results, '[]'::jsonb)) LOOP
    CONTINUE WHEN upper(COALESCE(r ->> 'status', '')) <> 'OK';   -- a failed call leaves the address in the queue
    SELECT cp.* INTO v_pt FROM fnd_contact_points cp
     WHERE cp.tenant_id = p_tenant_id AND cp.contact_point_id = (r ->> 'contact_point_id')::bigint AND cp.type = 'ADDRESS' AND cp.is_active;
    CONTINUE WHEN NOT FOUND;
    v_lines  := ARRAY(SELECT btrim(l) FROM regexp_split_to_table(v_pt.value, '\n') WITH ORDINALITY x(l, n) WHERE btrim(l) <> '' ORDER BY n);
    v_n      := COALESCE(array_length(v_lines, 1), 0);
    v_street := NULLIF(btrim(r ->> 'street'), '');
    v_city   := NULLIF(btrim(r ->> 'city_line'), '');
    v_gran   := upper(COALESCE(r ->> 'granularity', ''));
    v_suggest := NULL;
    IF v_street IS NULL OR v_city IS NULL OR v_gran IN ('', 'OTHER', 'GRANULARITY_UNSPECIFIED') THEN
      v_status := 'NOT_FOUND';
    ELSE
      -- the typed name lines + Google's street + Google's city line
      v_suggest := array_to_string(COALESCE(v_lines[1:v_n - 2], '{}') || ARRAY[v_street, v_city], E'\n');
      v_match   := v_n >= 2 AND bps.fnd_address_norm(v_lines[v_n - 1]) = bps.fnd_address_norm(v_street)
                   AND bps.fnd_address_norm(v_lines[v_n]) = bps.fnd_address_norm(v_city);
      v_status  := CASE WHEN v_gran IN ('PREMISE', 'SUB_PREMISE', 'PREMISE_PROXIMITY') THEN CASE WHEN v_match THEN 'VERIFIED' ELSE 'SUGGESTED' END
                        ELSE 'UNCONFIRMED' END;
      IF v_match THEN v_suggest := NULL; END IF;
    END IF;
    UPDATE fnd_contact_points
       SET is_verified = (v_status = 'VERIFIED'),
           verified_at = CASE WHEN v_status = 'VERIFIED' THEN now() END,
           suggested_address = v_suggest,
           google_geocode_response = COALESCE(google_geocode_response, '{}'::jsonb) || jsonb_build_object('validation',
             jsonb_build_object('status', v_status, 'at', now(), 'granularity', v_gran, 'verdict', r -> 'verdict'))
     WHERE contact_point_id = v_pt.contact_point_id;
    v_counts := jsonb_set(v_counts, ARRAY[v_status], to_jsonb((v_counts ->> v_status)::int + 1));
  END LOOP;
  RETURN v_counts;
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_address_validation_queue_get(bigint, integer, bigint[]), bps.fnd_address_validation_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_address_validation_queue_get(bigint, integer, bigint[]), bps.fnd_address_validation_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
