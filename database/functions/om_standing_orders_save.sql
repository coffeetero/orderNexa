-- ============================================================
-- om_standing_orders_save
-- Replaces standing order lines for (customer, production_dow,
-- production_code). Lines in p_lines are upserted; lines
-- previously saved but absent are deleted.
--
-- p_lines: [{item_id, quantity, prep_options}]
-- Saving with an empty array deletes all lines for that combo.
--
-- SECURITY DEFINER — bypasses RLS; tenant validated via JWT.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.om_standing_orders_save(
  p_tenant_id       BIGINT,
  p_customer_id     BIGINT,
  p_production_dow  TEXT,
  p_production_code TEXT,
  p_lines           JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
  v_user_id   BIGINT;
  v_line      JSONB;
  v_item_id   BIGINT;
  v_so_id     BIGINT;
  v_kept_ids  BIGINT[] := '{}';
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
  WHERE auth_user_id = auth.uid()
    AND tenant_id    = p_tenant_id
  LIMIT 1;

  FOR v_line IN
    SELECT * FROM jsonb_array_elements(COALESCE(p_lines, '[]'::JSONB))
  LOOP
    v_item_id := (v_line->>'item_id')::BIGINT;

    INSERT INTO om_standing_orders (
      tenant_id, customer_id, production_dow, production_code,
      item_id, quantity, prep_options, is_active,
      created_by, updated_by
    ) VALUES (
      p_tenant_id, p_customer_id, p_production_dow, p_production_code,
      v_item_id,
      COALESCE((v_line->>'quantity')::NUMERIC, 0),
      COALESCE((v_line->'prep_options'), '[]'::JSONB),
      TRUE,
      v_user_id, v_user_id
    )
    ON CONFLICT (tenant_id, customer_id, production_dow, production_code, item_id)
    DO UPDATE SET
      quantity     = EXCLUDED.quantity,
      prep_options = EXCLUDED.prep_options,
      is_active    = TRUE,
      updated_by   = v_user_id
    RETURNING standing_order_id INTO v_so_id;

    v_kept_ids := v_kept_ids || v_so_id;
  END LOOP;

  -- Delete lines removed by the user
  DELETE FROM om_standing_orders
  WHERE tenant_id       = p_tenant_id
    AND customer_id     = p_customer_id
    AND production_dow  = p_production_dow
    AND production_code = p_production_code
    AND standing_order_id != ALL(v_kept_ids);

  RETURN jsonb_build_object('saved', array_length(v_kept_ids, 1));
END;
$$;
