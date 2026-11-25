-- ============================================================
-- org_contact_note_save
-- Adds or edits a timestamped note on a contact (fnd_notes, source_table 'fnd_contacts', entity_id = contact_id).
-- p_note: { note_id (omit for new), note_text, is_pinned }. Returns { note_id }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_note_save(p_tenant_id bigint, p_contact_id bigint, p_note jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v      bps.fnd_contacts := bps.org_contact_check(p_tenant_id, p_contact_id, 'W');
  v_user bigint  := bps.fnd_current_user_id();
  v_id   bigint  := NULLIF(p_note ->> 'note_id', '')::bigint;
  v_text text    := NULLIF(btrim(p_note ->> 'note_text'), '');
  v_pin  boolean := COALESCE((p_note ->> 'is_pinned')::boolean, false);
BEGIN
  IF v_text IS NULL THEN RAISE EXCEPTION 'Write something in the note'; END IF;
  IF length(v_text) > 10000 THEN RAISE EXCEPTION 'A note is limited to 10,000 characters'; END IF;
  IF v_id IS NULL THEN
    INSERT INTO fnd_notes (tenant_id, entity_id, source_table, note_text, is_pinned, created_by, updated_by)
    VALUES (p_tenant_id, v.contact_id, 'fnd_contacts', v_text, v_pin, v_user, v_user) RETURNING note_id INTO v_id;
  ELSE
    UPDATE fnd_notes SET note_text = v_text, is_pinned = v_pin, updated_by = v_user
     WHERE note_id = v_id AND tenant_id = p_tenant_id AND source_table = 'fnd_contacts' AND entity_id = v.contact_id
       AND deleted_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Note not found'; END IF;
  END IF;
  RETURN jsonb_build_object('note_id', v_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_note_save(bigint, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_note_save(bigint, bigint, jsonb) TO authenticated, service_role, bps_dev;
