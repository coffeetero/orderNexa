-- ============================================================
-- org_contact_duplicates_get
-- Possible duplicates in the caller's address book: groups of two or more active contacts sharing a name, email or
-- phone (org_contact_match_keys). Returns [{ match_type, match_value, contacts: [{contact_id, full_name, kind,
-- customer_name, company_name, updated_at}] }], names first, at most 200 groups.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_duplicates_get(p_tenant_id bigint)
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
    SELECT jsonb_agg(g.j ORDER BY g.ord, g.k)
      FROM (
        SELECT k.k, CASE split_part(k.k, ':', 1) WHEN 'name' THEN 0 WHEN 'email' THEN 1 ELSE 2 END AS ord,
               jsonb_build_object('match_type', split_part(k.k, ':', 1), 'match_value', substr(k.k, strpos(k.k, ':') + 1),
                 'contacts', jsonb_agg(jsonb_build_object('contact_id', c.contact_id, 'full_name', bps.fnd_contact_display_name(c),
                               'kind', CASE WHEN c.source_table = 'fnd_customers' THEN 'CUSTOMER' ELSE 'COMPANY' END,
                               'customer_name', cu.customer_name, 'company_name', c.company_name, 'updated_at', c.updated_at)
                             ORDER BY c.updated_at DESC)) AS j
          FROM fnd_contacts c
          LEFT JOIN fnd_customers cu ON c.source_table = 'fnd_customers' AND cu.customer_id = c.entity_id
          CROSS JOIN LATERAL unnest(bps.org_contact_match_keys(jsonb_build_object(
                   'first_name', c.first_name, 'last_name', c.last_name,
                   'points', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type', cp.type, 'value', cp.value)), '[]'::jsonb)
                                FROM fnd_contact_points cp WHERE cp.contact_id = c.contact_id AND cp.is_active)))) AS k(k)
         WHERE c.tenant_id = p_tenant_id AND c.contact_type = 'PERSON' AND c.is_active
           AND ((c.source_table = 'fnd_tenants' AND c.entity_id = p_tenant_id)
                OR (c.source_table = 'fnd_customers' AND (v_all OR c.entity_id = ANY (v_ids))))
         GROUP BY k.k
        HAVING count(DISTINCT c.contact_id) > 1
         ORDER BY 2, 1
         LIMIT 200
      ) g), '[]'::jsonb);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_duplicates_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contact_duplicates_get(bigint) TO authenticated, service_role, bps_dev;
