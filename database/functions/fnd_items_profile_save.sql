-- ============================================================
-- fnd_items_profile_save
--
-- Saves fnd_items + bps_items atomically in one transaction.
-- INSERT when p_item_id IS NULL, UPDATE otherwise.
-- Raises an exception (and rolls back) if the UPDATE matches 0 rows.
--
-- Prerequisites: fnd_items.sql, bps_items.sql
-- ============================================================

DROP FUNCTION IF EXISTS bps.fnd_items_profile_save(BIGINT, BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, NUMERIC, NUMERIC, NUMERIC, BOOLEAN, BOOLEAN, JSONB, JSONB, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC);

CREATE OR REPLACE FUNCTION bps.fnd_items_profile_save(
  p_tenant_id             BIGINT,
  p_item_id               BIGINT    DEFAULT NULL,
  p_item_number           TEXT      DEFAULT NULL,
  p_item_name             TEXT      DEFAULT NULL,
  p_item_description      TEXT      DEFAULT NULL,
  p_category              TEXT      DEFAULT NULL,
  p_unit_of_sale          TEXT      DEFAULT 'PCS',
  p_item_weight           NUMERIC   DEFAULT NULL,
  p_weight_uom            TEXT      DEFAULT NULL,
  p_box_qty_per_box       NUMERIC   DEFAULT NULL,
  p_box_capacity_weight   NUMERIC   DEFAULT NULL,
  p_box_capacity_optimal  NUMERIC   DEFAULT NULL,
  p_sales_terms_apply     BOOLEAN   DEFAULT TRUE,
  p_is_active             BOOLEAN   DEFAULT TRUE,
  p_allowed_prep_options  JSONB     DEFAULT '[]'::JSONB,
  p_default_prep_options  JSONB     DEFAULT '[]'::JSONB,
  p_dough_type            TEXT      DEFAULT NULL,
  p_shape                 TEXT      DEFAULT NULL,
  p_packing               TEXT      DEFAULT NULL,
  p_machine_setting       TEXT      DEFAULT NULL,
  p_sheeter_setting       TEXT      DEFAULT NULL,
  p_weight_adjuster       NUMERIC   DEFAULT 0,
  p_scale_weight          NUMERIC   DEFAULT 0,
  p_scale_qty             NUMERIC   DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = bps, public
AS $$
DECLARE
  v_item_id   BIGINT;
  v_row_count INT;
BEGIN
  IF p_tenant_id IS NULL THEN
    RAISE EXCEPTION 'p_tenant_id is required';
  END IF;

  IF p_item_id IS NULL THEN
    INSERT INTO fnd_items (
      tenant_id, item_number, item_name, item_description,
      category, unit_of_sale,
      item_weight, weight_uom,
      box_qty_per_box, box_capacity_weight, box_capacity_optimal,
      sales_terms_apply, is_active,
      allowed_prep_options, default_prep_options
    ) VALUES (
      p_tenant_id, p_item_number, p_item_name, p_item_description,
      p_category, COALESCE(p_unit_of_sale, 'PCS'),
      p_item_weight, p_weight_uom,
      p_box_qty_per_box, p_box_capacity_weight, p_box_capacity_optimal,
      COALESCE(p_sales_terms_apply, TRUE), COALESCE(p_is_active, TRUE),
      COALESCE(p_allowed_prep_options, '[]'::JSONB),
      COALESCE(p_default_prep_options, '[]'::JSONB)
    )
    RETURNING item_id INTO v_item_id;
  ELSE
    UPDATE fnd_items SET
      item_number          = p_item_number,
      item_name            = p_item_name,
      item_description     = p_item_description,
      category             = p_category,
      unit_of_sale         = COALESCE(p_unit_of_sale, 'PCS'),
      item_weight          = p_item_weight,
      weight_uom           = p_weight_uom,
      box_qty_per_box      = p_box_qty_per_box,
      box_capacity_weight  = p_box_capacity_weight,
      box_capacity_optimal = p_box_capacity_optimal,
      sales_terms_apply    = COALESCE(p_sales_terms_apply, TRUE),
      is_active            = COALESCE(p_is_active, TRUE),
      allowed_prep_options = COALESCE(p_allowed_prep_options, '[]'::JSONB),
      default_prep_options = COALESCE(p_default_prep_options, '[]'::JSONB)
    WHERE tenant_id = p_tenant_id
      AND item_id   = p_item_id;

    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    IF v_row_count = 0 THEN
      RAISE EXCEPTION 'Item not found (item_id=%, tenant_id=%)', p_item_id, p_tenant_id;
    END IF;

    v_item_id := p_item_id;
  END IF;

  INSERT INTO bps_items (
    tenant_id, item_id,
    dough_type, shape, packing,
    machine_setting, sheeter_setting,
    weight_adjuster, scale_weight, scale_qty,
    is_sliceable, is_wrappable, is_coverable,
    default_sliced, default_wrapped, default_covered
  ) VALUES (
    p_tenant_id, v_item_id,
    p_dough_type, p_shape, p_packing,
    p_machine_setting, p_sheeter_setting,
    COALESCE(p_weight_adjuster, 0),
    COALESCE(p_scale_weight, 0),
    COALESCE(p_scale_qty, 0),
    COALESCE(p_allowed_prep_options, '[]'::JSONB) @> '["SLICED"]'::JSONB,
    COALESCE(p_allowed_prep_options, '[]'::JSONB) @> '["WRAPPED"]'::JSONB,
    COALESCE(p_allowed_prep_options, '[]'::JSONB) @> '["COVERED"]'::JSONB,
    COALESCE(p_default_prep_options, '[]'::JSONB) @> '["SLICED"]'::JSONB,
    COALESCE(p_default_prep_options, '[]'::JSONB) @> '["WRAPPED"]'::JSONB,
    COALESCE(p_default_prep_options, '[]'::JSONB) @> '["COVERED"]'::JSONB
  )
  ON CONFLICT (item_id) DO UPDATE SET
    dough_type      = EXCLUDED.dough_type,
    shape           = EXCLUDED.shape,
    packing         = EXCLUDED.packing,
    machine_setting = EXCLUDED.machine_setting,
    sheeter_setting = EXCLUDED.sheeter_setting,
    weight_adjuster = EXCLUDED.weight_adjuster,
    scale_weight    = EXCLUDED.scale_weight,
    scale_qty       = EXCLUDED.scale_qty,
    is_sliceable    = EXCLUDED.is_sliceable,
    is_wrappable    = EXCLUDED.is_wrappable,
    is_coverable    = EXCLUDED.is_coverable,
    default_sliced  = EXCLUDED.default_sliced,
    default_wrapped = EXCLUDED.default_wrapped,
    default_covered = EXCLUDED.default_covered;

  RETURN jsonb_build_object('item_id', v_item_id);
END;
$$;
