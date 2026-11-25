-- ============================================================
-- fnd_customer_export_rows
-- Internal (no app grant): the Import/Export Customers values of a tenant's customers (all, or p_customer_ids), with the
-- hierarchy sort key and the contact rows the values come from. Used by fnd_customer_export_get and the import functions,
-- so export and import read the same values.
--   data keys: customer_number, customer_name, customer_type, parent_number, is_active, billing_type, billing_period,
--     credit_limit, delivery_method, cutoff_extra_minutes, invoice_copy_count, is_standing_order, is_signature_required,
--     is_label_required, is_invoice_required, is_cost_on_invoice, is_cost_on_bill_of_lading, is_returns_allowed,
--     billing_address, shipping_address, phone, email, pricebook   (all text; flags Y/N)
--   billing_address  the active ADDRESS point labelled Billing (else the first one not labelled Shipping)
--   shipping_address the active ADDRESS point labelled Shipping (blank = deliver to the billing address)
--   phone / email    the customer's first active PHONE (or MOBILE) / EMAIL point, primary first
--   pricebook        the Default pricing book assignment in effect today (Approved, active)
-- sort_key: customer numbers from the top of the tree down (zero padded), so each parent sorts before its children.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_customer_export_rows(p_tenant_id bigint, p_customer_ids bigint[] DEFAULT NULL)
RETURNS TABLE (customer_id bigint, sort_key text[], addresses_contact_id bigint, billing_point_id bigint, shipping_point_id bigint,
               phone_point_id bigint, email_point_id bigint, data jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
    WITH RECURSIVE tree AS (
        SELECT c.customer_id, ARRAY[lpad(COALESCE(c.customer_number, ''), 20, '0')] AS path
          FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_parent_id IS NULL
        UNION ALL
        SELECT c.customer_id, t.path || lpad(COALESCE(c.customer_number, ''), 20, '0')
          FROM fnd_customers c JOIN tree t ON c.customer_parent_id = t.customer_id
         WHERE c.tenant_id = p_tenant_id AND cardinality(t.path) < 20
    ), pts AS (     -- the customers' active contact points, read once
        SELECT ct.entity_id AS customer_id, ct.is_active AS contact_active, ct.is_primary AS contact_primary,
               cp.contact_point_id, cp.type, cp.label, cp.value, cp.is_primary, cp.sequence
          FROM fnd_contacts ct JOIN fnd_contact_points cp ON cp.contact_id = ct.contact_id
         WHERE ct.tenant_id = p_tenant_id AND ct.source_table = 'fnd_customers' AND cp.is_active
           AND (p_customer_ids IS NULL OR ct.entity_id = ANY (p_customer_ids))
    ), bl AS (
        SELECT DISTINCT ON (customer_id) customer_id, contact_point_id, value FROM pts
         WHERE type = 'ADDRESS' AND COALESCE(label, '') NOT ILIKE 'shipping'
         ORDER BY customer_id, (label ILIKE 'billing') DESC, is_primary DESC, sequence, contact_point_id
    ), sh AS (
        SELECT DISTINCT ON (customer_id) customer_id, contact_point_id, value FROM pts
         WHERE type = 'ADDRESS' AND label ILIKE 'shipping'
         ORDER BY customer_id, is_primary DESC, sequence, contact_point_id
    ), ph AS (
        SELECT DISTINCT ON (customer_id) customer_id, contact_point_id, value FROM pts
         WHERE contact_active AND type IN ('PHONE', 'MOBILE')
         ORDER BY customer_id, is_primary DESC, contact_primary DESC, (type = 'PHONE') DESC, sequence, contact_point_id
    ), em AS (
        SELECT DISTINCT ON (customer_id) customer_id, contact_point_id, value FROM pts
         WHERE contact_active AND type = 'EMAIL'
         ORDER BY customer_id, is_primary DESC, contact_primary DESC, sequence, contact_point_id
    )
    SELECT c.customer_id, COALESCE(t.path, ARRAY[lpad(COALESCE(c.customer_number, ''), 20, '0')]),
           ad.contact_id, bl.contact_point_id, sh.contact_point_id, ph.contact_point_id, em.contact_point_id,
           jsonb_build_object(
             'customer_number', c.customer_number, 'customer_name', c.customer_name, 'customer_type', c.customer_type,
             'parent_number', p.customer_number,
             'is_active', CASE WHEN c.is_active THEN 'Y' ELSE 'N' END,
             'billing_type', c.billing_type, 'billing_period', c.billing_period, 'credit_limit', trim_scale(c.credit_limit)::text,
             'delivery_method', c.delivery_method_code, 'cutoff_extra_minutes', c.cutoff_extra_minutes::text,
             'invoice_copy_count', c.invoice_copy_count::text,
             'is_standing_order', CASE WHEN c.is_standing_order THEN 'Y' ELSE 'N' END,
             'is_signature_required', CASE WHEN c.is_signature_required THEN 'Y' ELSE 'N' END,
             'is_label_required', CASE WHEN c.is_label_required THEN 'Y' ELSE 'N' END,
             'is_invoice_required', CASE WHEN c.is_invoice_required THEN 'Y' ELSE 'N' END,
             'is_cost_on_invoice', CASE WHEN c.is_cost_on_invoice THEN 'Y' ELSE 'N' END,
             'is_cost_on_bill_of_lading', CASE WHEN c.is_cost_on_bill_of_lading THEN 'Y' ELSE 'N' END,
             'is_returns_allowed', CASE WHEN c.is_returns_allowed THEN 'Y' ELSE 'N' END,
             'billing_address', bl.value, 'shipping_address', sh.value, 'phone', ph.value, 'email', em.value,
             'pricebook', pb.pricebook_name)
      FROM fnd_customers c
      LEFT JOIN tree t ON t.customer_id = c.customer_id
      LEFT JOIN fnd_customers p ON p.customer_id = c.customer_parent_id
      LEFT JOIN LATERAL (SELECT ct.contact_id FROM fnd_contacts ct
                          WHERE ct.tenant_id = p_tenant_id AND ct.source_table = 'fnd_customers' AND ct.entity_id = c.customer_id
                            AND ct.contact_type = 'ADDRESSES'
                          ORDER BY ct.is_active DESC, ct.contact_id LIMIT 1) ad ON TRUE
      LEFT JOIN bl ON bl.customer_id = c.customer_id
      LEFT JOIN sh ON sh.customer_id = c.customer_id
      LEFT JOIN ph ON ph.customer_id = c.customer_id
      LEFT JOIN em ON em.customer_id = c.customer_id
      LEFT JOIN LATERAL (SELECT b.pricebook_name FROM fnd_customer_pricebooks a JOIN fnd_pricebooks b ON b.pricebook_id = a.pricebook_id
                          WHERE a.tenant_id = p_tenant_id AND a.customer_id = c.customer_id AND a.is_active AND a.status = 'Approved'
                            AND a.assignment_type = 'Default' AND a.effective_start_date <= CURRENT_DATE
                            AND (a.effective_end_date IS NULL OR a.effective_end_date >= CURRENT_DATE)
                          ORDER BY a.precedence DESC, a.effective_start_date DESC LIMIT 1) pb ON TRUE
     WHERE c.tenant_id = p_tenant_id AND (p_customer_ids IS NULL OR c.customer_id = ANY (p_customer_ids));
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_customer_export_rows(bigint, bigint[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.fnd_customer_export_rows(bigint, bigint[]) TO service_role, bps_dev;
