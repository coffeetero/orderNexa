-- ============================================================
-- po_vendor_save
-- Creates or updates one vendor. Returns the vendor as po_vendors_get lists it.
-- p_vendor: { vendor_id (omit for new), vendor_code, vendor_name, account_number, payment_terms, lead_time_days,
--   delivery_days [MON..SUN], min_order_amount, currency_code (default USD), website, notes, is_active }
-- ============================================================
CREATE OR REPLACE FUNCTION bps.po_vendor_save(p_tenant_id bigint, p_vendor jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user  bigint := bps.fnd_current_user_id();
  v_id    bigint := NULLIF(p_vendor ->> 'vendor_id', '')::bigint;
  v_code  text := upper(NULLIF(btrim(p_vendor ->> 'vendor_code'), ''));
  v_name  text := NULLIF(btrim(p_vendor ->> 'vendor_name'), '');
  v_acct  text := NULLIF(btrim(p_vendor ->> 'account_number'), '');
  v_terms text := NULLIF(btrim(p_vendor ->> 'payment_terms'), '');
  v_lead  integer := NULLIF(btrim(p_vendor ->> 'lead_time_days'), '')::integer;
  v_days  text[] := COALESCE((SELECT array_agg(d ORDER BY array_position(ARRAY['MON','TUE','WED','THU','FRI','SAT','SUN'], d))
                                FROM (SELECT DISTINCT upper(x) d FROM jsonb_array_elements_text(COALESCE(p_vendor -> 'delivery_days', '[]'::jsonb)) x) s), '{}');
  v_min   numeric := NULLIF(btrim(p_vendor ->> 'min_order_amount'), '')::numeric;
  v_cur   text := upper(COALESCE(NULLIF(btrim(p_vendor ->> 'currency_code'), ''), 'USD'));
  v_web   text := NULLIF(btrim(p_vendor ->> 'website'), '');
  v_notes text := NULLIF(btrim(p_vendor ->> 'notes'), '');
  v_act   boolean := COALESCE((p_vendor ->> 'is_active')::boolean, true);
BEGIN
  PERFORM bps.po_check(p_tenant_id, 'W');
  IF v_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM po_vendors WHERE tenant_id = p_tenant_id AND vendor_id = v_id) THEN
    RAISE EXCEPTION 'Vendor not found';
  END IF;
  IF v_code IS NULL THEN RAISE EXCEPTION 'Give the vendor a code'; END IF;
  IF v_code !~ '^[A-Z0-9][A-Z0-9_-]{0,19}$' THEN RAISE EXCEPTION 'The vendor code is up to 20 letters, digits, - or _'; END IF;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Give the vendor a name'; END IF;
  IF length(v_name) > 100 THEN RAISE EXCEPTION 'The vendor name is limited to 100 characters'; END IF;
  IF length(v_acct) > 50 THEN RAISE EXCEPTION 'The account number is limited to 50 characters'; END IF;
  IF length(v_terms) > 50 THEN RAISE EXCEPTION 'Payment terms are limited to 50 characters'; END IF;
  IF v_lead NOT BETWEEN 0 AND 90 THEN RAISE EXCEPTION 'Lead time is 0 to 90 days'; END IF;
  IF NOT v_days <@ ARRAY['MON','TUE','WED','THU','FRI','SAT','SUN'] THEN RAISE EXCEPTION 'Unknown delivery day'; END IF;
  IF v_min < 0 THEN RAISE EXCEPTION 'The minimum order cannot be negative'; END IF;
  IF v_cur !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'Currency is a 3-letter code (USD)'; END IF;
  IF length(v_web) > 200 THEN RAISE EXCEPTION 'The website is limited to 200 characters'; END IF;
  IF length(v_notes) > 2000 THEN RAISE EXCEPTION 'Notes are limited to 2000 characters'; END IF;
  IF EXISTS (SELECT 1 FROM po_vendors WHERE tenant_id = p_tenant_id AND vendor_code = v_code AND vendor_id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'There is already a vendor with code %', v_code;
  END IF;
  IF EXISTS (SELECT 1 FROM po_vendors WHERE tenant_id = p_tenant_id AND lower(vendor_name) = lower(v_name) AND vendor_id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'There is already a vendor called %', v_name;
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO po_vendors (tenant_id, vendor_code, vendor_name, account_number, payment_terms, lead_time_days, delivery_days,
                            min_order_amount, currency_code, website, notes, is_active, created_by, updated_by)
    VALUES (p_tenant_id, v_code, v_name, v_acct, v_terms, v_lead, v_days, v_min, v_cur, v_web, v_notes, v_act, v_user, v_user)
    RETURNING vendor_id INTO v_id;
  ELSE
    UPDATE po_vendors SET vendor_code = v_code, vendor_name = v_name, account_number = v_acct, payment_terms = v_terms,
                          lead_time_days = v_lead, delivery_days = v_days, min_order_amount = v_min, currency_code = v_cur,
                          website = v_web, notes = v_notes, is_active = v_act, updated_by = v_user
     WHERE vendor_id = v_id;
  END IF;

  RETURN (SELECT x FROM jsonb_array_elements(bps.po_vendors_get(p_tenant_id)) x WHERE (x ->> 'vendor_id')::bigint = v_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.po_vendor_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.po_vendor_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
