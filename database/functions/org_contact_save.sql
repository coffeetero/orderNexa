-- ============================================================
-- org_contact_save
-- Creates or updates one person contact from Organizer › Contacts. Returns the contact (org_contact_json).
-- p_contact: { contact_id (omit for new), customer_id (null = company contact, else a customer in the caller's scope),
--   name_prefix, first_name, middle_name, last_name, name_suffix, nickname, company_name, job_title, department, notes,
--   is_favorite, photo_data (key present = set or clear; absent = keep),
--   important_dates [{label, date 'YYYY-MM-DD' or '--MM-DD'}], related_people [{label, name}],
--   points [{contact_point_id?, type PHONE|MOBILE|FAX|EMAIL|ADDRESS|WEBSITE|OTHER, label, value, is_primary}],
--   tag_ids [..] (key present = replace the contact's tags) }
-- Points not in the list are removed, except legacy NOTE points, which this screen does not show and keeps.
-- card_name (the role on the customer screen's card) is set on create and kept afterwards; display_name follows
-- first + last name unless the customer screen gave it its own value. is_primary is never changed here.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_save(p_tenant_id bigint, p_contact jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user     bigint := bps.fnd_current_user_id();
  v_id       bigint := NULLIF(p_contact ->> 'contact_id', '')::bigint;
  v_cur      bps.fnd_contacts;
  v_cust     bigint := NULLIF(p_contact ->> 'customer_id', '')::bigint;
  v_source   text;
  v_entity   bigint;
  v_prefix   text := NULLIF(btrim(p_contact ->> 'name_prefix'), '');
  v_first    text := NULLIF(btrim(p_contact ->> 'first_name'), '');
  v_middle   text := NULLIF(btrim(p_contact ->> 'middle_name'), '');
  v_last     text := NULLIF(btrim(p_contact ->> 'last_name'), '');
  v_suffix   text := NULLIF(btrim(p_contact ->> 'name_suffix'), '');
  v_nick     text := NULLIF(btrim(p_contact ->> 'nickname'), '');
  v_company  text := NULLIF(btrim(p_contact ->> 'company_name'), '');
  v_job      text := NULLIF(btrim(p_contact ->> 'job_title'), '');
  v_dept     text := NULLIF(btrim(p_contact ->> 'department'), '');
  v_notes    text := NULLIF(btrim(p_contact ->> 'notes'), '');
  v_fav      boolean := COALESCE((p_contact ->> 'is_favorite')::boolean, false);
  v_photo    text;
  v_dates    jsonb := '[]'::jsonb;
  v_related  jsonb := '[]'::jsonb;
  v_derived  text;
  v_e        jsonb;
  v_txt      text;
  v_label    text;
  v_type     text;
  v_pid      bigint;
  v_kept     bigint[] := '{}';
  v_seq      int;
  v_prim     text[] := '{}';
  v_is_prim  boolean;
  v_tag_ids  bigint[];
BEGIN
  PERFORM bps.org_contact_check(p_tenant_id, NULL, 'W');
  IF v_id IS NOT NULL THEN v_cur := bps.org_contact_check(p_tenant_id, v_id, 'W'); END IF;

  -- Owner
  IF v_cust IS NULL THEN
    v_source := 'fnd_tenants'; v_entity := p_tenant_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM fnd_customers WHERE tenant_id = p_tenant_id AND customer_id = v_cust)
       OR NOT (bps.fnd_scope_is_all() OR v_cust = ANY (COALESCE(bps.fnd_scope_customer_ids(), '{}'::bigint[]))) THEN
      RAISE EXCEPTION 'Customer not found';
    END IF;
    v_source := 'fnd_customers'; v_entity := v_cust;
  END IF;

  -- Fields
  IF v_first IS NULL AND v_last IS NULL AND v_company IS NULL AND v_nick IS NULL THEN
    RAISE EXCEPTION 'Give the contact a name or a company';
  END IF;
  IF greatest(length(v_prefix), length(v_first), length(v_middle), length(v_last), length(v_suffix), length(v_nick),
              length(v_company), length(v_job), length(v_dept)) > 200 THEN
    RAISE EXCEPTION 'Names, company, job title and department are limited to 200 characters';
  END IF;
  IF length(v_notes) > 10000 THEN RAISE EXCEPTION 'Notes are limited to 10,000 characters'; END IF;

  IF p_contact ? 'photo_data' THEN
    v_photo := NULLIF(p_contact ->> 'photo_data', '');
    IF v_photo IS NOT NULL AND v_photo NOT LIKE 'data:image/%' THEN RAISE EXCEPTION 'The photo must be an image'; END IF;
    IF length(v_photo) > 200000 THEN RAISE EXCEPTION 'The photo is too large (limit 200 kB)'; END IF;
  ELSE
    v_photo := v_cur.photo_data;
  END IF;

  FOR v_e IN SELECT value FROM jsonb_array_elements(COALESCE(NULLIF(p_contact -> 'important_dates', 'null'::jsonb), '[]'::jsonb)) LOOP
    v_label := COALESCE(NULLIF(lower(btrim(v_e ->> 'label')), ''), 'other');
    v_txt := btrim(v_e ->> 'date');
    CONTINUE WHEN v_txt IS NULL OR v_txt = '';
    IF v_txt !~ '^(\d{4}|-)-\d{2}-\d{2}$' THEN RAISE EXCEPTION 'Dates must look like 1980-05-12, or --05-12 without a year'; END IF;
    BEGIN
      PERFORM make_date(CASE WHEN v_txt LIKE '--%' THEN 2000 ELSE left(v_txt, 4)::int END,
                        substr(v_txt, length(v_txt) - 4, 2)::int, right(v_txt, 2)::int);
    EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION '% is not a valid date', v_txt;
    END;
    IF length(v_label) > 40 THEN RAISE EXCEPTION 'Date labels are limited to 40 characters'; END IF;
    v_dates := v_dates || jsonb_build_array(jsonb_build_object('label', v_label, 'date', v_txt));
  END LOOP;

  FOR v_e IN SELECT value FROM jsonb_array_elements(COALESCE(NULLIF(p_contact -> 'related_people', 'null'::jsonb), '[]'::jsonb)) LOOP
    v_txt := NULLIF(btrim(v_e ->> 'name'), '');
    CONTINUE WHEN v_txt IS NULL;
    v_label := COALESCE(NULLIF(lower(btrim(v_e ->> 'label')), ''), 'other');
    IF length(v_txt) > 200 OR length(v_label) > 40 THEN RAISE EXCEPTION 'Related names are limited to 200 characters'; END IF;
    v_related := v_related || jsonb_build_array(jsonb_build_object('label', v_label, 'name', v_txt));
  END LOOP;

  -- Contact row
  v_derived := NULLIF(concat_ws(' ', v_first, v_last), '');
  IF v_id IS NULL THEN
    INSERT INTO fnd_contacts (tenant_id, entity_id, source_table, contact_type, card_name, display_name,
                              name_prefix, first_name, middle_name, last_name, name_suffix, nickname, company_name,
                              job_title, department, notes, is_favorite, photo_data, important_dates, related_people,
                              is_primary, is_active, created_by, updated_by)
    VALUES (p_tenant_id, v_entity, v_source, 'PERSON',
            CASE WHEN v_source = 'fnd_customers' THEN COALESCE(v_dept, v_job, v_derived, v_nick, v_company)
                 ELSE COALESCE(v_derived, v_nick, v_company) END,
            v_derived, v_prefix, v_first, v_middle, v_last, v_suffix, v_nick, v_company, v_job, v_dept, v_notes, v_fav,
            v_photo, v_dates, v_related, false, true, v_user, v_user)
    RETURNING contact_id INTO v_id;
  ELSE
    UPDATE fnd_contacts SET
      entity_id = v_entity, source_table = v_source,
      is_primary = CASE WHEN v_source = v_cur.source_table AND v_entity = v_cur.entity_id THEN is_primary ELSE false END,
      display_name = CASE WHEN display_name IS NULL OR display_name = NULLIF(concat_ws(' ', v_cur.first_name, v_cur.last_name), '')
                          THEN v_derived ELSE display_name END,
      name_prefix = v_prefix, first_name = v_first, middle_name = v_middle, last_name = v_last, name_suffix = v_suffix,
      nickname = v_nick, company_name = v_company, job_title = v_job, department = v_dept, notes = v_notes,
      is_favorite = v_fav, photo_data = v_photo, important_dates = v_dates, related_people = v_related,
      is_active = true, updated_at = now(), updated_by = v_user
     WHERE contact_id = v_id;
  END IF;

  -- Contact points: clear primaries first (one primary per type is enforced by a unique index)
  UPDATE fnd_contact_points SET is_primary = false WHERE contact_id = v_id AND type <> 'NOTE' AND is_primary;
  v_seq := 0;
  FOR v_e IN SELECT value FROM jsonb_array_elements(COALESCE(NULLIF(p_contact -> 'points', 'null'::jsonb), '[]'::jsonb)) LOOP
    v_type := upper(btrim(v_e ->> 'type'));
    v_txt := NULLIF(btrim(v_e ->> 'value'), '');
    v_label := NULLIF(btrim(v_e ->> 'label'), '');
    CONTINUE WHEN v_txt IS NULL;
    IF v_type IS NULL OR v_type NOT IN ('PHONE', 'MOBILE', 'FAX', 'EMAIL', 'ADDRESS', 'WEBSITE', 'OTHER') THEN
      RAISE EXCEPTION 'Unknown contact detail type %', COALESCE(v_type, '(none)');
    END IF;
    IF v_type = 'EMAIL' AND v_txt !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION '% is not an email address', v_txt; END IF;
    IF v_type IN ('PHONE', 'MOBILE', 'FAX') AND v_txt !~ '\d' THEN RAISE EXCEPTION '% is not a phone number', v_txt; END IF;
    IF length(v_txt) > 1000 OR length(v_label) > 60 THEN RAISE EXCEPTION 'A contact detail is too long'; END IF;
    v_seq := v_seq + 1;
    v_is_prim := COALESCE((v_e ->> 'is_primary')::boolean, false) AND NOT (v_type = ANY (v_prim));
    IF v_is_prim THEN v_prim := v_prim || v_type; END IF;
    v_pid := NULLIF(v_e ->> 'contact_point_id', '')::bigint;
    IF v_pid IS NOT NULL THEN
      UPDATE fnd_contact_points SET type = v_type, value = v_txt, label = v_label, sequence = v_seq, is_primary = v_is_prim,
                                    is_active = true, updated_by = v_user
       WHERE contact_point_id = v_pid AND contact_id = v_id AND type <> 'NOTE';
      IF NOT FOUND THEN v_pid := NULL; END IF;
    END IF;
    IF v_pid IS NULL THEN
      INSERT INTO fnd_contact_points (tenant_id, contact_id, type, value, label, sequence, is_primary, created_by, updated_by)
      VALUES (p_tenant_id, v_id, v_type, v_txt, v_label, v_seq, v_is_prim, v_user, v_user)
      RETURNING contact_point_id INTO v_pid;
    END IF;
    v_kept := v_kept || v_pid;
  END LOOP;
  DELETE FROM fnd_contact_points WHERE contact_id = v_id AND type <> 'NOTE' AND contact_point_id <> ALL (v_kept);

  -- Tags
  IF p_contact ? 'tag_ids' THEN
    SELECT COALESCE(array_agg(t.tag_id), '{}') INTO v_tag_ids
      FROM fnd_contact_tags t
     WHERE t.tenant_id = p_tenant_id
       AND t.tag_id IN (SELECT (x #>> '{}')::bigint FROM jsonb_array_elements(COALESCE(NULLIF(p_contact -> 'tag_ids', 'null'::jsonb), '[]'::jsonb)) x);
    DELETE FROM fnd_contact_tag_links WHERE contact_id = v_id AND tag_id <> ALL (v_tag_ids);
    INSERT INTO fnd_contact_tag_links (tenant_id, contact_id, tag_id, created_by)
    SELECT p_tenant_id, v_id, unnest(v_tag_ids), v_user
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN bps.org_contact_json((SELECT c FROM fnd_contacts c WHERE c.contact_id = v_id), true);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
