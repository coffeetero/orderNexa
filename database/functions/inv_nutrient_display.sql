-- ============================================================
-- inv_nutrient_display
-- The amount as printed on the label: rounded (inv_nutrient_round), trailing zeros dropped, unit appended ("2.5g", "140mg",
-- "<1g", "<5mg"). Calories print without a unit. NULL amount -> NULL.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_nutrient_display(p_rule text, p_amount numeric, p_unit text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT CASE
    WHEN p_amount IS NULL THEN NULL
    WHEN p_rule = 'GRAM' AND p_amount >= 0.5 AND p_amount < 1 THEN '<1' || p_unit
    WHEN p_rule = 'CHOLESTEROL' AND p_amount >= 2 AND p_amount < 5 THEN '<5' || p_unit
    ELSE trim_scale(bps.inv_nutrient_round(p_rule, p_amount))::text || CASE WHEN p_unit = 'kcal' THEN '' ELSE p_unit END
  END
$function$;
REVOKE EXECUTE ON FUNCTION bps.inv_nutrient_display(text, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_nutrient_display(text, numeric, text) TO authenticated, service_role, bps_dev;
