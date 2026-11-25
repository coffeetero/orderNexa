-- ============================================================
-- fnd_customer_import_upload
-- Customers > Import Customers, step 1: stores an uploaded file and checks it (fnd_customer_import_validate). Nothing
-- changes in the customers until fnd_customer_import_apply.
-- p_payload: { file_name, rows: [{ customer_number, customer_name, customer_type, parent_number, is_active, ... }] }
--   data rows only, in file order, keyed like fnd_customer_export_get; values as text. At most 5,000 rows.
-- The caller's earlier imports that were never applied are removed. Staff with write access to Import Customers who
-- can see all customers. Returns fnd_customer_import_get.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_customer_import_upload(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_actor  bigint := bps.fnd_nav_app_user_id();
    v_rows   jsonb  := COALESCE(p_payload -> 'rows', '[]'::jsonb);
    v_import bigint;
    v_keys   text[] := ARRAY['customer_number', 'customer_name', 'customer_type', 'parent_number', 'is_active', 'billing_type', 'billing_period',
                             'credit_limit', 'delivery_method', 'cutoff_extra_minutes', 'invoice_copy_count', 'is_standing_order',
                             'is_signature_required', 'is_label_required', 'is_invoice_required', 'is_cost_on_invoice',
                             'is_cost_on_bill_of_lading', 'is_returns_allowed', 'billing_address', 'shipping_address', 'phone', 'email', 'pricebook'];
BEGIN
    PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    IF NOT bps.fnd_has_access('customers.import', 'W') THEN
        RAISE EXCEPTION 'You do not have access to Import Customers' USING ERRCODE = '42501';
    END IF;
    IF NOT bps.fnd_scope_is_all() THEN
        RAISE EXCEPTION 'Importing customers needs access to all customers' USING ERRCODE = '42501';
    END IF;
    IF jsonb_typeof(v_rows) <> 'array' OR jsonb_array_length(v_rows) = 0 THEN
        RAISE EXCEPTION 'The file has no rows';
    END IF;
    IF jsonb_array_length(v_rows) > 5000 THEN
        RAISE EXCEPTION 'The file has more than 5,000 rows';
    END IF;

    DELETE FROM fnd_customer_imports WHERE tenant_id = p_tenant_id AND import_status = 'PREVIEW' AND created_by IS NOT DISTINCT FROM v_actor;

    INSERT INTO fnd_customer_imports (tenant_id, file_name, created_by, updated_by)
    VALUES (p_tenant_id, left(NULLIF(btrim(p_payload ->> 'file_name'), ''), 200), v_actor, v_actor)
    RETURNING customer_import_id INTO v_import;

    INSERT INTO fnd_customer_import_rows (tenant_id, customer_import_id, row_number, data, created_by, updated_by)
    SELECT p_tenant_id, v_import, x.ord::int,
           COALESCE((SELECT jsonb_object_agg(k, left(x.r ->> k, 2000)) FROM unnest(v_keys) k WHERE x.r ? k), '{}'::jsonb),
           v_actor, v_actor
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS x(r, ord);

    PERFORM bps.fnd_customer_import_validate(p_tenant_id, v_import);
    RETURN bps.fnd_customer_import_get(p_tenant_id, v_import);
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_customer_import_upload(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_customer_import_upload(bigint, jsonb) TO authenticated, service_role, bps_dev;
