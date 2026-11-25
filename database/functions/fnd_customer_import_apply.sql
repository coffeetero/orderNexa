-- ============================================================
-- fnd_customer_import_apply
-- Customers > Import Customers, step 2: checks the rows again against the current customers, then inserts the NEW
-- customers and updates the CHANGED ones (never deletes). Parents go first (by depth in the file, then ACCOUNT, SITE,
-- DEPARTMENT, then file order). Addresses, phone and email are written to the customer's Billing & Shipping contact
-- (created when missing): an existing contact point is updated, a missing one added. top_customer_id is recomputed.
-- When the fresh check finds errors nothing is applied and the refreshed preview is returned with applied = false.
-- Refused when already applied. Same access as upload.
-- Returns fnd_customer_import_get plus applied, inserted, updated.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_customer_import_apply(p_tenant_id bigint, p_customer_import_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_actor    bigint := bps.fnd_nav_app_user_id();
    v_imp      fnd_customer_imports%ROWTYPE;
    r          record;
    v          jsonb;      -- canonical file values of the row
    v_id       bigint;
    v_parent   bigint;
    v_contact  bigint;
    v_inserted int := 0;
    v_updated  int := 0;
    v_flag     text;
BEGIN
    PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    IF NOT bps.fnd_has_access('customers.import', 'W') THEN
        RAISE EXCEPTION 'You do not have access to Import Customers' USING ERRCODE = '42501';
    END IF;
    IF NOT bps.fnd_scope_is_all() THEN
        RAISE EXCEPTION 'Importing customers needs access to all customers' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_imp FROM fnd_customer_imports WHERE tenant_id = p_tenant_id AND customer_import_id = p_customer_import_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Import not found'; END IF;
    IF v_imp.import_status = 'APPLIED' THEN RAISE EXCEPTION 'This import is already applied'; END IF;

    PERFORM bps.fnd_customer_import_validate(p_tenant_id, p_customer_import_id);
    IF EXISTS (SELECT 1 FROM fnd_customer_import_rows WHERE customer_import_id = p_customer_import_id AND row_action = 'ERROR') THEN
        RETURN bps.fnd_customer_import_get(p_tenant_id, p_customer_import_id)
            || jsonb_build_object('applied', false, 'message', 'The customers changed since the preview and some rows now have errors; nothing was applied.');
    END IF;

    FOR r IN SELECT * FROM fnd_customer_import_rows
              WHERE customer_import_id = p_customer_import_id AND row_action IN ('NEW', 'CHANGED')
              ORDER BY hierarchy_depth, CASE upper(btrim(data ->> 'customer_type')) WHEN 'ACCOUNT' THEN 0 WHEN 'SITE' THEN 1 ELSE 2 END, row_number LOOP
        SELECT jsonb_object_agg(k, bps.fnd_customer_import_value(k, r.data ->> k)) INTO v FROM jsonb_object_keys(r.data) k;
        v_parent := (SELECT customer_id FROM fnd_customers WHERE tenant_id = p_tenant_id AND customer_number = r.parent_number);

        IF r.row_action = 'NEW' THEN
            INSERT INTO fnd_customers (tenant_id, customer_parent_id, customer_name, customer_number, customer_type, billing_type, billing_period,
                                       credit_limit, delivery_method_code, cutoff_extra_minutes, invoice_copy_count, is_active, is_standing_order,
                                       is_signature_required, is_label_required, is_invoice_required, is_cost_on_invoice, is_cost_on_bill_of_lading,
                                       is_returns_allowed, created_by, updated_by)
            VALUES (p_tenant_id, v_parent, v ->> 'customer_name', r.customer_number, v ->> 'customer_type', v ->> 'billing_type', v ->> 'billing_period',
                    (v ->> 'credit_limit')::numeric, v ->> 'delivery_method', (v ->> 'cutoff_extra_minutes')::int,
                    COALESCE((v ->> 'invoice_copy_count')::int, 1),
                    COALESCE((v ->> 'is_active') = 'Y', true), COALESCE((v ->> 'is_standing_order') = 'Y', false),
                    COALESCE((v ->> 'is_signature_required') = 'Y', false), COALESCE((v ->> 'is_label_required') = 'Y', false),
                    COALESCE((v ->> 'is_invoice_required') = 'Y', false), COALESCE((v ->> 'is_cost_on_invoice') = 'Y', false),
                    COALESCE((v ->> 'is_cost_on_bill_of_lading') = 'Y', false), COALESCE((v ->> 'is_returns_allowed') = 'Y', true),
                    v_actor, v_actor)
            RETURNING customer_id INTO v_id;
            INSERT INTO fnd_contacts (tenant_id, entity_id, source_table, card_name, contact_type, is_primary, is_active, created_by, updated_by)
            VALUES (p_tenant_id, v_id, 'fnd_customers', 'Billing & Shipping', 'ADDRESSES', false, true, v_actor, v_actor)
            RETURNING contact_id INTO v_contact;
            v_inserted := v_inserted + 1;
        ELSE
            v_id := r.customer_id;
            UPDATE fnd_customers c SET
                   customer_name        = v ->> 'customer_name',
                   customer_type        = v ->> 'customer_type',
                   customer_parent_id   = v_parent,
                   billing_type         = v ->> 'billing_type',
                   billing_period       = v ->> 'billing_period',
                   credit_limit         = (v ->> 'credit_limit')::numeric,
                   delivery_method_code = v ->> 'delivery_method',
                   cutoff_extra_minutes = (v ->> 'cutoff_extra_minutes')::int,
                   invoice_copy_count   = COALESCE((v ->> 'invoice_copy_count')::int, c.invoice_copy_count),
                   is_active                 = COALESCE((v ->> 'is_active') = 'Y', c.is_active),
                   is_standing_order         = COALESCE((v ->> 'is_standing_order') = 'Y', c.is_standing_order),
                   is_signature_required     = COALESCE((v ->> 'is_signature_required') = 'Y', c.is_signature_required),
                   is_label_required         = COALESCE((v ->> 'is_label_required') = 'Y', c.is_label_required),
                   is_invoice_required       = COALESCE((v ->> 'is_invoice_required') = 'Y', c.is_invoice_required),
                   is_cost_on_invoice        = COALESCE((v ->> 'is_cost_on_invoice') = 'Y', c.is_cost_on_invoice),
                   is_cost_on_bill_of_lading = COALESCE((v ->> 'is_cost_on_bill_of_lading') = 'Y', c.is_cost_on_bill_of_lading),
                   is_returns_allowed        = COALESCE((v ->> 'is_returns_allowed') = 'Y', c.is_returns_allowed),
                   updated_by = v_actor
             WHERE c.tenant_id = p_tenant_id AND c.customer_id = v_id;
            v_contact := (r.current_data ->> 'addresses_contact_id')::bigint;
            v_updated := v_updated + 1;
        END IF;

        -- contact values: only those given in the file that differ (new customer: those given)
        CONTINUE WHEN NOT EXISTS (SELECT 1 FROM unnest(ARRAY['billing_address', 'shipping_address', 'phone', 'email']) k
                                   WHERE v ->> k IS NOT NULL AND (v ->> k) IS DISTINCT FROM bps.fnd_customer_import_value(k, r.current_data ->> k));
        IF v_contact IS NULL THEN
            INSERT INTO fnd_contacts (tenant_id, entity_id, source_table, card_name, contact_type, is_primary, is_active, created_by, updated_by)
            VALUES (p_tenant_id, v_id, 'fnd_customers', 'Billing & Shipping', 'ADDRESSES', false, true, v_actor, v_actor)
            RETURNING contact_id INTO v_contact;
        END IF;

        IF v ->> 'billing_address' IS NOT NULL AND (v ->> 'billing_address') IS DISTINCT FROM bps.fnd_customer_import_value('billing_address', r.current_data ->> 'billing_address') THEN
            IF r.current_data ->> 'billing_point_id' IS NOT NULL THEN
                UPDATE fnd_contact_points SET value = v ->> 'billing_address', updated_by = v_actor
                 WHERE contact_point_id = (r.current_data ->> 'billing_point_id')::bigint;
            ELSE
                INSERT INTO fnd_contact_points (tenant_id, contact_id, type, value, label, sequence, is_primary, use_as_shipping, created_by, updated_by)
                VALUES (p_tenant_id, v_contact, 'ADDRESS', v ->> 'billing_address', 'Billing', 1, true,
                        r.current_data ->> 'shipping_point_id' IS NULL AND v ->> 'shipping_address' IS NULL, v_actor, v_actor);
            END IF;
        END IF;
        IF v ->> 'shipping_address' IS NOT NULL AND (v ->> 'shipping_address') IS DISTINCT FROM bps.fnd_customer_import_value('shipping_address', r.current_data ->> 'shipping_address') THEN
            IF r.current_data ->> 'shipping_point_id' IS NOT NULL THEN
                UPDATE fnd_contact_points SET value = v ->> 'shipping_address', updated_by = v_actor
                 WHERE contact_point_id = (r.current_data ->> 'shipping_point_id')::bigint;
            ELSE
                UPDATE fnd_contact_points cp SET use_as_shipping = false, updated_by = v_actor
                  FROM fnd_contacts ct
                 WHERE ct.contact_id = cp.contact_id AND ct.tenant_id = p_tenant_id AND ct.source_table = 'fnd_customers' AND ct.entity_id = v_id
                   AND cp.type = 'ADDRESS' AND cp.use_as_shipping;
                INSERT INTO fnd_contact_points (tenant_id, contact_id, type, value, label, sequence, is_primary, use_as_shipping, created_by, updated_by)
                VALUES (p_tenant_id, v_contact, 'ADDRESS', v ->> 'shipping_address', 'Shipping', 2, false, true, v_actor, v_actor);
            END IF;
        END IF;
        FOREACH v_flag IN ARRAY ARRAY['phone', 'email'] LOOP
            CONTINUE WHEN v ->> v_flag IS NULL OR (v ->> v_flag) IS NOT DISTINCT FROM bps.fnd_customer_import_value(v_flag, r.current_data ->> v_flag);
            IF r.current_data ->> (v_flag || '_point_id') IS NOT NULL THEN
                UPDATE fnd_contact_points SET value = v ->> v_flag, updated_by = v_actor
                 WHERE contact_point_id = (r.current_data ->> (v_flag || '_point_id'))::bigint;
            ELSE
                INSERT INTO fnd_contact_points (tenant_id, contact_id, type, value, label, sequence, is_primary, created_by, updated_by)
                VALUES (p_tenant_id, v_contact, upper(v_flag), v ->> v_flag, 'Main', 1, true, v_actor, v_actor);
            END IF;
        END LOOP;
    END LOOP;

    -- top of each customer's tree (as fnd_customers_save)
    WITH RECURSIVE tree AS (
        SELECT c.customer_id, c.customer_id AS top_id, ARRAY[c.customer_id] AS path
          FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_parent_id IS NULL
        UNION ALL
        SELECT c.customer_id, t.top_id, t.path || c.customer_id
          FROM fnd_customers c JOIN tree t ON c.customer_parent_id = t.customer_id
         WHERE c.tenant_id = p_tenant_id AND NOT c.customer_id = ANY (t.path)
    )
    UPDATE fnd_customers c SET top_customer_id = t.top_id
      FROM tree t WHERE c.customer_id = t.customer_id AND c.top_customer_id IS DISTINCT FROM t.top_id;

    UPDATE fnd_customer_imports SET import_status = 'APPLIED', applied_at = now(), applied_by = v_actor, updated_at = now(), updated_by = v_actor
     WHERE customer_import_id = p_customer_import_id;

    RETURN bps.fnd_customer_import_get(p_tenant_id, p_customer_import_id)
        || jsonb_build_object('applied', true, 'inserted', v_inserted, 'updated', v_updated);
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_customer_import_apply(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_customer_import_apply(bigint, bigint) TO authenticated, service_role, bps_dev;
