-- ============================================================
-- org_contacts_import
-- Imports company contacts parsed from a vCard or CSV file (parsing happens in the browser).
-- p_rows: [ org_contact_save payloads without contact_id / customer_id, plus tag_names [..] ] (at most 5,000).
-- p_commit false = preview: every row is checked by the real save inside a rolled-back step, nothing is kept.
-- Each row comes back as NEW (would be / was created: CREATED), DUPLICATE (same name, email or phone as a contact
-- already in the address book or earlier in the file, see org_contact_match_keys; skipped) or INVALID (with the reason).
-- Tags named in tag_names are created when missing. Returns { rows: [{ row, status, message, contact_id, match }],
-- new, duplicate, invalid }.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contacts_import(p_tenant_id bigint, p_rows jsonb, p_commit boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_all    boolean;
  v_ids    bigint[];
  v_seen   jsonb;
  v_row    jsonb;
  v_i      int := 0;
  v_keys   text[];
  v_match  text;
  v_tags   jsonb;
  v_name   text;
  v_tag_id bigint;
  v_saved  jsonb;
  v_out    jsonb := '[]'::jsonb;
  v_new    int := 0;
  v_dup    int := 0;
  v_bad    int := 0;
BEGIN
  PERFORM bps.org_contact_check(p_tenant_id, NULL, 'W');
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN RAISE EXCEPTION 'Nothing to import'; END IF;
  IF jsonb_array_length(p_rows) > 5000 THEN RAISE EXCEPTION 'Import at most 5,000 contacts at a time'; END IF;
  v_all := bps.fnd_scope_is_all();
  v_ids := COALESCE(bps.fnd_scope_customer_ids(), '{}'::bigint[]);

  -- Match keys of the contacts already in the address book → the contact's name
  SELECT COALESCE(jsonb_object_agg(k, nm), '{}'::jsonb) INTO v_seen
    FROM (SELECT DISTINCT ON (k) k, bps.fnd_contact_display_name(c) AS nm
            FROM fnd_contacts c
            CROSS JOIN LATERAL unnest(bps.org_contact_match_keys(jsonb_build_object(
                     'first_name', c.first_name, 'last_name', c.last_name,
                     'points', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type', cp.type, 'value', cp.value)), '[]'::jsonb)
                                  FROM fnd_contact_points cp WHERE cp.contact_id = c.contact_id AND cp.is_active)))) k
           WHERE c.tenant_id = p_tenant_id AND c.contact_type = 'PERSON' AND c.is_active
             AND ((c.source_table = 'fnd_tenants' AND c.entity_id = p_tenant_id)
                  OR (c.source_table = 'fnd_customers' AND (v_all OR c.entity_id = ANY (v_ids))))
           ORDER BY k, c.contact_id) x;

  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
    v_i := v_i + 1;
    v_row := (v_row - 'contact_id' - 'customer_id');
    v_keys := bps.org_contact_match_keys(v_row);
    SELECT v_seen ->> k INTO v_match FROM unnest(v_keys) k WHERE v_seen ? k LIMIT 1;
    IF v_match IS NOT NULL THEN
      v_dup := v_dup + 1;
      v_out := v_out || jsonb_build_array(jsonb_build_object('row', v_i, 'status', 'DUPLICATE', 'match', v_match,
                                                             'message', 'Matches ' || v_match));
      CONTINUE;
    END IF;

    BEGIN
      v_tags := '[]'::jsonb;
      FOR v_name IN SELECT DISTINCT btrim(x) FROM jsonb_array_elements_text(
                      CASE WHEN jsonb_typeof(v_row -> 'tag_names') = 'array' THEN v_row -> 'tag_names' ELSE '[]'::jsonb END) x
                     WHERE btrim(x) <> '' LOOP
        SELECT tag_id INTO v_tag_id FROM fnd_contact_tags WHERE tenant_id = p_tenant_id AND lower(tag_name) = lower(v_name);
        IF NOT FOUND THEN
          v_tag_id := (bps.org_contact_tag_save(p_tenant_id, jsonb_build_object('tag_name', v_name)) ->> 'tag_id')::bigint;
        END IF;
        v_tags := v_tags || to_jsonb(v_tag_id);
      END LOOP;
      v_saved := bps.org_contact_save(p_tenant_id, (v_row - 'tag_names') || jsonb_build_object('tag_ids', v_tags));
      IF NOT p_commit THEN RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = 'preview'; END IF;
      v_new := v_new + 1;
      v_out := v_out || jsonb_build_array(jsonb_build_object('row', v_i, 'status', 'CREATED', 'contact_id', v_saved -> 'contact_id'));
    EXCEPTION
      WHEN SQLSTATE 'P0099' THEN
        v_new := v_new + 1;
        v_out := v_out || jsonb_build_array(jsonb_build_object('row', v_i, 'status', 'NEW'));
      WHEN OTHERS THEN
        v_bad := v_bad + 1;
        v_out := v_out || jsonb_build_array(jsonb_build_object('row', v_i, 'status', 'INVALID', 'message', SQLERRM));
        CONTINUE;
    END;
    -- later rows with the same name / email / phone are duplicates of this one
    SELECT v_seen || COALESCE(jsonb_object_agg(k, COALESCE(NULLIF(concat_ws(' ', v_row ->> 'first_name', v_row ->> 'last_name'), ''),
                                                           v_row ->> 'company_name', 'row ' || v_i)), '{}'::jsonb)
      INTO v_seen FROM unnest(v_keys) k;
  END LOOP;

  RETURN jsonb_build_object('rows', v_out, 'new', v_new, 'duplicate', v_dup, 'invalid', v_bad);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contacts_import(bigint, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contacts_import(bigint, jsonb, boolean) TO authenticated, service_role, bps_dev;
