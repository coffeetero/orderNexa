-- ============================================================
-- fnd_notes_save
--
-- Inserts or updates a single note.
-- When p_entry.note_id is null → INSERT; otherwise UPDATE.
-- created_by / updated_by resolved from auth.uid() → fnd_users.
--
-- SECURITY DEFINER — bypasses RLS for writes; tenant validated via JWT.
-- fnd_notes_get (reads) uses SECURITY INVOKER so RLS visibility gate applies.
-- Prerequisites: fnd_notes.sql, fnd_users.sql
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_notes_save(
  p_tenant_id BIGINT,
  p_entry     JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
  v_note_id      BIGINT;
  v_user_id      BIGINT;
  v_entity_id    BIGINT;
  v_source_table TEXT;
  v_note_title   TEXT;
  v_note_text    TEXT;
  v_note_type    TEXT;
  v_is_important BOOLEAN;
  v_is_pinned    BOOLEAN;
  v_visibility   TEXT;
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
  WHERE auth_user_id = auth.uid()
    AND tenant_id    = p_tenant_id
  LIMIT 1;

  v_note_id      := NULLIF(p_entry->>'note_id', 'null')::BIGINT;
  v_entity_id    := (p_entry->>'entity_id')::BIGINT;
  v_source_table := p_entry->>'source_table';
  v_note_title   := NULLIF(TRIM(COALESCE(p_entry->>'note_title', '')), '');
  v_note_text    := TRIM(p_entry->>'note_text');
  v_note_type    := NULLIF(COALESCE(p_entry->>'note_type', ''), '');
  v_is_important := COALESCE((p_entry->>'is_important')::BOOLEAN, false);
  v_is_pinned    := COALESCE((p_entry->>'is_pinned')::BOOLEAN, false);
  v_visibility   := COALESCE(NULLIF(p_entry->>'visibility', ''), 'tenant_only');

  IF v_note_id IS NULL THEN
    INSERT INTO fnd_notes (
      tenant_id, entity_id, source_table,
      note_title, note_text, note_type,
      is_important, is_pinned, visibility,
      created_by, updated_by
    ) VALUES (
      p_tenant_id, v_entity_id, v_source_table,
      v_note_title, v_note_text, v_note_type,
      v_is_important, v_is_pinned, v_visibility,
      v_user_id, v_user_id
    )
    RETURNING note_id INTO v_note_id;
  ELSE
    UPDATE fnd_notes SET
      note_title   = v_note_title,
      note_text    = v_note_text,
      note_type    = v_note_type,
      is_important = v_is_important,
      is_pinned    = v_is_pinned,
      visibility   = v_visibility,
      updated_by   = v_user_id
    WHERE note_id   = v_note_id
      AND tenant_id = p_tenant_id;
  END IF;

  RETURN jsonb_build_object('note_id', v_note_id);
END;
$$;
