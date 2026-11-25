-- ============================================================
-- fnd_customer_import_get
-- One customer import: counts, status and its rows in file order
--   rows: [{ row_number, customer_number, customer_name, customer_type, parent_number, row_action, changes, issue }]
--   changes: [{ field, from, to }] (field = the export key)
-- Staff with read access to Import Customers.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_customer_import_get(p_tenant_id bigint, p_customer_import_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v jsonb;
BEGIN
    PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    IF NOT bps.fnd_has_access('customers.import', 'R') THEN
        RAISE EXCEPTION 'You do not have access to Import Customers' USING ERRCODE = '42501';
    END IF;
    SELECT jsonb_build_object(
             'customer_import_id', i.customer_import_id, 'file_name', i.file_name, 'import_status', i.import_status,
             'row_count', i.row_count, 'new_count', i.new_count, 'changed_count', i.changed_count,
             'unchanged_count', i.unchanged_count, 'error_count', i.error_count,
             'created_at', i.created_at, 'applied_at', i.applied_at,
             'rows', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                         'row_number', r.row_number, 'customer_number', COALESCE(r.customer_number, r.data ->> 'customer_number'),
                         'customer_name', r.data ->> 'customer_name', 'customer_type', r.data ->> 'customer_type',
                         'parent_number', COALESCE(r.parent_number, r.data ->> 'parent_number'),
                         'row_action', r.row_action, 'changes', COALESCE(r.changes, '[]'::jsonb), 'issue', r.issue) ORDER BY r.row_number)
                                 FROM fnd_customer_import_rows r WHERE r.customer_import_id = i.customer_import_id), '[]'::jsonb))
      INTO v
      FROM fnd_customer_imports i
     WHERE i.tenant_id = p_tenant_id AND i.customer_import_id = p_customer_import_id;
    IF v IS NULL THEN RAISE EXCEPTION 'Import not found'; END IF;
    RETURN v;
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_customer_import_get(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_customer_import_get(bigint, bigint) TO authenticated, service_role, bps_dev;
