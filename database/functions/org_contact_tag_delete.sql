-- ============================================================
-- org_contact_tag_delete
-- Deletes a contact tag; contacts keep everything else. Returns { tag_id }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_tag_delete(p_tenant_id bigint, p_tag_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.org_contact_check(p_tenant_id, NULL, 'D');
  DELETE FROM fnd_contact_tags WHERE tenant_id = p_tenant_id AND tag_id = p_tag_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tag not found'; END IF;
  RETURN jsonb_build_object('tag_id', p_tag_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_tag_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_tag_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
