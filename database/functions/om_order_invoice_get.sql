-- ============================================================
-- om_order_invoice_get
-- The invoice an order is on, for Order Entry: { invoice_number, invoice_status } where invoice_status is
-- ISSUED (numbered by the Packaging List), DRAFT (run processed, number not given yet) or NONE (not on an invoice).
-- Cancelled invoices are ignored. invoice_number is set only when ISSUED.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_order_invoice_get(p_tenant_id bigint, p_order_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT COALESCE(
        (SELECT jsonb_build_object(
                    'invoice_number', CASE WHEN t.status = 'DRAFT' THEN NULL ELSE t.document_number END,
                    'invoice_status', CASE WHEN t.status = 'DRAFT' THEN 'DRAFT' ELSE 'ISSUED' END)
           FROM ar_transaction_lines l
           JOIN ar_transactions t ON t.ar_transaction_id = l.ar_transaction_id
          WHERE l.tenant_id = p_tenant_id AND l.order_id = p_order_id
            AND t.transaction_type = 'INV' AND t.status <> 'CANCELLED'
          ORDER BY (t.status = 'DRAFT'), t.ar_transaction_id DESC
          LIMIT 1),
        jsonb_build_object('invoice_number', NULL, 'invoice_status', 'NONE'));
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_order_invoice_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_order_invoice_get(bigint, bigint) TO authenticated, service_role;
