-- ============================================================
-- om_save_order
-- Atomically creates, updates, or deletes an order with its lines.
--
-- p_action:
--   'create' → INSERT order header + lines; p_order_id must be NULL.
--   'update' → UPDATE order header; replace all lines (DELETE + INSERT).
--              p_order_id must match an existing order for this tenant.
--   'delete' → DELETE order (lines cascade). p_order_id required.
--
-- p_payload (JSONB for create/update):
--   {
--     "customer_id":      <bigint|null>,
--     "order_number":     <text>,          -- required for create; ignored for update
--     "order_date":       <date string>,
--     "delivery_date":    <date string>,
--     "delivery_window":  <"AM"|"PM"|"SPECIAL">,
--     "delivery_amount":  <numeric>,
--     "lines": [
--       {
--         "item_id":         <bigint|null>,
--         "item_description":<text>,
--         "quantity":        <numeric>,
--         "unit_price":      <numeric>,
--         "unit_discount":   <numeric>,
--         "is_sliced":       <bool>,
--         "is_wrapped":      <bool>,
--         "is_covered":      <bool>,
--         "is_scored":       <bool>
--       }, ...
--     ]
--   }
--
-- Returns: { success, order_id, order_number, message }
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_save_order(
    p_tenant_id BIGINT,
    p_action    TEXT,
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
    v_line         JSONB;
    v_qty          NUMERIC(14,4);
    v_price        NUMERIC(14,4);
    v_discount     NUMERIC(14,4);
    v_extended     NUMERIC(14,4);
    v_total_qty    NUMERIC(14,4) := 0;
    v_total_amt    NUMERIC(14,4) := 0;
    v_total_disc   NUMERIC(14,4) := 0;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- ── DELETE ──────────────────────────────────────────────────────────
    IF p_action = 'delete' THEN
        IF p_order_id IS NULL THEN
            RAISE EXCEPTION 'p_order_id is required for delete';
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

    -- p_payload required for create/update
    IF p_payload IS NULL THEN
        RAISE EXCEPTION 'p_payload is required for action %', p_action;
    END IF;

    -- ── CREATE ──────────────────────────────────────────────────────────
    IF p_action = 'create' THEN
        v_order_number := TRIM(p_payload->>'order_number');
        IF v_order_number IS NULL OR v_order_number = '' THEN
            RAISE EXCEPTION 'order_number is required in payload for create';
        END IF;

        INSERT INTO om_orders (
            order_number,
            order_date,
            delivery_date,
            delivery_window,
            delivery_amount,
            quantity,
            amount,
            discount_amount,
            customer_id,
            order_source,
            tenant_id,
            snapshot_data
        ) VALUES (
            v_order_number,
            NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
            NULLIF(TRIM(p_payload->>'delivery_date'), '')::DATE,
            NULLIF(TRIM(p_payload->>'delivery_window'), ''),
            COALESCE((p_payload->>'delivery_amount')::NUMERIC, 0),
            0,   -- updated below after lines
            0,
            0,
            NULLIF((p_payload->>'customer_id')::TEXT, 'null')::BIGINT,
            'Clerk',
            p_tenant_id,
            COALESCE(p_payload->'snapshot_data', '{}'::JSONB)
        )
        RETURNING order_id INTO v_order_id;

    -- ── UPDATE ──────────────────────────────────────────────────────────
    ELSIF p_action = 'update' THEN
        IF p_order_id IS NULL THEN
            RAISE EXCEPTION 'p_order_id is required for update';
        END IF;
        v_order_id := p_order_id;

        UPDATE om_orders SET
            order_date      = NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
            delivery_date   = NULLIF(TRIM(p_payload->>'delivery_date'), '')::DATE,
            delivery_window = NULLIF(TRIM(p_payload->>'delivery_window'), ''),
            delivery_amount = COALESCE((p_payload->>'delivery_amount')::NUMERIC, 0),
            customer_id     = NULLIF((p_payload->>'customer_id')::TEXT, 'null')::BIGINT
        WHERE order_id  = v_order_id
          AND tenant_id = p_tenant_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order % not found for this tenant', v_order_id;
        END IF;

        -- Replace all lines
        DELETE FROM om_order_lines
         WHERE order_id  = v_order_id
           AND tenant_id = p_tenant_id;

        SELECT order_number INTO v_order_number
          FROM om_orders WHERE order_id = v_order_id;

    ELSE
        RAISE EXCEPTION 'Unknown action: %. Expected create, update, or delete.', p_action;
    END IF;

    -- ── Insert lines (shared by create and update) ───────────────────────
    FOR v_line IN SELECT jsonb_array_elements(COALESCE(p_payload->'lines', '[]'::JSONB))
    LOOP
        v_qty      := COALESCE((v_line->>'quantity')::NUMERIC,     0);
        v_price    := COALESCE((v_line->>'unit_price')::NUMERIC,   0);
        v_discount := COALESCE((v_line->>'unit_discount')::NUMERIC,0);
        v_extended := v_qty * (v_price - v_discount);

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
            is_scored,
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
            COALESCE((v_line->>'is_scored')::BOOLEAN,  FALSE),
            p_tenant_id
        );

        v_total_qty  := v_total_qty  + v_qty;
        v_total_amt  := v_total_amt  + v_extended;
        v_total_disc := v_total_disc + (v_qty * v_discount);
    END LOOP;

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
        'message',      'Order saved.'
    );

EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Order number % already exists for this tenant.', v_order_number;
END;
$$;
