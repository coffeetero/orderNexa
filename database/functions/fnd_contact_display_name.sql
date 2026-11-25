-- ============================================================
-- fnd_contact_display_name
-- The name a contact is shown under: prefix first middle last suffix, else display name, nickname, company, card name.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_contact_display_name(p bps.fnd_contacts)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT COALESCE(
    NULLIF(concat_ws(' ', NULLIF(btrim(p.name_prefix), ''), NULLIF(btrim(p.first_name), ''), NULLIF(btrim(p.middle_name), ''),
                          NULLIF(btrim(p.last_name), ''), NULLIF(btrim(p.name_suffix), '')), ''),
    NULLIF(btrim(p.display_name), ''), NULLIF(btrim(p.nickname), ''), NULLIF(btrim(p.company_name), ''), p.card_name)
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_contact_display_name(bps.fnd_contacts) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_contact_display_name(bps.fnd_contacts) TO authenticated, service_role, bps_dev;
