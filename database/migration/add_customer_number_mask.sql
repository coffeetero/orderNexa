-- Customer number mask (Admin > Application Settings > Formats). Approved names:
--   column fnd_tenants.customer_number_mask; functions fnd_customer_number_format, fnd_format_settings_get, fnd_format_settings_save.
-- Each # takes the next digit/character of the customer number; anything else prints as is; characters beyond the mask are
-- dropped, like the old BPS ('###-##': 11200 -> 112-00, 15400000 -> 154-00). NULL prints the number as stored.
SET search_path = bps, public;

ALTER TABLE bps.fnd_tenants ADD COLUMN customer_number_mask text
  CONSTRAINT chk_fnd_tenants_customer_number_mask CHECK (customer_number_mask IS NULL OR (customer_number_mask LIKE '%#%' AND length(customer_number_mask) <= 30));

CREATE OR REPLACE FUNCTION bps.fnd_customer_number_format(p_mask text, p_number text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path = bps, public AS $$
DECLARE v_out text := ''; v_i int := 1; v_ch text;
BEGIN
  IF p_number IS NULL OR p_mask IS NULL OR p_mask = '' THEN RETURN p_number; END IF;
  FOREACH v_ch IN ARRAY regexp_split_to_array(p_mask, '') LOOP
    IF v_ch = '#' THEN
      EXIT WHEN v_i > length(p_number);
      v_out := v_out || substr(p_number, v_i, 1);
      v_i := v_i + 1;
    ELSE
      EXIT WHEN v_i > length(p_number);
      v_out := v_out || v_ch;
    END IF;
  END LOOP;
  RETURN v_out;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_format_settings_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN (SELECT jsonb_build_object('customer_number_mask', customer_number_mask) FROM bps.fnd_tenants WHERE tenant_id = p_tenant_id);
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_format_settings_save(p_tenant_id bigint, p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_mask text := NULLIF(btrim(p_payload ->> 'customer_number_mask'), '');
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.production', 'W') THEN RAISE EXCEPTION 'Not authorised to change application settings'; END IF;
  IF v_mask IS NOT NULL AND (position('#' IN v_mask) = 0 OR length(v_mask) > 30) THEN
    RAISE EXCEPTION 'The customer number mask needs at least one # and at most 30 characters';
  END IF;
  UPDATE bps.fnd_tenants SET customer_number_mask = v_mask WHERE tenant_id = p_tenant_id;
  RETURN bps.fnd_format_settings_get(p_tenant_id);
END $$;

REVOKE EXECUTE ON FUNCTION bps.fnd_customer_number_format(text, text), bps.fnd_format_settings_get(bigint), bps.fnd_format_settings_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_customer_number_format(text, text), bps.fnd_format_settings_get(bigint), bps.fnd_format_settings_save(bigint, jsonb) TO authenticated, service_role, bps_dev;

-- Alpine Bakery prints customer numbers like the old BPS.
UPDATE bps.fnd_tenants SET customer_number_mask = '###-##' WHERE tenant_name = 'Alpine Bakery';
