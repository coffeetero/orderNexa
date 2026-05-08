-- ============================================================
-- om_orders_save
-- Atomically saves an order header + lines.
--
-- Behavior:
--   - p_order_id IS NULL     -> create order header
--   - p_order_id IS NOT NULL -> update existing order header
--   - p_action = 'delete'    -> delete order (explicit path kept for compatibility)
--
-- p_payload (JSONB for create/update):
--   {
--     "customer_id":      <bigint|null>,
--     "order_number":     <text>,          -- required for create; optional for update
--     "order_date":       <date string>,
--     "production_date":  <date string>,
--     "production_code":  <"AM"|"PM"|"SPECIAL">,
--     "department_event":   <text|null>,
--     "delivery_amount":  <numeric>,
--     "lines": [
--       {
--         "order_line_id":    <bigint|null>,
--         "client_temp_id":   <text|null>, -- echoed back in line_refs
--         "item_id":          <bigint|null>,
--         "item_description": <text>,
--         "quantity":         <numeric>,
--         "unit_price":       <numeric>,
--         "unit_discount":    <numeric>,
--         "is_sliced":        <bool>,
--         "is_wrapped":       <bool>,
--         "is_covered":       <bool>,
--       }, ...
--     ]
--   }
--
-- Returns: { success, order_id, order_number, mode, line_refs, message }
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_orders_save(
    p_tenant_id BIGINT,
    p_action    TEXT   DEFAULT NULL,
    p_order_id  BIGINT DEFAULT NULL,
    p_payload   JSONB  DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
    v_order_id     BIGINT;
    v_order_number TEXT;
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
    v_payload_customer_id BIGINT;
    v_order_customer_id   BIGINT;
    v_order_customer_name TEXT;
    v_production_date DATE;
    v_requires_gapless BOOLEAN;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- ── DELETE (explicit compatibility path) ────────────────────────────
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

        DELETE FROM om_orders
         WHERE order_id  = p_order_id
           AND tenant_id = p_tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order % not found for this tenant', p_order_id;
        END IF;
        RETURN jsonb_build_object(
            'success',      TRUE,
            'order_id',     p_order_id,
            'order_number', NULL,
            'message',      'Order deleted.'
        );
    END IF;

    -- p_payload required for create/update upsert
    IF p_payload IS NULL THEN
        RAISE EXCEPTION 'p_payload is required';
    END IF;

    v_production_date := NULLIF(TRIM(p_payload->>'production_date'), '')::DATE;

    v_payload_customer_id := NULLIF((p_payload->>'customer_id')::TEXT, 'null')::BIGINT;
    v_order_customer_id := v_payload_customer_id;

    IF v_payload_customer_id IS NOT NULL THEN
        SELECT
            CASE
                WHEN UPPER(TRIM(selected.customer_type)) = 'LOCATION'
                 AND selected.customer_parent_id IS NOT NULL
                THEN parent.customer_id
                ELSE selected.customer_id
            END,
            CASE
                WHEN UPPER(TRIM(selected.customer_type)) = 'LOCATION'
                 AND selected.customer_parent_id IS NOT NULL
                THEN parent.customer_name
                ELSE selected.customer_name
            END
          INTO v_order_customer_id, v_order_customer_name
          FROM fnd_customers selected
          LEFT JOIN fnd_customers parent
                 ON parent.tenant_id = selected.tenant_id
                AND parent.customer_id = selected.customer_parent_id
         WHERE selected.tenant_id = p_tenant_id
           AND selected.customer_id = v_payload_customer_id;
    END IF;

    -- ── HEADER UPSERT (id-driven, with order-number fallback) ───────────
    IF p_order_id IS NULL THEN
        v_order_number := TRIM(p_payload->>'order_number');
        IF v_order_number IS NULL OR v_order_number = '' OR v_order_number = 'New Order' THEN
            v_order_number := fnd_tenant_sequence_next(
                p_tenant_id,
                'order_number',
                COALESCE(v_production_date, CURRENT_DATE)
            );
        END IF;

        SELECT order_id INTO v_order_id
          FROM om_orders
         WHERE tenant_id = p_tenant_id
           AND order_number = v_order_number
         LIMIT 1;

        IF FOUND THEN
            UPDATE om_orders SET
                order_date      = NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                production_date = v_production_date,
                production_code = NULLIF(TRIM(p_payload->>'production_code'), ''),
                customer_id     = v_order_customer_id,
                customer_name   = v_order_customer_name,
                department_event  = CASE
                    WHEN p_payload ? 'department_event' THEN NULLIF(TRIM(p_payload->>'department_event'), '')
                    ELSE department_event
                END,
                snapshot_data   = COALESCE(p_payload->'snapshot_data', snapshot_data)
            WHERE order_id  = v_order_id
              AND tenant_id = p_tenant_id;
            v_mode := 'updated';
        ELSE
            INSERT INTO om_orders (
                order_number,
                order_date,
                production_date,
                production_code,
                quantity,
                amount,
                discount_amount,
                customer_id,
                customer_name,
                department_event,
                order_source,
                tenant_id,
                snapshot_data
            ) VALUES (
                v_order_number,
                NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                v_production_date,
                NULLIF(TRIM(p_payload->>'production_code'), ''),
                0,   -- updated below after lines
                0,
                0,
                v_order_customer_id,
                v_order_customer_name,
                NULLIF(TRIM(p_payload->>'department_event'), ''),
                'Clerk',
                p_tenant_id,
                COALESCE(p_payload->'snapshot_data', '{}'::JSONB)
            )
            RETURNING order_id INTO v_order_id;
            v_mode := 'created';
        END IF;
    ELSE
        v_order_id := p_order_id;

        UPDATE om_orders SET
            order_number    = COALESCE(NULLIF(TRIM(p_payload->>'order_number'), ''), order_number),
            order_date      = NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
            production_date = v_production_date,
            production_code = NULLIF(TRIM(p_payload->>'production_code'), ''),
            customer_id     = v_order_customer_id,
            customer_name   = v_order_customer_name,
            department_event  = CASE
                WHEN p_payload ? 'department_event' THEN NULLIF(TRIM(p_payload->>'department_event'), '')
                ELSE department_event
            END
        WHERE order_id  = v_order_id
          AND tenant_id = p_tenant_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order % not found for this tenant', v_order_id;
        END IF;
        v_mode := 'updated';
    END IF;

    -- ── LINES UPSERT (id-driven by order_line_id) ───────────────────────
    FOR v_line IN SELECT jsonb_array_elements(COALESCE(p_payload->'lines', '[]'::JSONB))
    LOOP
        v_qty      := COALESCE((v_line->>'quantity')::NUMERIC,     0);
        v_price    := COALESCE((v_line->>'unit_price')::NUMERIC,   0);
        v_discount := COALESCE((v_line->>'unit_discount')::NUMERIC,0);
        v_extended := v_qty * (v_price - v_discount);

        v_line_id := NULLIF((v_line->>'order_line_id')::TEXT, 'null')::BIGINT;

        IF v_line_id IS NULL THEN
            INSERT INTO om_order_lines (
                order_id,
                item_id,
                item_description,
                quantity,
                unit_price,
                unit_discount,
                extended_amount,
                is_sliced,
                is_wrapped,
                is_covered,
                tenant_id
            ) VALUES (
                v_order_id,
                NULLIF((v_line->>'item_id')::TEXT, 'null')::BIGINT,
                COALESCE(TRIM(v_line->>'item_description'), ''),
                v_qty,
                v_price,
                v_discount,
                v_extended,
                COALESCE((v_line->>'is_sliced')::BOOLEAN,  FALSE),
                COALESCE((v_line->>'is_wrapped')::BOOLEAN, FALSE),
                COALESCE((v_line->>'is_covered')::BOOLEAN, FALSE),
                p_tenant_id
            )
            RETURNING order_line_id INTO v_line_id;
        ELSE
            UPDATE om_order_lines
               SET item_id = NULLIF((v_line->>'item_id')::TEXT, 'null')::BIGINT,
                   item_description = COALESCE(TRIM(v_line->>'item_description'), ''),
                   quantity = v_qty,
                   unit_price = v_price,
                   unit_discount = v_discount,
                   extended_amount = v_extended,
                   is_sliced = COALESCE((v_line->>'is_sliced')::BOOLEAN, FALSE),
                   is_wrapped = COALESCE((v_line->>'is_wrapped')::BOOLEAN, FALSE),
                   is_covered = COALESCE((v_line->>'is_covered')::BOOLEAN, FALSE)
             WHERE order_line_id = v_line_id
               AND order_id = v_order_id
               AND tenant_id = p_tenant_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Order line % not found for order % and tenant %',
                    v_line_id, v_order_id, p_tenant_id;
            END IF;
        END IF;

        v_line_refs := v_line_refs || jsonb_build_array(
            jsonb_build_object(
                'client_temp_id', NULLIF(TRIM(v_line->>'client_temp_id'), ''),
                'order_line_id', v_line_id
            )
        );

        v_total_qty  := v_total_qty  + v_qty;
        v_total_amt  := v_total_amt  + v_extended;
        v_total_disc := v_total_disc + (v_qty * v_discount);
    END LOOP;

    -- Remove persisted lines omitted from payload (full-state save contract).
    IF jsonb_array_length(COALESCE(p_payload->'lines', '[]'::JSONB)) = 0 THEN
        DELETE FROM om_order_lines
         WHERE order_id = v_order_id
           AND tenant_id = p_tenant_id;
        GET DIAGNOSTICS v_deleted_line_count = ROW_COUNT;
    ELSE
        DELETE FROM om_order_lines l
         WHERE l.order_id = v_order_id
           AND l.tenant_id = p_tenant_id
           AND NOT EXISTS (
                SELECT 1
                  FROM jsonb_array_elements(v_line_refs) r
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
        SELECT order_number INTO v_order_number
          FROM om_orders WHERE order_id = v_order_id;
    END IF;

    RETURN jsonb_build_object(
        'success',      TRUE,
        'order_id',     v_order_id,
        'order_number', v_order_number,
        'mode',         v_mode,
        'line_refs',    v_line_refs,
        'deleted_lines', v_deleted_line_count,
        'message',      'Order saved.'
    );

EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Order number % already exists for this tenant.', v_order_number;
END;
$$;
