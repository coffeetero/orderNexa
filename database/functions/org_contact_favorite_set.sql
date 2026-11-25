-- ============================================================
-- org_contact_favorite_set
-- Marks or unmarks a contact as a favourite (company-wide). Returns { contact_id, is_favorite }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_favorite_set(p_tenant_id bigint, p_contact_id bigint, p_is_favorite boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v bps.fnd_contacts := bps.org_contact_check(p_tenant_id, p_contact_id, 'W');
BEGIN
  UPDATE fnd_contacts SET is_favorite = COALESCE(p_is_favorite, false), updated_at = now(), updated_by = bps.fnd_current_user_id()
   WHERE contact_id = v.contact_id;
  RETURN jsonb_build_object('contact_id', v.contact_id, 'is_favorite', COALESCE(p_is_favorite, false));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_favorite_set(bigint, bigint, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_favorite_set(bigint, bigint, boolean) TO authenticated, service_role, bps_dev;
