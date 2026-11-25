-- ============================================================
-- inv_nutrient_round
-- The amount declared on a Nutrition Facts label for an unrounded amount, by FDA rounding rule (21 CFR 101.9(c), FDA Food
-- Labeling Guide Appendix H). For the "less than" ranges it returns the threshold (cholesterol 2-<5 mg -> 5, grams 0.5-<1 -> 1);
-- inv_nutrient_display then prints "<5mg" / "<1g".
--   CALORIES    <5 -> 0; <=50 nearest 5; >50 nearest 10
--   FAT         <0.5 -> 0; <5 nearest 0.5; >=5 nearest 1             (total, saturated, trans, poly-, monounsaturated fat)
--   CHOLESTEROL <2 -> 0; 2-<5 "less than 5"; >=5 nearest 5
--   SODIUM      <5 -> 0; <=140 nearest 5; >140 nearest 10
--   GRAM        <0.5 -> 0; 0.5-<1 "less than 1"; >=1 nearest 1         (carbohydrate, fiber, sugars, added sugars, sugar alcohol, protein)
--   TENTH       nearest 0.1                                            (vitamin D mcg, iron mg, vitamin C mg)
--   TEN         nearest 10                                             (calcium mg, potassium mg, vitamin A mcg)
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_nutrient_round(p_rule text, p_amount numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT CASE
    WHEN p_amount IS NULL THEN NULL
    WHEN p_rule = 'CALORIES'    THEN CASE WHEN p_amount < 5 THEN 0 WHEN p_amount <= 50 THEN round(p_amount / 5) * 5 ELSE round(p_amount / 10) * 10 END
    WHEN p_rule = 'FAT'         THEN CASE WHEN p_amount < 0.5 THEN 0 WHEN p_amount < 5 THEN round(p_amount * 2) / 2 ELSE round(p_amount) END
    WHEN p_rule = 'CHOLESTEROL' THEN CASE WHEN p_amount < 2 THEN 0 WHEN p_amount < 5 THEN 5 ELSE round(p_amount / 5) * 5 END
    WHEN p_rule = 'SODIUM'      THEN CASE WHEN p_amount < 5 THEN 0 WHEN p_amount <= 140 THEN round(p_amount / 5) * 5 ELSE round(p_amount / 10) * 10 END
    WHEN p_rule = 'GRAM'        THEN CASE WHEN p_amount < 0.5 THEN 0 WHEN p_amount < 1 THEN 1 ELSE round(p_amount) END
    WHEN p_rule = 'TENTH'       THEN round(p_amount, 1)
    WHEN p_rule = 'TEN'         THEN round(p_amount / 10) * 10
  END
$function$;
REVOKE EXECUTE ON FUNCTION bps.inv_nutrient_round(text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_nutrient_round(text, numeric) TO authenticated, service_role, bps_dev;
