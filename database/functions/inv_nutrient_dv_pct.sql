-- ============================================================
-- inv_nutrient_dv_pct
-- % Daily Value of an unrounded amount (21 CFR 101.9(d)(7)(ii), (c)(8)(iii)). 0 when the declared amount rounds to zero
-- (so "0g" never shows a % above 0); otherwise from the unrounded amount, which the rule allows.
--   Fats, cholesterol, sodium, carbohydrate, fiber, added sugars: nearest 1%.
--   Vitamins and minerals: <=10% nearest 2%; >10-50% nearest 5%; >50% nearest 10%.
-- NULL when the nutrient has no daily value or the amount is NULL.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_nutrient_dv_pct(p_rule text, p_amount numeric, p_daily_value numeric, p_is_vitamin_mineral boolean)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT CASE
    WHEN p_amount IS NULL OR p_daily_value IS NULL OR p_daily_value <= 0 THEN NULL
    WHEN bps.inv_nutrient_round(p_rule, p_amount) = 0 THEN 0
    WHEN NOT p_is_vitamin_mineral THEN round(p_amount / p_daily_value * 100)::integer
    ELSE (SELECT CASE WHEN pct <= 10 THEN round(pct / 2) * 2 WHEN pct <= 50 THEN round(pct / 5) * 5 ELSE round(pct / 10) * 10 END::integer
            FROM (SELECT p_amount / p_daily_value * 100 AS pct) x)
  END
$function$;
REVOKE EXECUTE ON FUNCTION bps.inv_nutrient_dv_pct(text, numeric, numeric, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_nutrient_dv_pct(text, numeric, numeric, boolean) TO authenticated, service_role, bps_dev;
