-- ============================================================
-- org_contact_json
-- Internal: one contact with its owner, contact points (not the legacy NOTE points) and tags, as Organizer › Contacts
-- shows it. p_with_photo adds photo_data. Callers check access first (org_contact_check).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_json(p bps.fnd_contacts, p_with_photo boolean DEFAULT true)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT jsonb_build_object(
    'contact_id', p.contact_id,
    'full_name', bps.fnd_contact_display_name(p),
    'name_prefix', p.name_prefix, 'first_name', p.first_name, 'middle_name', p.middle_name, 'last_name', p.last_name,
    'name_suffix', p.name_suffix, 'nickname', p.nickname, 'company_name', p.company_name,
    'job_title', p.job_title, 'department', p.department, 'notes', p.notes,
    'is_favorite', p.is_favorite, 'is_active', p.is_active, 'is_primary', p.is_primary,
    'important_dates', p.important_dates, 'related_people', p.related_people,
    'has_photo', p.photo_data IS NOT NULL,
    'photo_data', CASE WHEN p_with_photo THEN p.photo_data END,
    'kind', CASE WHEN p.source_table = 'fnd_customers' THEN 'CUSTOMER' ELSE 'COMPANY' END,
    'customer_id', cu.customer_id, 'customer_name', cu.customer_name, 'customer_number', cu.customer_number,
    'points', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                 'contact_point_id', cp.contact_point_id, 'type', cp.type, 'label', cp.label, 'value', cp.value,
                 'is_primary', cp.is_primary, 'do_not_contact', cp.do_not_contact)
                 ORDER BY cp.type, cp.sequence, cp.contact_point_id)
               FROM fnd_contact_points cp
              WHERE cp.contact_id = p.contact_id AND cp.is_active AND cp.type <> 'NOTE'), '[]'::jsonb),
    'tags', COALESCE((SELECT jsonb_agg(jsonb_build_object('tag_id', t.tag_id, 'tag_name', t.tag_name, 'tag_color', t.tag_color)
                 ORDER BY lower(t.tag_name))
               FROM fnd_contact_tag_links l JOIN fnd_contact_tags t ON t.tag_id = l.tag_id
              WHERE l.contact_id = p.contact_id), '[]'::jsonb),
    'created_at', p.created_at, 'created_by_name', uc.user_name,
    'updated_at', p.updated_at, 'updated_by_name', uu.user_name)
  FROM (SELECT 1) one
  LEFT JOIN fnd_customers cu ON p.source_table = 'fnd_customers' AND cu.customer_id = p.entity_id
  LEFT JOIN fnd_users uc ON uc.user_id = p.created_by
  LEFT JOIN fnd_users uu ON uu.user_id = p.updated_by
$function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_json(bps.fnd_contacts, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.org_contact_json(bps.fnd_contacts, boolean) TO service_role, bps_dev;
