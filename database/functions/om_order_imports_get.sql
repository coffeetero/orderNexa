-- ============================================================
-- om_order_imports_get
-- Imports with a production date in [p_from, p_to], newest first (without their rows).
-- Returns [{ order_import_id, customer_id, customer_name, customer_number, production_date, production_code, file_name,
--   import_status, row_count, order_count, error_count, warning_count, total_amount, created_at, approved_at }]
-- ============================================================
CREATE OR REPLACE FUNCTION bps.om_order_imports_get(p_tenant_id bigint, p_from date, p_to date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
    PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'order_import_id', i.order_import_id, 'customer_id', i.customer_id, 'customer_name', c.customer_name,
                 'customer_number', c.customer_number, 'production_date', i.production_date, 'production_code', i.production_code,
                 'file_name', i.file_name, 'import_status', i.import_status, 'row_count', i.row_count, 'order_count', i.order_count,
                 'error_count', i.error_count, 'warning_count', i.warning_count, 'total_amount', i.total_amount,
                 'created_at', i.created_at, 'approved_at', i.approved_at) ORDER BY i.production_date DESC, i.created_at DESC)
          FROM om_order_imports i JOIN fnd_customers c ON c.customer_id = i.customer_id
         WHERE i.tenant_id = p_tenant_id
           AND (p_from IS NULL OR i.production_date >= p_from) AND (p_to IS NULL OR i.production_date <= p_to)), '[]'::jsonb);
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.om_order_imports_get(bigint, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.om_order_imports_get(bigint, date, date) TO authenticated, service_role, bps_dev;
