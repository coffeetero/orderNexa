-- ============================================================
-- om_customer_invoice_owner
-- Which customer receives the invoice for an order placed by p_customer_id: the nearest ancestor-or-self that is an
-- ACCOUNT, or a SITE with is_invoice_required (a location with its own invoice, as in the old BPS). A DEPARTMENT never
-- owns an invoice: it is billed with its site or account. Falls back to the top ancestor.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_customer_invoice_owner(p_tenant_id bigint, p_customer_id bigint)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    WITH RECURSIVE up AS (
        SELECT c.customer_id, c.customer_parent_id, c.customer_type, c.is_invoice_required, 0 AS depth
          FROM fnd_customers c
         WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
        UNION ALL
        SELECT c.customer_id, c.customer_parent_id, c.customer_type, c.is_invoice_required, up.depth + 1
          FROM fnd_customers c
          JOIN up ON c.customer_id = up.customer_parent_id
         WHERE c.tenant_id = p_tenant_id AND up.depth < 10
    )
    SELECT COALESCE(
        (SELECT customer_id FROM up
          WHERE UPPER(TRIM(customer_type)) = 'ACCOUNT'
             OR (UPPER(TRIM(customer_type)) = 'SITE' AND is_invoice_required)
          ORDER BY depth LIMIT 1),
        (SELECT customer_id FROM up ORDER BY depth DESC LIMIT 1)
    );
$function$;
