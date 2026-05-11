-- ============================================================
-- fnd_pricebook_items_save
--
-- Atomically upserts a set of pricebook price entries for one item.
-- Each entry in p_entries:
--   { pricebook_id, pricebook_item_id (null = insert), item_price, is_active }
--
-- INSERT path: uses ON CONFLICT on uq_fnd_pricebook_items_book_item_tier
--   so a duplicate tier-1 entry becomes an update instead of an error.
-- UPDATE path: targets pricebook_item_id directly.
--
-- SECURITY DEFINER — bypasses customer-facing RLS; validates tenant
-- access via JWT claims before touching any rows.
--
-- Prerequisites: fnd_pricebook_items.sql
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_pricebook_items_save(
  p_tenant_id BIGINT,
  p_item_id   BIGINT,
  p_entries   JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
  v_rec               RECORD;
  v_entry             JSONB;
  v_pricebook_item_id BIGINT;
  v_pricebook_id      BIGINT;
  v_item_price        NUMERIC;
  v_is_active         BOOLEAN;
  v_count             INT := 0;
BEGIN
  IF NOT (
    p_tenant_id::text = ANY (ARRAY(
      SELECT jsonb_array_elements_text(
        (NULLIF(current_setting('request.jwt.claims'::text, true), ''::text))::jsonb
          -> 'app_metadata'::text
          -> 'allowed_tenant_ids'::text
      )
    ))
  ) THEN
    RAISE EXCEPTION 'Access denied for tenant %', p_tenant_id;
  END IF;

  FOR v_rec IN SELECT value FROM jsonb_array_elements(p_entries) AS t(value) LOOP
    v_entry             := v_rec.value;
    v_pricebook_item_id := NULLIF(v_entry->>'pricebook_item_id', 'null')::BIGINT;
    v_pricebook_id      := (v_entry->>'pricebook_id')::BIGINT;
    v_item_price        := (v_entry->>'item_price')::NUMERIC;
    v_is_active         := COALESCE((v_entry->>'is_active')::BOOLEAN, true);

    IF v_pricebook_item_id IS NULL THEN
      INSERT INTO fnd_pricebook_items (
        tenant_id, pricebook_id, item_id, item_price, min_quantity, is_active
      ) VALUES (
        p_tenant_id, v_pricebook_id, p_item_id, v_item_price, 1, v_is_active
      )
      ON CONFLICT ON CONSTRAINT uq_fnd_pricebook_items_book_item_tier
      DO UPDATE SET
        item_price = EXCLUDED.item_price,
        is_active  = EXCLUDED.is_active;
    ELSE
      UPDATE fnd_pricebook_items SET
        item_price = v_item_price,
        is_active  = v_is_active
      WHERE pricebook_item_id = v_pricebook_item_id
        AND tenant_id         = p_tenant_id;
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('saved', v_count);
END;
$$;
