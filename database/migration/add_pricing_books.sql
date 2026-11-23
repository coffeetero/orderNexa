-- =====================================================================================
-- Pricing books. A customer account is assigned books (type Default / Seasonal / Promotional / Introductory) with from/to dates, an
-- active flag and a status. An assignment prices orders only when it is active, Approved and the order's DELIVERY date is inside its
-- range. Eligible books are tried strictly in the table order (precedence), item by item: an item missing from the first book falls
-- through to the next. Staff may add an item no book prices (after a prompt; the line is flagged unpriced); customers may not.
-- Changes: data - existing PRIMARY/Draft assignments become Default/Approved; new columns fnd_pricebooks.owner_customer_id
-- (a book made for one customer) and om_order_lines.is_unpriced; check constraints; approval guard; resolver functions;
-- om_items_get_v2 and om_orders_save use the resolver; Pricing Books functions; to-do list. Apply after add_dashboard_cards.sql.
-- =====================================================================================
SET search_path = bps, public;

UPDATE bps.fnd_customer_pricebooks SET assignment_type = 'Default' WHERE assignment_type = 'PRIMARY';
UPDATE bps.fnd_customer_pricebooks SET status = 'Approved' WHERE status = 'Draft';
ALTER TABLE bps.fnd_customer_pricebooks
  ADD CONSTRAINT chk_fnd_customer_pricebooks_type   CHECK (assignment_type IN ('Default','Seasonal','Promotional','Introductory')),
  ADD CONSTRAINT chk_fnd_customer_pricebooks_status CHECK (status IN ('Draft','Pending Approval','Approved','Archived'));
ALTER TABLE bps.fnd_pricebooks ADD COLUMN owner_customer_id BIGINT REFERENCES bps.fnd_customers(customer_id);
COMMENT ON COLUMN bps.fnd_pricebooks.owner_customer_id IS 'Set when the book was made for one customer (for example a Starbucks Pricing Book); it can still be assigned to other accounts.';
ALTER TABLE bps.om_order_lines ADD COLUMN is_unpriced BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN bps.om_order_lines.is_unpriced IS 'True when staff added the item although no pricing book priced it on the delivery date.';
UPDATE bps.fnd_areas SET area_name = 'Pricing Books' WHERE area_key = 'inventory.pricing';

-- Only people with Approve rights on pricing may approve an assignment.
CREATE OR REPLACE FUNCTION bps.fnd_customer_pricebooks_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path = bps, public AS $$
BEGIN
  IF NEW.status = 'Approved' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'Approved')
     AND NOT bps.fnd_is_trusted() AND NOT bps.fnd_has_access_any(ARRAY['customers.pricing','inventory.pricing'], 'A') THEN
    RAISE EXCEPTION 'Only a pricing approver can set an assignment to Approved';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION bps.fnd_customer_pricebooks_guard() FROM PUBLIC, anon;
CREATE TRIGGER trg_fnd_customer_pricebooks_guard BEFORE INSERT OR UPDATE ON bps.fnd_customer_pricebooks
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_customer_pricebooks_guard();

-- Delivery date of a production date and code (production date + the code's delivery days after).
CREATE OR REPLACE FUNCTION bps.om_delivery_date_calc(p_tenant_id bigint, p_production_date date, p_production_code text) RETURNS date
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT p_production_date + COALESCE((SELECT pc.delivery_days_after FROM bps.om_production_codes pc
     WHERE pc.tenant_id = p_tenant_id AND pc.production_code = upper(btrim(p_production_code))), 0)
$$;

-- {item_id: unit_price} for the items (all items when p_item_ids is NULL) that the customer's eligible books price on p_delivery_date.
-- The customer may be a site or department: the account's books apply.
CREATE OR REPLACE FUNCTION bps.fnd_item_prices_map(p_tenant_id bigint, p_customer_id bigint, p_delivery_date date, p_item_ids bigint[] DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_acc bigint; v_map jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  SELECT COALESCE(c.top_customer_id, c.customer_id) INTO v_acc FROM bps.fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id;
  IF v_acc IS NULL THEN RETURN '{}'::jsonb; END IF;
  WITH elig AS (
    SELECT cp.pricebook_id, row_number() OVER (ORDER BY cp.precedence, cp.customer_pricebook_id) AS rn
      FROM bps.fnd_customer_pricebooks cp JOIN bps.fnd_pricebooks pb ON pb.pricebook_id = cp.pricebook_id AND pb.is_active
     WHERE cp.tenant_id = p_tenant_id AND cp.customer_id = v_acc AND cp.is_active AND cp.status = 'Approved'
       AND cp.effective_start_date <= p_delivery_date AND (cp.effective_end_date IS NULL OR cp.effective_end_date >= p_delivery_date)
  ), hits AS (
    SELECT DISTINCT ON (i.item_id) i.item_id, i.item_price
      FROM elig e JOIN bps.fnd_pricebook_items i ON i.pricebook_id = e.pricebook_id AND i.tenant_id = p_tenant_id AND i.is_active AND i.item_price IS NOT NULL
     WHERE p_item_ids IS NULL OR i.item_id = ANY(p_item_ids)
     ORDER BY i.item_id, e.rn, i.min_quantity
  )
  SELECT COALESCE(jsonb_object_agg(item_id::text, item_price), '{}'::jsonb) INTO v_map FROM hits;
  RETURN v_map;
END $$;

DROP FUNCTION bps.om_items_get_v2(bigint, bigint, boolean);
CREATE OR REPLACE FUNCTION bps.om_items_get_v2(p_tenant_id bigint, p_customer_id bigint DEFAULT NULL::bigint, p_return_actives_only boolean DEFAULT true, p_production_date date DEFAULT NULL::date, p_production_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_prices       JSONB := '{}'::JSONB;
    v_result       JSONB;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- Prices come from the customer's pricing books for the delivery date (see fnd_item_prices_map).
    IF p_customer_id IS NOT NULL THEN
        v_prices := bps.fnd_item_prices_map(
            p_tenant_id, p_customer_id,
            bps.om_delivery_date_calc(p_tenant_id, COALESCE(p_production_date, CURRENT_DATE), p_production_code));
    END IF;

    SELECT jsonb_agg(row_data ORDER BY (row_data->>'item_number'))
      INTO v_result
      FROM (
        SELECT jsonb_build_object(
            'item_id',        i.item_id,
            'item_number',    COALESCE(i.item_number, ''),
            'item_name',      i.item_name,
            'category',       i.category,
            'unit_of_sale',   i.unit_of_sale,
            'allowed_prep_options', COALESCE(prep_allowed.allowed_prep_options, '[]'::JSONB),
            'default_prep_options', COALESCE(prep_default.default_prep_options, '[]'::JSONB),
            'is_scoreable',   FALSE,
            'default_scored', FALSE,
            'unit_price',     (v_prices ->> i.item_id::TEXT)::NUMERIC,
            'in_pricebook',   (v_prices ? i.item_id::TEXT)
        ) AS row_data
          FROM fnd_items i
          LEFT JOIN LATERAL (
                SELECT COALESCE(
                    jsonb_agg(
                        jsonb_build_object(
                            'value', vv.value,
                            'label', vv.label
                        )
                        ORDER BY vv.display_order, vv.label
                    ),
                    '[]'::JSONB
                ) AS allowed_prep_options
                  FROM jsonb_array_elements_text(COALESCE(i.allowed_prep_options, '[]'::JSONB)) opt(value)
                  JOIN fnd_valuesets vs
                    ON vs.tenant_id = i.tenant_id
                   AND vs.valueset_code = 'ITEMPREP'
                   AND vs.is_active = TRUE
                  JOIN fnd_valueset_values vv
                    ON vv.tenant_id = vs.tenant_id
                   AND vv.valueset_id = vs.valueset_id
                   AND vv.value = opt.value
                   AND vv.is_disabled = FALSE
              ) prep_allowed ON TRUE
          LEFT JOIN LATERAL (
                SELECT COALESCE(
                    jsonb_agg(
                        jsonb_build_object(
                            'value', vv.value,
                            'label', vv.label
                        )
                        ORDER BY vv.display_order, vv.label
                    ),
                    '[]'::JSONB
                ) AS default_prep_options
                  FROM jsonb_array_elements_text(COALESCE(i.default_prep_options, '[]'::JSONB)) opt(value)
                  JOIN fnd_valuesets vs
                    ON vs.tenant_id = i.tenant_id
                   AND vs.valueset_code = 'ITEMPREP'
                   AND vs.is_active = TRUE
                  JOIN fnd_valueset_values vv
                    ON vv.tenant_id = vs.tenant_id
                   AND vv.valueset_id = vs.valueset_id
                   AND vv.value = opt.value
                   AND vv.is_disabled = FALSE
              ) prep_default ON TRUE
         WHERE i.tenant_id  = p_tenant_id
           AND (NOT p_return_actives_only OR i.is_active = TRUE)
         LIMIT 2000
    ) sub;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$function$;

CREATE OR REPLACE FUNCTION bps.om_orders_save(p_tenant_id bigint, p_action text DEFAULT NULL::text, p_order_id bigint DEFAULT NULL::bigint, p_payload jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
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
    v_is_site               BOOLEAN := FALSE;
    v_payload_customer_name TEXT;
    v_production_date DATE;
    v_production_code TEXT;
    v_department_event TEXT;
    v_base_department_event TEXT;
    v_next_department_event_suffix INTEGER;
    v_requires_gapless BOOLEAN;
    v_constraint_name TEXT;
    v_has_po_number BOOLEAN := FALSE;
    v_delivery_charge NUMERIC(12,2);
    v_run_id        BIGINT;
    v_old_order     om_orders%ROWTYPE;
    v_staff         BOOLEAN;
    v_delivery_date DATE;
    v_resolved      NUMERIC;
    v_unpriced      BOOLEAN;
    v_old_line      om_order_lines%ROWTYPE;
    v_item_id       BIGINT;
BEGIN
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    -- ── DELETE ────────────────────────────────────────────────────────────
    IF LOWER(COALESCE(p_action, '')) = 'delete' THEN
        IF p_order_id IS NULL THEN
            RAISE EXCEPTION 'p_order_id is required for delete';
        END IF;
        SELECT * INTO v_old_order FROM om_orders WHERE order_id = p_order_id AND tenant_id = p_tenant_id;
        IF FOUND THEN
            PERFORM bps.om_production_cutoff_assert(p_tenant_id, v_old_order.production_date,
                                                    v_old_order.production_code, v_old_order.customer_id);
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
                WHEN UPPER(TRIM(selected.customer_type)) = 'SITE'
                 AND selected.customer_parent_id IS NOT NULL
                THEN parent.customer_id
                ELSE selected.customer_id
            END,
            CASE
                WHEN UPPER(TRIM(selected.customer_type)) = 'SITE'
                 AND selected.customer_parent_id IS NOT NULL
                THEN parent.customer_name
                ELSE selected.customer_name
            END,
            UPPER(TRIM(selected.customer_type)) = 'SITE',
            selected.customer_name
          INTO v_order_customer_id, v_order_customer_name,
               v_is_site, v_payload_customer_name
          FROM fnd_customers selected
          LEFT JOIN fnd_customers parent
                 ON parent.tenant_id   = selected.tenant_id
                AND parent.customer_id = selected.customer_parent_id
         WHERE selected.tenant_id   = p_tenant_id
           AND selected.customer_id = v_payload_customer_id;
    END IF;

    -- ── Cutoff: customers cannot enter or change orders for a run past its cutoff ──
    IF p_order_id IS NOT NULL THEN
        SELECT * INTO v_old_order FROM om_orders WHERE order_id = p_order_id AND tenant_id = p_tenant_id;
        IF FOUND THEN
            PERFORM bps.om_production_cutoff_assert(p_tenant_id, v_old_order.production_date,
                                                    v_old_order.production_code, v_old_order.customer_id);
        END IF;
    END IF;
    PERFORM bps.om_production_cutoff_assert(p_tenant_id, v_production_date, v_production_code, v_order_customer_id);
    v_run_id := bps.om_production_run_get_or_create(p_tenant_id, v_production_date, v_production_code);
    v_delivery_charge := COALESCE(NULLIF(TRIM(p_payload->>'delivery_amount'), '')::NUMERIC, 0);
    IF v_delivery_charge < 0 THEN
        RAISE EXCEPTION 'delivery_amount cannot be negative';
    END IF;

    -- ── Default department_event when not supplied in payload ─────────────
    -- The selected customer's own name (site name for a site, department name, account name); 'ORDER' without a customer.
    IF v_department_event IS NULL THEN
        v_department_event := COALESCE(NULLIF(UPPER(TRIM(v_payload_customer_name)), ''), 'ORDER');
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
                        order_source, tenant_id, snapshot_data,
                        delivery_charge, production_run_id
                    ) VALUES (
                        v_order_number,
                        v_po_number,
                        NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                        v_production_date, v_production_code,
                        0, 0, 0,
                        v_order_customer_id, v_order_customer_name,
                        v_department_event,
                        'Clerk', p_tenant_id,
                        COALESCE(p_payload->'snapshot_data', '{}'::JSONB),
                        v_delivery_charge, v_run_id
                    )
                    RETURNING order_id INTO v_order_id;
                ELSE
                    INSERT INTO om_orders (
                        order_number, order_date, production_date, production_code,
                        quantity, amount, discount_amount,
                        customer_id, customer_name, department_event,
                        order_source, tenant_id, snapshot_data,
                        delivery_charge, production_run_id
                    ) VALUES (
                        v_order_number,
                        NULLIF(TRIM(p_payload->>'order_date'), '')::DATE,
                        v_production_date, v_production_code,
                        0, 0, 0,
                        v_order_customer_id, v_order_customer_name,
                        v_department_event,
                        'Clerk', p_tenant_id,
                        COALESCE(p_payload->'snapshot_data', '{}'::JSONB),
                        v_delivery_charge, v_run_id
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
                production_run_id = v_run_id,
                delivery_charge  = CASE WHEN p_payload ? 'delivery_amount' THEN v_delivery_charge ELSE delivery_charge END,
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
                production_run_id = v_run_id,
                delivery_charge  = CASE WHEN p_payload ? 'delivery_amount' THEN v_delivery_charge ELSE delivery_charge END,
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
    -- Prices come from the customer's pricing books for the delivery date (precedence = table order, item by item).
    -- Staff may add an item no book prices (it is flagged unpriced); customers may not, and cannot change a price.
    v_staff := bps.fnd_is_tenant_staff(p_tenant_id);
    v_delivery_date := bps.om_delivery_date_calc(p_tenant_id, v_production_date, v_production_code);
    FOR v_line IN SELECT jsonb_array_elements(COALESCE(p_payload->'lines', '[]'::JSONB)) LOOP
        v_qty      := COALESCE((v_line->>'quantity')::NUMERIC,     0);
        v_price    := COALESCE((v_line->>'unit_price')::NUMERIC,   0);
        v_discount := COALESCE((v_line->>'unit_discount')::NUMERIC,0);
        v_extended := v_qty * (v_price - v_discount);
        v_line_id  := NULLIF((v_line->>'order_line_id')::TEXT, 'null')::BIGINT;
        v_item_id  := NULLIF((v_line->>'item_id')::TEXT, 'null')::BIGINT;
        v_unpriced := FALSE;
        v_old_line := NULL;
        IF v_line_id IS NOT NULL THEN
            SELECT * INTO v_old_line FROM om_order_lines WHERE order_line_id = v_line_id AND order_id = v_order_id AND tenant_id = p_tenant_id;
        END IF;

        IF v_item_id IS NOT NULL THEN
            IF v_old_line.order_line_id IS NOT NULL AND v_old_line.item_id IS NOT DISTINCT FROM v_item_id AND NOT v_staff THEN
                -- an unchanged line keeps the price it was entered with
                v_price := v_old_line.unit_price;
                v_unpriced := v_old_line.is_unpriced;
            ELSE
                v_resolved := (bps.fnd_item_prices_map(p_tenant_id, v_order_customer_id, v_delivery_date, ARRAY[v_item_id]) ->> v_item_id::TEXT)::NUMERIC;
                IF NOT v_staff THEN
                    IF v_resolved IS NULL THEN
                        RAISE EXCEPTION 'Item % is not priced in your pricing books and cannot be ordered', COALESCE(NULLIF(TRIM(v_line->>'item_description'), ''), v_item_id::TEXT);
                    END IF;
                    v_price := v_resolved;
                ELSIF v_resolved IS NULL THEN
                    v_unpriced := TRUE;
                END IF;
            END IF;
            v_extended := v_qty * (v_price - v_discount);
        END IF;

        IF v_line_id IS NULL THEN
            INSERT INTO om_order_lines (
                order_id, item_id, item_description,
                quantity, unit_price, unit_discount, extended_amount,
                prep_options, tenant_id, is_unpriced
            ) VALUES (
                v_order_id,
                NULLIF((v_line->>'item_id')::TEXT, 'null')::BIGINT,
                COALESCE(TRIM(v_line->>'item_description'), ''),
                v_qty, v_price, v_discount, v_extended,
                COALESCE(v_line->'prep_options', '[]'::JSONB),
                p_tenant_id, v_unpriced
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
                prep_options     = COALESCE(v_line->'prep_options', '[]'::JSONB),
                is_unpriced      = v_unpriced
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


-- ---------- Pricing Books screen ----------
CREATE OR REPLACE FUNCTION bps.fnd_pricebooks_list_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('pricebook_id', b.pricebook_id, 'pricebook_name', b.pricebook_name, 'description', b.description,
      'is_active', b.is_active, 'owner_customer_id', b.owner_customer_id, 'owner_customer_name', oc.customer_name,
      'item_count', (SELECT count(*) FROM bps.fnd_pricebook_items i WHERE i.pricebook_id = b.pricebook_id AND i.is_active),
      'assigned_count', (SELECT count(DISTINCT cp.customer_id) FROM bps.fnd_customer_pricebooks cp WHERE cp.pricebook_id = b.pricebook_id))
      ORDER BY b.pricebook_name), '[]'::jsonb)
    FROM bps.fnd_pricebooks b LEFT JOIN bps.fnd_customers oc ON oc.customer_id = b.owner_customer_id WHERE b.tenant_id = p_tenant_id);
END $$;

-- payload: {pricebook_id?, pricebook_name, description?, is_active?, owner_customer_id?}; returns the pricebook_id. Names are unique per company.
CREATE OR REPLACE FUNCTION bps.fnd_pricebook_save(p_tenant_id bigint, p_payload jsonb) RETURNS bigint
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_id bigint := NULLIF(p_payload ->> 'pricebook_id', '')::bigint; v_name text := btrim(COALESCE(p_payload ->> 'pricebook_name', ''));
        v_owner bigint := NULLIF(p_payload ->> 'owner_customer_id', '')::bigint;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF v_name = '' THEN RAISE EXCEPTION 'The pricing book needs a name'; END IF;
  IF EXISTS (SELECT 1 FROM bps.fnd_pricebooks WHERE tenant_id = p_tenant_id AND lower(pricebook_name) = lower(v_name) AND pricebook_id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'A pricing book named % already exists', v_name;
  END IF;
  IF v_owner IS NOT NULL AND NOT EXISTS (SELECT 1 FROM bps.fnd_customers WHERE tenant_id = p_tenant_id AND customer_id = v_owner) THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO bps.fnd_pricebooks (tenant_id, pricebook_name, description, is_active, owner_customer_id, currency_id)
    VALUES (p_tenant_id, v_name, NULLIF(btrim(p_payload ->> 'description'), ''), COALESCE((p_payload ->> 'is_active')::boolean, true), v_owner,
            (SELECT currency_id FROM bps.fnd_currencies WHERE iso_code = 'USD'))
    RETURNING pricebook_id INTO v_id;
  ELSE
    UPDATE bps.fnd_pricebooks SET pricebook_name = v_name, description = NULLIF(btrim(p_payload ->> 'description'), ''),
      is_active = COALESCE((p_payload ->> 'is_active')::boolean, is_active), owner_customer_id = v_owner
     WHERE pricebook_id = v_id AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Pricing book not found'; END IF;
  END IF;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_pricebook_detail_get(p_tenant_id bigint, p_pricebook_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN jsonb_build_object(
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object('pricebook_item_id', i.pricebook_item_id, 'item_id', i.item_id, 'item_number', it.item_number,
        'item_name', it.item_name, 'item_price', i.item_price, 'is_active', i.is_active) ORDER BY it.item_number)
        FROM bps.fnd_pricebook_items i JOIN bps.fnd_items it ON it.item_id = i.item_id WHERE i.pricebook_id = p_pricebook_id AND i.tenant_id = p_tenant_id), '[]'::jsonb),
    'assignments', COALESCE((SELECT jsonb_agg(jsonb_build_object('customer_id', cp.customer_id, 'customer_name', c.customer_name, 'assignment_type', cp.assignment_type,
        'status', cp.status, 'is_active', cp.is_active, 'effective_start_date', cp.effective_start_date, 'effective_end_date', cp.effective_end_date,
        'precedence', cp.precedence) ORDER BY c.customer_name, cp.precedence)
        FROM bps.fnd_customer_pricebooks cp JOIN bps.fnd_customers c ON c.customer_id = cp.customer_id
       WHERE cp.pricebook_id = p_pricebook_id AND cp.tenant_id = p_tenant_id), '[]'::jsonb));
END $$;

-- p_entries: [{item_id, item_price, is_active?, remove?}]; one row per item per book (an existing row is updated, remove deletes it).
CREATE OR REPLACE FUNCTION bps.fnd_pricebook_items_set(p_tenant_id bigint, p_pricebook_id bigint, p_entries jsonb) RETURNS integer
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE e jsonb; n int := 0; v_item bigint; v_price numeric;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT EXISTS (SELECT 1 FROM bps.fnd_pricebooks WHERE pricebook_id = p_pricebook_id AND tenant_id = p_tenant_id) THEN RAISE EXCEPTION 'Pricing book not found'; END IF;
  FOR e IN SELECT * FROM jsonb_array_elements(COALESCE(p_entries, '[]'::jsonb)) LOOP
    v_item := (e ->> 'item_id')::bigint;
    IF COALESCE((e ->> 'remove')::boolean, false) THEN
      DELETE FROM bps.fnd_pricebook_items WHERE pricebook_id = p_pricebook_id AND tenant_id = p_tenant_id AND item_id = v_item;
    ELSE
      v_price := NULLIF(btrim(e ->> 'item_price'), '')::numeric;
      IF v_price IS NULL OR v_price < 0 THEN RAISE EXCEPTION 'Every item needs a price of 0 or more'; END IF;
      UPDATE bps.fnd_pricebook_items SET item_price = v_price, is_active = COALESCE((e ->> 'is_active')::boolean, true)
       WHERE pricebook_id = p_pricebook_id AND tenant_id = p_tenant_id AND item_id = v_item;
      IF NOT FOUND THEN
        INSERT INTO bps.fnd_pricebook_items (pricebook_id, item_id, item_price, is_active, tenant_id)
        VALUES (p_pricebook_id, v_item, v_price, COALESCE((e ->> 'is_active')::boolean, true), p_tenant_id);
      END IF;
    END IF;
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;

-- ---------- To-do's: pricing assignments that start soon (or already started) but are not yet in effect ----------
-- Only for people who may approve pricing. A start within p_days days counts; assignments already past their start still count until approved.
CREATE OR REPLACE FUNCTION bps.fnd_todos_get(p_tenant_id bigint, p_days integer DEFAULT 14) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_today date := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access_any(ARRAY['customers.pricing','inventory.pricing'], 'A') THEN RETURN '[]'::jsonb; END IF;
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('kind', 'PRICEBOOK_NOT_IN_EFFECT', 'customer_id', cp.customer_id, 'customer_name', c.customer_name,
      'pricebook_id', cp.pricebook_id, 'pricebook_name', pb.pricebook_name, 'assignment_type', cp.assignment_type, 'status', cp.status, 'is_active', cp.is_active,
      'effective_start_date', cp.effective_start_date, 'effective_end_date', cp.effective_end_date, 'days_until_start', (cp.effective_start_date - v_today))
      ORDER BY cp.effective_start_date, c.customer_name), '[]'::jsonb)
    FROM bps.fnd_customer_pricebooks cp JOIN bps.fnd_customers c ON c.customer_id = cp.customer_id JOIN bps.fnd_pricebooks pb ON pb.pricebook_id = cp.pricebook_id
   WHERE cp.tenant_id = p_tenant_id AND cp.status <> 'Archived' AND NOT (cp.is_active AND cp.status = 'Approved')
     AND cp.effective_start_date <= v_today + p_days AND (cp.effective_end_date IS NULL OR cp.effective_end_date >= v_today));
END $$;

REVOKE EXECUTE ON FUNCTION
  bps.om_delivery_date_calc(bigint, date, text), bps.fnd_item_prices_map(bigint, bigint, date, bigint[]), bps.om_items_get_v2(bigint, bigint, boolean, date, text),
  bps.fnd_pricebooks_list_get(bigint), bps.fnd_pricebook_save(bigint, jsonb), bps.fnd_pricebook_detail_get(bigint, bigint),
  bps.fnd_pricebook_items_set(bigint, bigint, jsonb), bps.fnd_todos_get(bigint, integer), bps.om_orders_save(bigint, text, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  bps.om_delivery_date_calc(bigint, date, text), bps.fnd_item_prices_map(bigint, bigint, date, bigint[]), bps.om_items_get_v2(bigint, bigint, boolean, date, text),
  bps.fnd_pricebooks_list_get(bigint), bps.fnd_pricebook_save(bigint, jsonb), bps.fnd_pricebook_detail_get(bigint, bigint),
  bps.fnd_pricebook_items_set(bigint, bigint, jsonb), bps.fnd_todos_get(bigint, integer), bps.om_orders_save(bigint, text, bigint, jsonb) TO authenticated, service_role, bps_dev;
