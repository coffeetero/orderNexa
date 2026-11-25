-- ============================================================
-- fnd_customer_import_value
-- One Import/Export Customers value in its canonical form, so a file value and the customer's current value compare equal
-- when they mean the same thing. Blank -> NULL. Line breaks -> \n, outer spaces trimmed.
--   flags (is_*)                      Y / YES / TRUE / 1 -> 'Y', N / NO / FALSE / 0 -> 'N'
--   credit_limit                      $ and thousands commas dropped, trailing zeros dropped (1,000.50 -> 1000.5)
--   cutoff_extra_minutes, invoice_copy_count   leading zeros dropped
--   customer_type, billing_type, billing_period, delivery_method   upper case
--   billing_address, shipping_address spaces at line ends dropped
-- A value that does not fit its key is returned as typed (fnd_customer_import_validate reports it).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_customer_import_value(p_key text, p_value text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v text := NULLIF(btrim(replace(replace(p_value, E'\r\n', E'\n'), E'\r', E'\n'), E' \t\n'), '');
    x text;
BEGIN
    IF v IS NULL THEN RETURN NULL; END IF;
    IF p_key LIKE 'is\_%' THEN
        RETURN CASE WHEN upper(v) IN ('Y', 'YES', 'TRUE', '1') THEN 'Y' WHEN upper(v) IN ('N', 'NO', 'FALSE', '0') THEN 'N' ELSE v END;
    ELSIF p_key = 'credit_limit' THEN
        x := replace(replace(v, '$', ''), ',', '');
        RETURN CASE WHEN x ~ '^\d+(\.\d+)?$' THEN trim_scale(x::numeric)::text ELSE v END;
    ELSIF p_key IN ('cutoff_extra_minutes', 'invoice_copy_count') THEN
        RETURN CASE WHEN v ~ '^\d{1,6}$' THEN (v::int)::text ELSE v END;
    ELSIF p_key IN ('customer_type', 'billing_type', 'billing_period', 'delivery_method') THEN
        RETURN upper(v);
    ELSIF p_key IN ('billing_address', 'shipping_address') THEN
        RETURN regexp_replace(v, '[ \t]+\n', E'\n', 'g');
    END IF;
    RETURN v;
END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.fnd_customer_import_value(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_customer_import_value(text, text) TO authenticated, service_role, bps_dev;
