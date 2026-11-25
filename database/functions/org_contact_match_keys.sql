-- ============================================================
-- org_contact_match_keys
-- The keys two contacts are considered duplicates on (the one duplicate rule, used by org_contact_duplicates_get and
-- org_contacts_import): 'name:<first last>' (both names given, case-insensitive), 'email:<address>' (lower case) and
-- 'phone:<last 10 digits>' (7 or more digits). p: { first_name, last_name, points [{type, value}] }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_match_keys(p jsonb)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT COALESCE(array_agg(DISTINCT k) FILTER (WHERE k IS NOT NULL), '{}')
    FROM (
      SELECT CASE WHEN NULLIF(btrim(p ->> 'first_name'), '') IS NOT NULL AND NULLIF(btrim(p ->> 'last_name'), '') IS NOT NULL
                  THEN 'name:' || lower(btrim(p ->> 'first_name') || ' ' || btrim(p ->> 'last_name')) END AS k
      UNION ALL
      SELECT CASE
               WHEN upper(e ->> 'type') = 'EMAIL' AND NULLIF(btrim(e ->> 'value'), '') IS NOT NULL
                 THEN 'email:' || lower(btrim(e ->> 'value'))
               WHEN upper(e ->> 'type') IN ('PHONE', 'MOBILE') AND length(regexp_replace(e ->> 'value', '\D', '', 'g')) >= 7
                 THEN 'phone:' || right(regexp_replace(e ->> 'value', '\D', '', 'g'), 10)
             END
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p -> 'points') = 'array' THEN p -> 'points' ELSE '[]'::jsonb END) e
    ) x
$function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_match_keys(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_match_keys(jsonb) TO authenticated, service_role, bps_dev;
