-- ============================================================
-- om_standing_orders_save
-- Saves standing order lines to one or more production days
-- atomically. For each DOW in p_production_dows: deletes all
-- existing lines for (customer, dow, code) then inserts fresh
-- from p_lines. Saving an empty array clears all lines for
-- those days.
--
-- p_production_dows: TEXT[]  e.g. '{MON,WED,FRI}'
-- p_lines:           JSONB   [{item_id, quantity, prep_options}]
--
-- SECURITY DEFINER — bypasses RLS; tenant validated via JWT.
-- ============================================================

DROP FUNCTION IF EXISTS bps.om_standing_orders_save(BIGINT, BIGINT, TEXT, TEXT, JSONB);

CREATE OR REPLACE FUNCTION bps.om_standing_orders_save(
  p_tenant_id        BIGINT,
  p_customer_id      BIGINT,
  p_production_dows  TEXT[],
  p_production_code  TEXT,
  p_lines            JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
  v_user_id BIGINT;
  v_dow     TEXT;
  v_line    JSONB;
BEGIN
  IF NOT (
    p_tenant_id::text = ANY (ARRAY(
      SELECT jsonb_array_elements_text(
        (NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb
          -> 'app_metadata' -> 'allowed_tenant_ids'
      )
    ))
  ) THEN
    RAISE EXCEPTION 'Access denied for tenant %', p_tenant_id;
  END IF;

  SELECT user_id INTO v_user_id
  FROM fnd_users
  WHERE auth_user_id = auth.uid() AND tenant_id = p_tenant_id
  LIMIT 1;

  FOREACH v_dow IN ARRAY p_production_dows LOOP
    DELETE FROM om_standing_orders
    WHERE tenant_id       = p_tenant_id
      AND customer_id     = p_customer_id
      AND production_dow  = v_dow
      AND production_code = p_production_code;

    FOR v_line IN SELECT * FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB)) LOOP
      INSERT INTO om_standing_orders (
        tenant_id, customer_id, production_dow, production_code,
        item_id, quantity, prep_options, is_active, created_by, updated_by
      ) VALUES (
        p_tenant_id, p_customer_id, v_dow, p_production_code,
        (v_line->>'item_id')::BIGINT,
        COALESCE((v_line->>'quantity')::NUMERIC, 0),
        COALESCE(v_line->'prep_options', '[]'::JSONB),
        TRUE, v_user_id, v_user_id
      );
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'days_saved',  array_length(p_production_dows, 1),
    'lines_saved', jsonb_array_length(COALESCE(p_lines, '[]'::JSONB))
  );
END;
$$;
