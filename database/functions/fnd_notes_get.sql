-- ============================================================
-- fnd_notes_get
--
-- Returns all active notes for a given entity, with author name
-- joined from fnd_users. Sorted: pinned first, then newest first.
--
-- SECURITY INVOKER — RLS on fnd_notes enforces tenant scoping and visibility.
-- Prerequisites: fnd_notes.sql, fnd_users.sql
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_notes_get(
  p_tenant_id    BIGINT,
  p_entity_id    BIGINT,
  p_source_table TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = bps, public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'note_id',      n.note_id,
        'note_title',   n.note_title,
        'note_text',    n.note_text,
        'note_type',    n.note_type,
        'is_important', n.is_important,
        'is_pinned',    n.is_pinned,
        'visibility',   n.visibility,
        'created_at',   n.created_at,
        'created_by',   n.created_by,
        'author_name',  COALESCE(u.user_name, u.email, 'Unknown'),
        'updated_at',   n.updated_at
      )
      ORDER BY n.is_pinned DESC, n.created_at DESC
    ),
    '[]'::JSONB
  )
  INTO v_result
  FROM fnd_notes n
  LEFT JOIN fnd_users u
         ON u.user_id   = n.created_by
        AND u.tenant_id = p_tenant_id
  WHERE n.tenant_id    = p_tenant_id
    AND n.entity_id    = p_entity_id
    AND n.source_table = p_source_table
    AND n.deleted_at   IS NULL;

  RETURN v_result;
END;
$$;
