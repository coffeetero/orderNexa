-- ============================================================
-- org_contact_note_delete
-- Removes a contact note (soft delete: deleted_at). Returns { note_id }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_note_delete(p_tenant_id bigint, p_note_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_contact bigint;
BEGIN
  PERFORM bps.org_contact_check(p_tenant_id, NULL, 'W');
  SELECT entity_id INTO v_contact FROM fnd_notes
   WHERE note_id = p_note_id AND tenant_id = p_tenant_id AND source_table = 'fnd_contacts' AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Note not found'; END IF;
  PERFORM bps.org_contact_check(p_tenant_id, v_contact, 'W');
  UPDATE fnd_notes SET deleted_at = now(), updated_by = bps.fnd_current_user_id() WHERE note_id = p_note_id;
  RETURN jsonb_build_object('note_id', p_note_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_note_delete(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_note_delete(bigint, bigint) TO authenticated, service_role, bps_dev;
