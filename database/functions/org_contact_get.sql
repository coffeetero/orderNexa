-- ============================================================
-- org_contact_get
-- One contact for the detail pane: fields, photo, contact points, tags and its notes timeline (pinned first, newest first).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_get(p_tenant_id bigint, p_contact_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v bps.fnd_contacts := bps.org_contact_check(p_tenant_id, p_contact_id, 'R');
BEGIN
  RETURN bps.org_contact_json(v, true) || jsonb_build_object('timeline', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('note_id', n.note_id, 'note_text', n.note_text, 'is_pinned', n.is_pinned,
                                        'created_at', n.created_at, 'updated_at', n.updated_at,
                                        'author_name', COALESCE(u.user_name, u.email, 'Unknown'))
                     ORDER BY n.is_pinned DESC, n.created_at DESC)
      FROM fnd_notes n LEFT JOIN fnd_users u ON u.user_id = n.created_by
     WHERE n.tenant_id = p_tenant_id AND n.source_table = 'fnd_contacts' AND n.entity_id = v.contact_id
       AND n.deleted_at IS NULL), '[]'::jsonb));
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_get(bigint, bigint) TO authenticated, service_role, bps_dev;
