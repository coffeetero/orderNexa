-- Print Invoices (Production > Print Invoices), 2026-11-24. Approved names:
--   columns fnd_tenants.item_number_mask, invoice_footer_note, invoice_tagline (Admin > Application Settings > Formats);
--   function ar_invoices_print_get; om_report_customers_get basis 'PRINT'.
-- item_number_mask works like customer_number_mask ('###-##' prints 11721 as 117-21; empty = as stored).
SET search_path = bps, public;

ALTER TABLE bps.fnd_tenants ADD COLUMN IF NOT EXISTS item_number_mask text
  CONSTRAINT chk_fnd_tenants_item_number_mask CHECK (item_number_mask IS NULL OR (item_number_mask LIKE '%#%' AND length(item_number_mask) <= 30));
ALTER TABLE bps.fnd_tenants ADD COLUMN IF NOT EXISTS invoice_footer_note text
  CONSTRAINT chk_fnd_tenants_invoice_footer_note CHECK (invoice_footer_note IS NULL OR length(invoice_footer_note) <= 300);
ALTER TABLE bps.fnd_tenants ADD COLUMN IF NOT EXISTS invoice_tagline text
  CONSTRAINT chk_fnd_tenants_invoice_tagline CHECK (invoice_tagline IS NULL OR length(invoice_tagline) <= 100);

CREATE OR REPLACE FUNCTION bps.fnd_format_settings_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN (SELECT jsonb_build_object('customer_number_mask', customer_number_mask, 'item_number_mask', item_number_mask,
                                    'invoice_footer_note', invoice_footer_note, 'invoice_tagline', invoice_tagline)
            FROM bps.fnd_tenants WHERE tenant_id = p_tenant_id);
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_format_settings_save(p_tenant_id bigint, p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE
  v_mask    text := NULLIF(btrim(p_payload ->> 'customer_number_mask'), '');
  v_item    text := NULLIF(btrim(p_payload ->> 'item_number_mask'), '');
  v_note    text := NULLIF(btrim(p_payload ->> 'invoice_footer_note'), '');
  v_tagline text := NULLIF(btrim(p_payload ->> 'invoice_tagline'), '');
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.production', 'W') THEN RAISE EXCEPTION 'Not authorised to change application settings'; END IF;
  IF v_mask IS NOT NULL AND (position('#' IN v_mask) = 0 OR length(v_mask) > 30) THEN
    RAISE EXCEPTION 'The customer number mask needs at least one # and at most 30 characters';
  END IF;
  IF v_item IS NOT NULL AND (position('#' IN v_item) = 0 OR length(v_item) > 30) THEN
    RAISE EXCEPTION 'The item number mask needs at least one # and at most 30 characters';
  END IF;
  IF length(v_note) > 300 THEN RAISE EXCEPTION 'The invoice footer note can have at most 300 characters'; END IF;
  IF length(v_tagline) > 100 THEN RAISE EXCEPTION 'The invoice tagline can have at most 100 characters'; END IF;
  UPDATE bps.fnd_tenants SET customer_number_mask = v_mask, item_number_mask = v_item, invoice_footer_note = v_note, invoice_tagline = v_tagline
   WHERE tenant_id = p_tenant_id;
  RETURN bps.fnd_format_settings_get(p_tenant_id);
END $$;

REVOKE EXECUTE ON FUNCTION bps.fnd_format_settings_get(bigint), bps.fnd_format_settings_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_format_settings_get(bigint), bps.fnd_format_settings_save(bigint, jsonb) TO authenticated, service_role, bps_dev;

-- Alpine Bakery prints invoices like the old BPS.
UPDATE bps.fnd_tenants
   SET item_number_mask = '###-##',
       invoice_footer_note = 'PRODUCED IN A BAKERY WHICH USES THE FOLLOWING ALLERGENS; SOY, EGGS, WHEY, TREENUTS AND SESAME SEEDS',
       invoice_tagline = 'a taste of europe'
 WHERE tenant_name = 'Alpine Bakery';
