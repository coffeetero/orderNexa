-- ============================================================
-- om_production_runs_mark_printed
-- Stamps the print time of a report on the runs in [p_from, p_to] (one code when given): p_report is 'BAKER', 'LABELS' or
-- 'DELIVERY'. The Packaging List stamps itself inside om_report_packaging_issue. Staff only. Returns the runs stamped.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_production_runs_mark_printed(p_tenant_id bigint, p_from date, p_to date, p_production_code text, p_report text)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_code text := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_rep  text := UPPER(TRIM(p_report));
    v_n    integer;
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RAISE EXCEPTION 'Only tenant staff can record prints';
    END IF;
    IF v_rep NOT IN ('BAKER', 'LABELS', 'DELIVERY') THEN
        RAISE EXCEPTION 'Unknown report %', p_report;
    END IF;
    UPDATE om_production_runs r SET
        baker_sheet_printed_at = CASE WHEN v_rep = 'BAKER'    THEN now() ELSE baker_sheet_printed_at END,
        labels_printed_at      = CASE WHEN v_rep = 'LABELS'   THEN now() ELSE labels_printed_at END,
        delivery_printed_at    = CASE WHEN v_rep = 'DELIVERY' THEN now() ELSE delivery_printed_at END
     WHERE r.tenant_id = p_tenant_id AND r.production_date BETWEEN p_from AND p_to
       AND (v_code IS NULL OR r.production_code = v_code);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$function$;
