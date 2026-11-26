-- ============================================================
-- inv_unit_grams
-- Converts a weight to grams. p_unit: g, kg, oz, lb (avoirdupois). Used by Inventory › Recipes for every quantity.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_unit_grams(p_qty numeric, p_unit text)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT p_qty * CASE lower(p_unit) WHEN 'g' THEN 1 WHEN 'kg' THEN 1000 WHEN 'oz' THEN 28.349523125 WHEN 'lb' THEN 453.59237 END;
$function$;
REVOKE EXECUTE ON FUNCTION bps.inv_unit_grams(numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_unit_grams(numeric, text) TO authenticated, service_role, bps_dev;
