-- ============================================================
-- org_contact_delete
-- Deletes a contact (with its contact points and tags). A contact that has notes is deactivated instead, so the notes
-- history stays. Returns { contact_id, result: 'DELETED' | 'DEACTIVATED' }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_delete(p_tenant_id bigint, p_contact_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v bps.fnd_contacts := bps.org_contact_check(p_tenant_id, p_contact_id, 'D');
BEGIN
  IF EXISTS (SELECT 1 FROM fnd_notes n WHERE n.tenant_id = p_tenant_id AND n.source_table = 'fnd_contacts'
                                         AND n.entity_id = v.contact_id AND n.deleted_at IS NULL) THEN
    UPDATE fnd_contacts SET is_active = false, is_primary = false, is_favorite = false,
                            updated_at = now(), updated_by = bps.fnd_current_user_id()
     WHERE contact_id = v.contact_id;
    RETURN jsonb_build_object('contact_id', v.contact_id, 'result', 'DEACTIVATED');
  END IF;
  DELETE FROM fnd_contacts WHERE contact_id = v.contact_id;
  RETURN jsonb_build_object('contact_id', v.contact_id, 'result', 'DELETED');
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
