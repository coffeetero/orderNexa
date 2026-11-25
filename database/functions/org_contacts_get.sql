-- ============================================================
-- org_contacts_get
-- The address book list for Organizer › Contacts: active person contacts of the company and of the customers in the
-- caller's scope, with what the list shows and searches (names, company, customer, primary phone/email, tags).
-- sort_name orders and groups the list (last name, then first name, else the display name).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contacts_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_all boolean;
  v_ids bigint[];
BEGIN
  PERFORM bps.org_contact_check(p_tenant_id, NULL, 'R');
  v_all := bps.fnd_scope_is_all();
  v_ids := COALESCE(bps.fnd_scope_customer_ids(), '{}'::bigint[]);
  RETURN COALESCE((
    SELECT jsonb_agg(x.j || jsonb_build_object('sort_name', x.sort_name) ORDER BY x.sort_name, x.contact_id)
      FROM (
        SELECT c.contact_id,
               lower(COALESCE(NULLIF(concat_ws(' ', NULLIF(btrim(c.last_name), ''), NULLIF(btrim(c.first_name), '')), ''),
                              bps.fnd_contact_display_name(c))) AS sort_name,
               jsonb_build_object(
                 'contact_id', c.contact_id,
                 'full_name', bps.fnd_contact_display_name(c),
                 'first_name', c.first_name, 'last_name', c.last_name, 'nickname', c.nickname,
                 'company_name', c.company_name, 'job_title', c.job_title,
                 'is_favorite', c.is_favorite, 'has_photo', c.photo_data IS NOT NULL,
                 'kind', CASE WHEN c.source_table = 'fnd_customers' THEN 'CUSTOMER' ELSE 'COMPANY' END,
                 'customer_id', cu.customer_id, 'customer_name', cu.customer_name, 'customer_number', cu.customer_number,
                 'phone', (SELECT cp.value FROM fnd_contact_points cp WHERE cp.contact_id = c.contact_id AND cp.is_active
                              AND cp.type IN ('MOBILE', 'PHONE')
                            ORDER BY cp.is_primary DESC, cp.type = 'MOBILE' DESC, cp.sequence, cp.contact_point_id LIMIT 1),
                 'email', (SELECT cp.value FROM fnd_contact_points cp WHERE cp.contact_id = c.contact_id AND cp.is_active
                              AND cp.type = 'EMAIL' ORDER BY cp.is_primary DESC, cp.sequence, cp.contact_point_id LIMIT 1),
                 'search', lower(concat_ws(' ', bps.fnd_contact_display_name(c), c.nickname, c.company_name, c.job_title,
                              c.department, cu.customer_name, cu.customer_number,
                              (SELECT string_agg(cp.value || ' ' || regexp_replace(cp.value, '\D', '', 'g'), ' ')
                                 FROM fnd_contact_points cp WHERE cp.contact_id = c.contact_id AND cp.is_active AND cp.type <> 'NOTE'))),
                 'tag_ids', COALESCE((SELECT jsonb_agg(l.tag_id) FROM fnd_contact_tag_links l WHERE l.contact_id = c.contact_id), '[]'::jsonb),
                 'updated_at', c.updated_at) AS j
          FROM fnd_contacts c
          LEFT JOIN fnd_customers cu ON c.source_table = 'fnd_customers' AND cu.customer_id = c.entity_id
         WHERE c.tenant_id = p_tenant_id AND c.contact_type = 'PERSON' AND c.is_active
           AND ((c.source_table = 'fnd_tenants' AND c.entity_id = p_tenant_id)
                OR (c.source_table = 'fnd_customers' AND (v_all OR c.entity_id = ANY (v_ids))))
      ) x), '[]'::jsonb);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contacts_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contacts_get(bigint) TO authenticated, service_role, bps_dev;
