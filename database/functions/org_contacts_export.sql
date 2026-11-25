-- ============================================================
-- org_contacts_export
-- Full contact details for a vCard / CSV export: the caller's visible active contacts, or only p_contact_ids when given
-- (the list as currently filtered). Photos are left out. Ordered as the address book.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contacts_export(p_tenant_id bigint, p_contact_ids bigint[] DEFAULT NULL)
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
    SELECT jsonb_agg(bps.org_contact_json(c, false)
                     ORDER BY lower(COALESCE(NULLIF(concat_ws(' ', NULLIF(btrim(c.last_name), ''), NULLIF(btrim(c.first_name), '')), ''),
                                             bps.fnd_contact_display_name(c))), c.contact_id)
      FROM fnd_contacts c
     WHERE c.tenant_id = p_tenant_id AND c.contact_type = 'PERSON' AND c.is_active
       AND (p_contact_ids IS NULL OR c.contact_id = ANY (p_contact_ids))
       AND ((c.source_table = 'fnd_tenants' AND c.entity_id = p_tenant_id)
            OR (c.source_table = 'fnd_customers' AND (v_all OR c.entity_id = ANY (v_ids))))), '[]'::jsonb);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contacts_export(bigint, bigint[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_contacts_export(bigint, bigint[]) TO authenticated, service_role, bps_dev;
