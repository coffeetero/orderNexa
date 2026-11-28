-- ============================================================
-- Health checks on accounts: no active Approved pricing book, no contact person, no address.
-- Replaces the versions in migration/add_health_checks.sql; the message starts with the customer's name (owner request 2026-11-28:
-- "Account" dropped, the check's own heading already says it). CREATE OR REPLACE keeps the existing grants.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_hc_accounts_without_pricebook(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', c.customer_name || ' has no active, Approved pricing book.', 'Assign a pricing book and approve it on the customer''s Pricing tab.',
         'CUSTOMER', c.customer_id, c.customer_id, '/customers?customer=' || c.customer_id
    FROM bps.fnd_customers c
   WHERE c.tenant_id = p_tenant_id AND c.customer_type = 'ACCOUNT' AND c.is_active
     AND NOT EXISTS (SELECT 1 FROM bps.fnd_customer_pricebooks cp WHERE cp.customer_id = c.customer_id AND cp.is_active AND cp.status = 'Approved')
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_accounts_without_contact(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', c.customer_name || ' has no contact person.', 'Add a contact on the customer''s Contacts tab.',
         'CUSTOMER', c.customer_id, c.customer_id, '/customers?customer=' || c.customer_id
    FROM bps.fnd_customers c
   WHERE c.tenant_id = p_tenant_id AND c.customer_type = 'ACCOUNT' AND c.is_active
     AND NOT EXISTS (SELECT 1 FROM bps.fnd_contacts k WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.entity_id = c.customer_id
                        AND k.is_active AND k.contact_type = 'PERSON')
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_accounts_without_address(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', c.customer_name || ' has no address.', 'Add an address on the customer''s Contacts tab.',
         'CUSTOMER', c.customer_id, c.customer_id, '/customers?customer=' || c.customer_id
    FROM bps.fnd_customers c
   WHERE c.tenant_id = p_tenant_id AND c.customer_type = 'ACCOUNT' AND c.is_active
     AND NOT EXISTS (SELECT 1 FROM bps.fnd_contacts k JOIN bps.fnd_contact_points cpt ON cpt.contact_id = k.contact_id AND cpt.type = 'ADDRESS' AND cpt.is_active
                      WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.entity_id = c.customer_id AND k.is_active)
$$;
