-- ============================================================
-- ar_invoices_mark_printed
-- Records that invoices were printed (Print Invoices): sets printed_at = now() on the given invoices of the company.
-- Used by the health check invoices_need_reprint (a memo made after the last print). Staff only.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_invoices_mark_printed(p_tenant_id bigint, p_ar_transaction_ids bigint[])
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_n integer;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can print invoices';
    END IF;
    UPDATE ar_transactions SET printed_at = now()
     WHERE tenant_id = p_tenant_id AND transaction_type = 'INV' AND ar_transaction_id = ANY (p_ar_transaction_ids);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$function$;
