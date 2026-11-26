-- ============================================================
-- po_unit_base
-- How much of the base unit one p_unit holds: grams for weights (g, kg, oz, lb), millilitres for volumes (ml, l, fl_oz,
-- gal, US), 1 for each (ea). Used to turn a pack price into a cost per lb, kg, l, gal or each.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.po_unit_base(p_unit text)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT CASE lower(p_unit)
           WHEN 'g' THEN 1 WHEN 'kg' THEN 1000 WHEN 'oz' THEN 28.349523125 WHEN 'lb' THEN 453.59237
           WHEN 'ml' THEN 1 WHEN 'l' THEN 1000 WHEN 'fl_oz' THEN 29.5735295625 WHEN 'gal' THEN 3785.411784
           WHEN 'ea' THEN 1 END;
$function$;
GRANT EXECUTE ON FUNCTION bps.po_unit_base(text) TO authenticated, service_role, bps_dev;
