-- ============================================================
-- org_contact_check
-- Internal: checks the caller may act on a contact in Organizer › Contacts and returns it.
-- p_action: 'R' read, 'W' write, 'D' delete (organizer.contacts access). p_contact_id NULL checks access only.
-- Visible: person contacts of the company (source_table fnd_tenants) and of the customers in the caller's scope.
-- Called only from the SECURITY DEFINER org_contact* functions; app users cannot execute it.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_contact_check(p_tenant_id bigint, p_contact_id bigint, p_action text)
RETURNS bps.fnd_contacts
LANGUAGE plpgsql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v bps.fnd_contacts;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('organizer.contacts', p_action) THEN
    RAISE EXCEPTION 'You do not have access to % contacts',
      CASE upper(p_action) WHEN 'R' THEN 'view' WHEN 'D' THEN 'delete' ELSE 'edit' END USING ERRCODE = '42501';
  END IF;
  IF p_contact_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v FROM fnd_contacts c WHERE c.tenant_id = p_tenant_id AND c.contact_id = p_contact_id AND c.contact_type = 'PERSON';
  IF NOT FOUND
     OR NOT ((v.source_table = 'fnd_tenants' AND v.entity_id = p_tenant_id)
             OR (v.source_table = 'fnd_customers'
                 AND (bps.fnd_scope_is_all() OR v.entity_id = ANY (COALESCE(bps.fnd_scope_customer_ids(), '{}'::bigint[]))))) THEN
    RAISE EXCEPTION 'Contact not found';
  END IF;
  RETURN v;
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_contact_check(bigint, bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.org_contact_check(bigint, bigint, text) TO service_role, bps_dev;
