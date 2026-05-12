-- ============================================================
-- fnd_notes_delete
--
-- Soft-deletes a note by setting deleted_at = now().
-- Records updated_by from the calling user.
--
-- SECURITY INVOKER — RLS on fnd_notes enforces tenant scoping.
-- Prerequisites: fnd_notes.sql, fnd_users.sql
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_notes_delete(
  p_tenant_id BIGINT,
  p_note_id   BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = bps, public
AS $$
DECLARE
  v_user_id BIGINT;
BEGIN
  SELECT user_id INTO v_user_id
  FROM fnd_users
  WHERE auth_user_id = auth.uid()
    AND tenant_id    = p_tenant_id
  LIMIT 1;

  UPDATE fnd_notes SET
    deleted_at = now(),
    updated_by = v_user_id
  WHERE note_id   = p_note_id
    AND tenant_id = p_tenant_id
    AND deleted_at IS NULL;

  RETURN jsonb_build_object('deleted', p_note_id);
END;
$$;
