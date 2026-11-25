-- ============================================================
-- org_contact_merge
-- Merges p_merge_id into p_keep_id and deletes p_merge_id. The kept contact keeps its own values and owner; blank
-- fields are filled from the merged one; notes fields are joined; dates, related names, tags, timeline notes and
-- contact points are combined (a point already on the kept contact, same kind and value, is not repeated).
-- A customer's contact can only be merged into a contact of the same customer (keep the customer's contact instead).
-- Needs edit and delete access. Returns the kept contact (org_contact_json).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_merge(p_tenant_id bigint, p_keep_id bigint, p_merge_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  k      bps.fnd_contacts := bps.org_contact_check(p_tenant_id, p_keep_id, 'W');
  m      bps.fnd_contacts := bps.org_contact_check(p_tenant_id, p_merge_id, 'D');
  v_user bigint := bps.fnd_current_user_id();
BEGIN
  IF k.contact_id = m.contact_id THEN RAISE EXCEPTION 'Pick two different contacts'; END IF;
  IF m.source_table = 'fnd_customers' AND (k.source_table, k.entity_id) IS DISTINCT FROM (m.source_table, m.entity_id) THEN
    RAISE EXCEPTION 'This contact belongs to a customer: keep it and merge the other contact into it';
  END IF;

  -- points: move the ones the kept contact does not have yet (same kind of detail and same value)
  UPDATE fnd_contact_points mp SET contact_id = k.contact_id, is_primary = false, sequence = 100 + mp.sequence, updated_by = v_user
   WHERE mp.contact_id = m.contact_id AND mp.is_active
     AND NOT EXISTS (
       SELECT 1 FROM fnd_contact_points kp
        WHERE kp.contact_id = k.contact_id AND kp.is_active
          AND (CASE WHEN kp.type IN ('PHONE', 'MOBILE', 'FAX') THEN 'PHONE' ELSE kp.type END)
              = (CASE WHEN mp.type IN ('PHONE', 'MOBILE', 'FAX') THEN 'PHONE' ELSE mp.type END)
          AND (CASE WHEN kp.type IN ('PHONE', 'MOBILE', 'FAX') THEN right(regexp_replace(kp.value, '\D', '', 'g'), 10)
                    ELSE lower(btrim(kp.value)) END)
              = (CASE WHEN mp.type IN ('PHONE', 'MOBILE', 'FAX') THEN right(regexp_replace(mp.value, '\D', '', 'g'), 10)
                      ELSE lower(btrim(mp.value)) END));

  INSERT INTO fnd_contact_tag_links (tenant_id, contact_id, tag_id, created_by)
  SELECT p_tenant_id, k.contact_id, l.tag_id, v_user FROM fnd_contact_tag_links l WHERE l.contact_id = m.contact_id
  ON CONFLICT DO NOTHING;

  UPDATE fnd_notes SET entity_id = k.contact_id, updated_by = v_user
   WHERE tenant_id = p_tenant_id AND source_table = 'fnd_contacts' AND entity_id = m.contact_id;

  DELETE FROM fnd_contacts WHERE contact_id = m.contact_id;

  UPDATE fnd_contacts SET
    name_prefix  = COALESCE(k.name_prefix, m.name_prefix),
    first_name   = COALESCE(k.first_name, m.first_name),
    middle_name  = COALESCE(k.middle_name, m.middle_name),
    last_name    = COALESCE(k.last_name, m.last_name),
    name_suffix  = COALESCE(k.name_suffix, m.name_suffix),
    nickname     = COALESCE(k.nickname, m.nickname),
    company_name = COALESCE(k.company_name, m.company_name),
    job_title    = COALESCE(k.job_title, m.job_title),
    department   = COALESCE(k.department, m.department),
    display_name = COALESCE(k.display_name, m.display_name),
    photo_data   = COALESCE(k.photo_data, m.photo_data),
    notes        = CASE WHEN m.notes IS NULL OR k.notes = m.notes THEN k.notes
                        WHEN k.notes IS NULL THEN m.notes ELSE k.notes || E'\n\n' || m.notes END,
    is_favorite  = k.is_favorite OR m.is_favorite,
    is_primary   = k.is_primary OR (m.is_primary AND m.source_table = k.source_table AND m.entity_id = k.entity_id),
    important_dates = k.important_dates || COALESCE((SELECT jsonb_agg(e) FROM jsonb_array_elements(m.important_dates) e
                                                      WHERE NOT k.important_dates @> jsonb_build_array(e)), '[]'::jsonb),
    related_people  = k.related_people || COALESCE((SELECT jsonb_agg(e) FROM jsonb_array_elements(m.related_people) e
                                                     WHERE NOT k.related_people @> jsonb_build_array(e)), '[]'::jsonb),
    updated_at = now(), updated_by = v_user
   WHERE contact_id = k.contact_id;

  RETURN bps.org_contact_json((SELECT c FROM fnd_contacts c WHERE c.contact_id = k.contact_id), true);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_merge(bigint, bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_merge(bigint, bigint, bigint) TO authenticated, service_role, bps_dev;
