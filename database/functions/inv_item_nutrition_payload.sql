-- ============================================================
-- inv_item_nutrition_payload
-- An item's stored nutrition profile in the shape inv_nutrition_label_build and inv_item_nutrition_save take, plus its status,
-- approval and audit fields. NULL when the item has no profile. Row security decides what is visible.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_item_nutrition_payload(p_tenant_id bigint, p_item_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
  SELECT jsonb_build_object(
           'item_nutrition_id', n.item_nutrition_id, 'item_id', n.item_id,
           'value_source', n.value_source, 'source_note', n.source_note,
           'serving_size_text', n.serving_size_text, 'serving_size_g', n.serving_size_g,
           'servings_per_container', n.servings_per_container, 'label_format', n.label_format, 'is_dual_column', n.is_dual_column,
           'nutrients', COALESCE((SELECT jsonb_object_agg(v.nutrient_code, trim_scale(v.amount))
                                    FROM bps.inv_item_nutrient_values v WHERE v.item_nutrition_id = n.item_nutrition_id), '{}'::jsonb),
           'ingredient_statement', n.ingredient_statement,
           'allergens', jsonb_build_object('milk', n.is_allergen_milk, 'egg', n.is_allergen_egg, 'fish', n.is_allergen_fish,
                          'shellfish', n.is_allergen_shellfish, 'tree_nuts', n.is_allergen_tree_nuts, 'peanuts', n.is_allergen_peanuts,
                          'wheat', n.is_allergen_wheat, 'soy', n.is_allergen_soy, 'sesame', n.is_allergen_sesame),
           'fish_species', n.fish_species, 'shellfish_species', n.shellfish_species, 'tree_nut_types', n.tree_nut_types,
           'may_contain_text', n.may_contain_text, 'effective_date', n.effective_date,
           'status', n.status, 'approved_at', n.approved_at, 'approved_by_name', ua.user_name,
           'updated_at', n.updated_at, 'updated_by_name', uu.user_name)
    FROM bps.inv_item_nutrition n
    LEFT JOIN bps.fnd_users ua ON ua.user_id = n.approved_by
    LEFT JOIN bps.fnd_users uu ON uu.user_id = n.updated_by
   WHERE n.tenant_id = p_tenant_id AND n.item_id = p_item_id
$function$;
REVOKE EXECUTE ON FUNCTION bps.inv_item_nutrition_payload(bigint, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_item_nutrition_payload(bigint, bigint) TO authenticated, service_role, bps_dev;
