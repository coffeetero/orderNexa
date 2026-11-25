-- ============================================================
-- org_contact_tag_save
-- Creates or renames a contact tag. p_tag: { tag_id (omit for new), tag_name, tag_color }.
-- Names are unique per tenant, ignoring case. Returns the tag.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_tag_save(p_tenant_id bigint, p_tag jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user  bigint := bps.fnd_current_user_id();
  v_id    bigint := NULLIF(p_tag ->> 'tag_id', '')::bigint;
  v_name  text   := NULLIF(btrim(p_tag ->> 'tag_name'), '');
  v_color text   := COALESCE(NULLIF(lower(btrim(p_tag ->> 'tag_color')), ''), 'gray');
BEGIN
  PERFORM bps.org_contact_check(p_tenant_id, NULL, 'W');
  IF v_name IS NULL THEN RAISE EXCEPTION 'Give the tag a name'; END IF;
  IF length(v_name) > 60 THEN RAISE EXCEPTION 'Tag names are limited to 60 characters'; END IF;
  IF v_color NOT IN ('gray', 'red', 'orange', 'amber', 'green', 'teal', 'sky', 'blue', 'violet', 'pink') THEN v_color := 'gray'; END IF;
  IF EXISTS (SELECT 1 FROM fnd_contact_tags WHERE tenant_id = p_tenant_id AND lower(tag_name) = lower(v_name)
                                              AND tag_id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'A tag named % already exists', v_name;
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO fnd_contact_tags (tenant_id, tag_name, tag_color, created_by, updated_by)
    VALUES (p_tenant_id, v_name, v_color, v_user, v_user) RETURNING tag_id INTO v_id;
  ELSE
    UPDATE fnd_contact_tags SET tag_name = v_name, tag_color = v_color, updated_by = v_user
     WHERE tenant_id = p_tenant_id AND tag_id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Tag not found'; END IF;
  END IF;
  RETURN jsonb_build_object('tag_id', v_id, 'tag_name', v_name, 'tag_color', v_color);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_tag_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_tag_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
