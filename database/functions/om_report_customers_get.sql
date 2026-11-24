-- ============================================================
-- om_report_customers_get
-- Customers to pick from on the Labels and Packaging pages, for production dates in [p_from, p_to] (and one production
-- code when given). Staff only.
--   p_basis 'ORDER'   : customers that have orders (the order's customer; a site's orders sit under its parent).
--   p_basis 'INVOICE' : invoice owners that have a DRAFT or OPEN invoice for a run in the range (process the run first).
--   p_basis 'PRINT'   : invoice owners with an issued invoice (not DRAFT/CANCELLED) for those production dates, migrated or
--                       BPS-made (Print Invoices; same selection as ar_invoices_print_get).
-- Returns [{ customer_id, customer_name, customer_number, document_count }] ordered by name.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_report_customers_get(p_tenant_id bigint, p_from date, p_to date, p_production_code text, p_basis text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code   text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_result jsonb;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can run reports';
    END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'A valid from date and to date are required';
    END IF;

    IF UPPER(COALESCE(p_basis, 'ORDER')) = 'PRINT' THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'customer_id', x.customer_id, 'customer_name', x.customer_name,
                   'customer_number', x.customer_number, 'document_count', x.n
               ) ORDER BY x.customer_name), '[]'::jsonb)
          INTO v_result
          FROM (
            SELECT c.customer_id, c.customer_name, c.customer_number, COUNT(DISTINCT t.ar_transaction_id) AS n
              FROM ar_transactions t
              JOIN fnd_customers c ON c.customer_id = t.customer_id AND c.tenant_id = t.tenant_id
              LEFT JOIN om_production_runs r ON r.production_run_id = t.production_run_id
             WHERE t.tenant_id = p_tenant_id AND t.transaction_type = 'INV' AND t.status NOT IN ('DRAFT', 'CANCELLED')
               AND t.transaction_date BETWEEN p_from - 14 AND p_to + 14
               AND (   (r.production_run_id IS NOT NULL AND r.production_date BETWEEN p_from AND p_to AND (v_code IS NULL OR r.production_code = v_code))
                    OR (t.production_run_id IS NULL AND EXISTS (
                          SELECT 1 FROM ar_transaction_lines l
                            LEFT JOIN om_shipment_lines sl ON sl.shipment_line_id = l.shipment_line_id
                            JOIN om_orders o ON o.order_id = COALESCE(l.order_id, sl.order_id)
                           WHERE l.ar_transaction_id = t.ar_transaction_id
                             AND o.production_date BETWEEN p_from AND p_to AND (v_code IS NULL OR o.production_code = v_code))))
             GROUP BY c.customer_id, c.customer_name, c.customer_number
          ) x;
    ELSIF UPPER(COALESCE(p_basis, 'ORDER')) = 'INVOICE' THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'customer_id', x.customer_id, 'customer_name', x.customer_name,
                   'customer_number', x.customer_number, 'document_count', x.n
               ) ORDER BY x.customer_name), '[]'::jsonb)
          INTO v_result
          FROM (
            SELECT c.customer_id, c.customer_name, c.customer_number, COUNT(*) AS n
              FROM ar_transactions t
              JOIN om_production_runs r ON r.production_run_id = t.production_run_id
              JOIN fnd_customers c ON c.customer_id = t.customer_id AND c.tenant_id = t.tenant_id
             WHERE t.tenant_id = p_tenant_id AND t.transaction_type = 'INV' AND t.status IN ('DRAFT', 'OPEN')
               AND r.production_date BETWEEN p_from AND p_to AND (v_code IS NULL OR r.production_code = v_code)
             GROUP BY c.customer_id, c.customer_name, c.customer_number
          ) x;
    ELSE
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'customer_id', x.customer_id, 'customer_name', x.customer_name,
                   'customer_number', x.customer_number, 'document_count', x.n
               ) ORDER BY x.customer_name), '[]'::jsonb)
          INTO v_result
          FROM (
            SELECT c.customer_id, c.customer_name, c.customer_number, COUNT(*) AS n
              FROM om_orders o
              JOIN fnd_customers c ON c.customer_id = o.customer_id AND c.tenant_id = o.tenant_id
             WHERE o.tenant_id = p_tenant_id AND o.production_date BETWEEN p_from AND p_to
               AND (v_code IS NULL OR o.production_code = v_code) AND COALESCE(o.import_status, 'APPROVED') = 'APPROVED'
             GROUP BY c.customer_id, c.customer_name, c.customer_number
          ) x;
    END IF;
    RETURN v_result;
END;
$function$;
