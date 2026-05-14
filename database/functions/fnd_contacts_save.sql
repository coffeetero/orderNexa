-- ============================================================
-- fnd_contacts_save
-- Upserts one contact and its contact points.
-- Points present in p_contact.contact_points are inserted or
-- updated; points previously saved but absent from the array
-- are deleted.
--
-- contact_type is immutable after creation:
--   PERSON         — regular person contact
--   ADDRESSES      — system contact: all entity addresses
--   OTHER_CONTACTS — system contact: misc / legacy contact data
--
-- card_name and display_name are locked for system contacts.
-- is_primary is forced FALSE for ADDRESSES / OTHER_CONTACTS.
--
-- SECURITY DEFINER — bypasses RLS; tenant validated via JWT.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_contacts_save(
  p_tenant_id    BIGINT,
  p_entity_id    BIGINT,
  p_source_table TEXT,
  p_contact      JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
  v_user_id      BIGINT;
  v_contact_id   BIGINT;
  v_contact_type TEXT;
  v_is_primary   BOOLEAN;
  v_point        JSONB;
  v_point_id     BIGINT;
  v_pt_primary   BOOLEAN;
  v_kept_ids     BIGINT[] := '{}';
BEGIN
  IF NOT (
    p_tenant_id::text = ANY (ARRAY(
      SELECT jsonb_array_elements_text(
        (NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb
          -> 'app_metadata' -> 'allowed_tenant_ids'
      )
    ))
  ) THEN
    RAISE EXCEPTION 'Access denied for tenant %', p_tenant_id;
  END IF;

  SELECT user_id INTO v_user_id
  FROM fnd_users
  WHERE auth_user_id = auth.uid() AND tenant_id = p_tenant_id
  LIMIT 1;

  v_contact_id := NULLIF(p_contact->>'contact_id', '')::BIGINT;

  IF v_contact_id IS NOT NULL THEN
    SELECT contact_type INTO v_contact_type
    FROM fnd_contacts WHERE contact_id = v_contact_id AND tenant_id = p_tenant_id;
  ELSE
    v_contact_type := COALESCE(NULLIF(p_contact->>'contact_type', ''), 'PERSON');
  END IF;

  v_is_primary := CASE
    WHEN v_contact_type IN ('ADDRESSES', 'OTHER_CONTACTS') THEN FALSE
    ELSE COALESCE((p_contact->>'is_primary')::BOOLEAN, FALSE)
  END;

  -- ── Upsert contact ──────────────────────────────────────────
  IF v_contact_id IS NULL THEN
    INSERT INTO fnd_contacts (
      tenant_id, entity_id, source_table, contact_type,
      card_name, display_name, first_name, last_name,
      job_title, department, is_primary, is_active, created_by, updated_by
    ) VALUES (
      p_tenant_id, p_entity_id, p_source_table, v_contact_type,
      CASE v_contact_type
        WHEN 'ADDRESSES'      THEN 'Billing & Shipping'
        WHEN 'OTHER_CONTACTS' THEN 'Other Contacts'
        ELSE p_contact->>'card_name'
      END,
      CASE WHEN v_contact_type = 'PERSON' THEN NULLIF(p_contact->>'display_name', '') ELSE NULL END,
      NULLIF(p_contact->>'first_name', ''),
      NULLIF(p_contact->>'last_name',  ''),
      NULLIF(p_contact->>'job_title',  ''),
      NULLIF(p_contact->>'department', ''),
      v_is_primary,
      COALESCE((p_contact->>'is_active')::BOOLEAN, TRUE),
      v_user_id, v_user_id
    )
    RETURNING contact_id INTO v_contact_id;
  ELSE
    UPDATE fnd_contacts SET
      card_name    = CASE v_contact_type
                       WHEN 'ADDRESSES'      THEN 'Billing & Shipping'
                       WHEN 'OTHER_CONTACTS' THEN 'Other Contacts'
                       ELSE p_contact->>'card_name'
                     END,
      display_name = CASE WHEN v_contact_type = 'PERSON' THEN NULLIF(p_contact->>'display_name', '') ELSE display_name END,
      first_name   = CASE WHEN v_contact_type = 'PERSON' THEN NULLIF(p_contact->>'first_name', '') ELSE first_name END,
      last_name    = CASE WHEN v_contact_type = 'PERSON' THEN NULLIF(p_contact->>'last_name',  '') ELSE last_name  END,
      job_title    = CASE WHEN v_contact_type = 'PERSON' THEN NULLIF(p_contact->>'job_title',  '') ELSE job_title  END,
      department   = CASE WHEN v_contact_type = 'PERSON' THEN NULLIF(p_contact->>'department', '') ELSE department END,
      is_primary   = v_is_primary,
      is_active    = COALESCE((p_contact->>'is_active')::BOOLEAN, TRUE),
      updated_by   = v_user_id
    WHERE contact_id = v_contact_id AND tenant_id = p_tenant_id;
  END IF;

  IF v_is_primary AND v_contact_type = 'PERSON' THEN
    UPDATE fnd_contacts SET is_primary = FALSE
    WHERE tenant_id    = p_tenant_id
      AND entity_id    = p_entity_id
      AND source_table = p_source_table
      AND contact_type = 'PERSON'
      AND contact_id  != v_contact_id;
  END IF;

  -- ── Upsert contact points ───────────────────────────────────
  FOR v_point IN
    SELECT * FROM jsonb_array_elements(COALESCE(p_contact->'contact_points', '[]'::jsonb))
  LOOP
    v_point_id   := NULLIF(v_point->>'contact_point_id', '')::BIGINT;
    v_pt_primary := COALESCE((v_point->>'is_primary')::BOOLEAN, FALSE);

    IF v_point_id IS NULL THEN
      INSERT INTO fnd_contact_points (
        tenant_id, contact_id, type, value, label, sequence,
        is_primary, is_active, do_not_contact, use_as_shipping,
        country_dial_code, created_by, updated_by
      ) VALUES (
        p_tenant_id, v_contact_id,
        v_point->>'type', v_point->>'value',
        NULLIF(v_point->>'label', ''),
        COALESCE(NULLIF(v_point->>'sequence', '')::SMALLINT, 1),
        v_pt_primary,
        COALESCE((v_point->>'is_active')::BOOLEAN, TRUE),
        COALESCE((v_point->>'do_not_contact')::BOOLEAN, FALSE),
        COALESCE((v_point->>'use_as_shipping')::BOOLEAN, FALSE),
        NULLIF(v_point->>'country_dial_code', ''),
        v_user_id, v_user_id
      )
      RETURNING contact_point_id INTO v_point_id;
    ELSE
      UPDATE fnd_contact_points SET
        value             = v_point->>'value',
        label             = NULLIF(v_point->>'label', ''),
        sequence          = COALESCE(NULLIF(v_point->>'sequence', '')::SMALLINT, sequence),
        is_primary        = v_pt_primary,
        is_active         = COALESCE((v_point->>'is_active')::BOOLEAN, is_active),
        do_not_contact    = COALESCE((v_point->>'do_not_contact')::BOOLEAN, do_not_contact),
        use_as_shipping   = COALESCE((v_point->>'use_as_shipping')::BOOLEAN, use_as_shipping),
        country_dial_code = NULLIF(v_point->>'country_dial_code', ''),
        updated_by        = v_user_id
      WHERE contact_point_id = v_point_id AND tenant_id = p_tenant_id;
    END IF;

    v_kept_ids := v_kept_ids || v_point_id;

    IF v_pt_primary THEN
      UPDATE fnd_contact_points SET is_primary = FALSE
      WHERE contact_id       = v_contact_id
        AND tenant_id        = p_tenant_id
        AND type             = v_point->>'type'
        AND contact_point_id != v_point_id;
    END IF;
  END LOOP;

  -- ── Delete removed points ───────────────────────────────────
  DELETE FROM fnd_contact_points
  WHERE contact_id = v_contact_id
    AND tenant_id  = p_tenant_id
    AND contact_point_id != ALL(v_kept_ids);

  RETURN jsonb_build_object('contact_id', v_contact_id);
END;
$$;
