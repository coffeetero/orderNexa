-- ============================================================
-- om_orders_save
-- Atomically saves an order header + lines.
--
-- department_event defaulting (new orders only):
--   1. If department_event is passed in the payload → use it
--   2. Else if customer is DEPARTMENT → use the department's customer_name
--   3. Else → default to 'ORDER'
--
-- When department_event collides with an existing order for the same
-- slot (customer + production_date + production_code + department_event),
-- a suffix is appended: 'ORDER-01', 'KITCHEN-02', etc.
--
-- DEPARTMENT customers: order is stored under the parent customer_id.
-- (LOCATION type is no longer used — replaced by DEPARTMENT.)
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_orders_save(
    p_tenant_id bigint,
    p_action    text    DEFAULT NULL,
    p_order_id  bigint  DEFAULT NULL,
    p_payload   jsonb   DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_order_id     BIGINT;
    v_order_number TEXT;
    v_po_number    TEXT;
    v_mode         TEXT;
    v_line         JSONB;
    v_line_id      BIGINT;
    v_deleted_line_count INTEGER := 0;
    v_line_refs    JSONB := '[]'::JSONB;
    v_qty          NUMERIC(14,4);
    v_price        NUMERIC(14,4);
    v_discount     NUMERIC(14,4);
    v_extended     NUMERIC(14,4);
    v_total_qty    NUMERIC(14,4) := 0;
    v_total_amt    NUMERIC(14,4) := 0;
    v_total_disc   NUMERIC(14,4) := 0;
    v_payload_customer_id   BIGINT;
    v_order_customer_id     BIGINT;
    v_order_customer_name   TEXT;
    v_is_department         BOOLEAN := FALSE;
    v_payload_customer_name TEXT;
    v_production_date DATE;
    v_production_code TEXT;
    v_department_event TEXT;
    v_base_department_event TEXT;
    v_next_department_event_suffix INTEGER;
    v_requires_gapless BOOLEAN;
    v_constraint_name TEXT;
    v_has_po_number BOOLEAN := FALSE;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- ── DELETE ────────────────────────────────────────────────────────────
    IF LOWER(COALESCE(p_action, '')) = 'delete' THEN
        IF p_order_id IS NULL THEN
            RAISE EXCEPTION 'p_order_id is required for delete';
        END IF;
        v_requires_gapless := FALSE;
        SELECT COALESCE(seq.requires_gapless, FALSE)
          INTO v_requires_gapless
          FROM fnd_tenant_sequences seq
         WHERE seq.tenant_id = p_tenant_id
           AND seq.sequence_name = 'order_number';
        IF COALESCE(v_requires_gapless, FALSE) THEN
            RAISE EXCEPTION 'Order % cannot be deleted because this tenant requires gapless order numbers. Cancel or void the order instead.', p_order_id;
        END IF;
        DELETE FROM om_orders WHERE order_id = p_order_id AND tenant_id = p_tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order % not found for this tenant', p_order_id;
        END IF;
        RETURN jsonb_build_object('success', TRUE, 'order_id', p_order_id, 'order_number', NULL, 'message', 'Order deleted.');
    END IF;

    IF p_payload IS NULL THEN
        RAISE EXCEPTION 'p_payload is required';
    END IF;

    v_production_date  := NULLIF(TRIM(p_payload->>'production_date'), '')::DATE;
    v_production_code  := NULLIF(UPPER(TRIM(p_payload->>'production_code')), '');
    v_department_event := NULLIF(UPPER(TRIM(p_payload->>'department_event')), '');
    v_po_number        := NULLIF(TRIM(p_payload->>'po_number'), '');

    SELECT EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = 'bps'
           AND table_name = 'om_orders'
           AND column_name = 'po_number'
    ) INTO v_has_po_number;

    v_payload_customer_id := NULLIF((p_payload->>'customer_id')::TEXT, 'null')::BIGINT;
    v_order_customer_id   := v_payload_customer_id;

    -- ── Customer lookup: DEPARTMENT → store order under parent ───────────
    IF v_payload_customer_id IS NOT NULL THEN
        SELECT
            CASE
                WHEN UPPER(TRIM(selected.customer_type)) = 'DEPARTMENT'
                 AND selected.customer_parent_id IS NOT NULL
                THEN parent.customer_id
                ELSE selected.customer_id
            END,
            CASE
                WHEN UPPER(TRIM(selected.customer_type)) = 'DEPARTMENT'
                 AND selected.customer_parent_id IS NOT NULL
                THEN parent.customer_name
                ELSE selected.customer_name
            END,
            UPPER(TRIM(selected.customer_type)) = 'DEPARTMENT',
            selected.customer_name
          INTO v_order_customer_id, v_order_customer_name,
               v_is_department, v_payload_customer_name
          FROM fnd_customers selected
          LEFT JOIN fnd_customers parent
                 ON parent.tenant_id   = selected.tenant_id
                AND parent.customer_id = selected.customer_parent_id
         WHERE selected.tenant_id   = p_tenant_id
           AND selected.customer_id = v_payload_customer_id;
    END IF;

    -- ── Default department_event when not supplied in payload ─────────────
    -- 1. Passed in payload → already in v_department_event
    -- 2. Customer is DEPARTMENT → use department's own customer_name
    -- 3. Otherwise → 'ORDER'
    IF v_department_event IS NULL THEN
        v_department_event := CASE
            WHEN v_is_department THEN UPPER(TRIM(v_payload_customer_name))
            ELSE 'ORDER'
        END;
    END IF;

    -- ── HEADER INSERT (new order) ─────────────────────────────────────────
    IF p_order_id IS NULL THEN
        v_base_department_event := v_department_event;

        v_order_number := TRIM(p_payload->>'order_number');
        IF v_order_number IS NULL OR v_order_number = '' OR v_order_number = 'New Order' THEN
            v_order_number := fnd_tenant_sequence_next(
                p_tenant_id, 'order_number', COALESCE(v_production_date, CURRENT_DATE)
            );
        END IF;

        -- Check for collision; append suffix if needed
        IF EXISTS (
            SELECT 1 FROM om_orders existing
             WHERE existing.tenant_id       = p_tenant_id
               AND existing.customer_id    IS NOT DISTINCT FROM v_order_customer_id
               AND existing.production_date = v_production_date
               AND existing.production_code IS NOT DISTINCT FROM v_production_code
               AND existing.department_event = v_base_department_event
        ) THEN
            SELECT COALESCE(MAX(
                CASE
                    WHEN existing.department_event = v_base_department_event THEN 0
                    WHEN substring(existing.department_event FROM length(v_base_department_event) + 2) ~ '^[0-9]+$'
                    THEN substring(existing.department_event FROM length(v_base_department_event) + 2)::INTEGER
                    ELSE NULL
                END), 0) + 1
              INTO v_next_department_event_suffix
              FROM om_orders existing
             WHERE existing.tenant_id       = p_tenant_id
               AND existing.customer_id    IS NOT DISTINCT FROM v_order_customer_id
               AND existing.production_date = v_production_date
               AND existing.production_code IS NOT DISTINCT FROM v_production_code
               AND (existing.department_event = v_base_department_event
                    OR existing.department_event LIKE v_base_department_event || '-%');
            v_department_event := v_base_department_event || '-' || LPAD(v_next_department_event_suffix::TEXT, 2, '0');
        END IF;

        LOOP
            BEGIN
                IF v_has_po_number THEN
                    INSERT INTO om_orders (
                        order_number, po_number, order_date, production_date, production_code,
                        quantity, amount, discount_amount,
                        customer_id, customer_name, department_event,
                        order_source, tenant_id, snapshot_data
                    ) VALUES (
                        v_order_number,
                        v_po_number,
                        NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                        v_production_date, v_production_code,
                        0, 0, 0,
                        v_order_customer_id, v_order_customer_name,
                        v_department_event,
                        'Clerk', p_tenant_id,
                        COALESCE(p_payload->'snapshot_data', '{}'::JSONB)
                    )
                    RETURNING order_id INTO v_order_id;
                ELSE
                    INSERT INTO om_orders (
                        order_number, order_date, production_date, production_code,
                        quantity, amount, discount_amount,
                        customer_id, customer_name, department_event,
                        order_source, tenant_id, snapshot_data
                    ) VALUES (
                        v_order_number,
                        NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                        v_production_date, v_production_code,
                        0, 0, 0,
                        v_order_customer_id, v_order_customer_name,
                        v_department_event,
                        'Clerk', p_tenant_id,
                        COALESCE(p_payload->'snapshot_data', '{}'::JSONB)
                    )
                    RETURNING order_id INTO v_order_id;
                END IF;
                EXIT;
            EXCEPTION WHEN unique_violation THEN
                GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
                IF v_constraint_name <> 'uq_om_orders_slot_department_event' THEN RAISE; END IF;
                SELECT COALESCE(MAX(
                    CASE
                        WHEN existing.department_event = v_base_department_event THEN 0
                        WHEN substring(existing.department_event FROM length(v_base_department_event) + 2) ~ '^[0-9]+$'
                        THEN substring(existing.department_event FROM length(v_base_department_event) + 2)::INTEGER
                        ELSE NULL
                    END), 0) + 1
                  INTO v_next_department_event_suffix
                  FROM om_orders existing
                 WHERE existing.tenant_id       = p_tenant_id
                   AND existing.customer_id    IS NOT DISTINCT FROM v_order_customer_id
                   AND existing.production_date = v_production_date
                   AND existing.production_code IS NOT DISTINCT FROM v_production_code
                   AND (existing.department_event = v_base_department_event
                        OR existing.department_event LIKE v_base_department_event || '-%');
                v_department_event := v_base_department_event || '-' || LPAD(v_next_department_event_suffix::TEXT, 2, '0');
            END;
        END LOOP;
        v_mode := 'created';

    ELSE
        -- ── HEADER UPDATE ─────────────────────────────────────────────────
        v_order_id := p_order_id;
        IF v_has_po_number THEN
            UPDATE om_orders SET
                order_number     = COALESCE(NULLIF(TRIM(p_payload->>'order_number'), ''), order_number),
                po_number        = CASE WHEN p_payload ? 'po_number' THEN v_po_number ELSE po_number END,
                order_date       = NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                production_date  = v_production_date,
                production_code  = v_production_code,
                customer_id      = v_order_customer_id,
                customer_name    = v_order_customer_name,
                department_event = CASE
                    WHEN p_payload ? 'department_event' THEN v_department_event
                    ELSE department_event
                END
            WHERE order_id = v_order_id AND tenant_id = p_tenant_id;
        ELSE
            UPDATE om_orders SET
                order_number     = COALESCE(NULLIF(TRIM(p_payload->>'order_number'), ''), order_number),
                order_date       = NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                production_date  = v_production_date,
                production_code  = v_production_code,
                customer_id      = v_order_customer_id,
                customer_name    = v_order_customer_name,
                department_event = CASE
                    WHEN p_payload ? 'department_event' THEN v_department_event
                    ELSE department_event
                END
            WHERE order_id = v_order_id AND tenant_id = p_tenant_id;
        END IF;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order % not found for this tenant', v_order_id;
        END IF;
        v_mode := 'updated';
    END IF;

    -- ── LINES UPSERT ──────────────────────────────────────────────────────
    FOR v_line IN SELECT jsonb_array_elements(COALESCE(p_payload->'lines', '[]'::JSONB)) LOOP
        v_qty      := COALESCE((v_line->>'quantity')::NUMERIC,     0);
        v_price    := COALESCE((v_line->>'unit_price')::NUMERIC,   0);
        v_discount := COALESCE((v_line->>'unit_discount')::NUMERIC,0);
        v_extended := v_qty * (v_price - v_discount);
        v_line_id  := NULLIF((v_line->>'order_line_id')::TEXT, 'null')::BIGINT;

        IF v_line_id IS NULL THEN
            INSERT INTO om_order_lines (
                order_id, item_id, item_description,
                quantity, unit_price, unit_discount, extended_amount,
                prep_options, tenant_id
            ) VALUES (
                v_order_id,
                NULLIF((v_line->>'item_id')::TEXT, 'null')::BIGINT,
                COALESCE(TRIM(v_line->>'item_description'), ''),
                v_qty, v_price, v_discount, v_extended,
                COALESCE(v_line->'prep_options', '[]'::JSONB),
                p_tenant_id
            )
            RETURNING order_line_id INTO v_line_id;
        ELSE
            UPDATE om_order_lines SET
                item_id          = NULLIF((v_line->>'item_id')::TEXT, 'null')::BIGINT,
                item_description = COALESCE(TRIM(v_line->>'item_description'), ''),
                quantity         = v_qty,
                unit_price       = v_price,
                unit_discount    = v_discount,
                extended_amount  = v_extended,
                prep_options     = COALESCE(v_line->'prep_options', '[]'::JSONB)
            WHERE order_line_id = v_line_id
              AND order_id      = v_order_id
              AND tenant_id     = p_tenant_id;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Order line % not found for order % and tenant %', v_line_id, v_order_id, p_tenant_id;
            END IF;
        END IF;

        v_line_refs  := v_line_refs || jsonb_build_array(jsonb_build_object(
            'client_temp_id', NULLIF(TRIM(v_line->>'client_temp_id'), ''),
            'order_line_id',  v_line_id
        ));
        v_total_qty  := v_total_qty  + v_qty;
        v_total_amt  := v_total_amt  + v_extended;
        v_total_disc := v_total_disc + (v_qty * v_discount);
    END LOOP;

    -- Remove lines omitted from payload (full-state save contract)
    IF jsonb_array_length(COALESCE(p_payload->'lines', '[]'::JSONB)) = 0 THEN
        DELETE FROM om_order_lines WHERE order_id = v_order_id AND tenant_id = p_tenant_id;
        GET DIAGNOSTICS v_deleted_line_count = ROW_COUNT;
    ELSE
        DELETE FROM om_order_lines l
         WHERE l.order_id  = v_order_id
           AND l.tenant_id = p_tenant_id
           AND NOT EXISTS (
                SELECT 1 FROM jsonb_array_elements(v_line_refs) r
                 WHERE (r->>'order_line_id')::BIGINT = l.order_line_id
           );
        GET DIAGNOSTICS v_deleted_line_count = ROW_COUNT;
    END IF;

    -- Update header rollups
    UPDATE om_orders SET
        quantity        = v_total_qty,
        amount          = v_total_amt,
        discount_amount = v_total_disc
    WHERE order_id = v_order_id;

    IF v_order_number IS NULL THEN
        SELECT order_number INTO v_order_number FROM om_orders WHERE order_id = v_order_id;
    END IF;

    RETURN jsonb_build_object(
        'success',          TRUE,
        'order_id',         v_order_id,
        'order_number',     v_order_number,
        'po_number',        v_po_number,
        'department_event', v_department_event,
        'mode',             v_mode,
        'line_refs',        v_line_refs,
        'deleted_lines',    v_deleted_line_count,
        'message',          'Order saved.'
    );

EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
    IF v_constraint_name = 'uq_om_orders_slot_department_event' THEN
        RAISE EXCEPTION 'An order already exists for this customer, production date, production code, and Department/Event.';
    END IF;
    RAISE EXCEPTION 'Order number % already exists for this tenant.', v_order_number;
END;
$function$;
