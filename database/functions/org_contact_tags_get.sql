-- ============================================================
-- org_contact_tags_get
-- The tenant's contact tags (labels) with how many active contacts carry each, by name.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_tags_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  PERFORM bps.org_contact_check(p_tenant_id, NULL, 'R');
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('tag_id', t.tag_id, 'tag_name', t.tag_name, 'tag_color', t.tag_color,
                                        'contact_count', (SELECT count(*) FROM fnd_contact_tag_links l
                                                            JOIN fnd_contacts c ON c.contact_id = l.contact_id AND c.is_active
                                                           WHERE l.tag_id = t.tag_id))
                     ORDER BY lower(t.tag_name))
      FROM fnd_contact_tags t WHERE t.tenant_id = p_tenant_id), '[]'::jsonb);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_tags_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_tags_get(bigint) TO authenticated, service_role, bps_dev;
