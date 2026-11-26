-- ============================================================
-- inv_recipe_json
-- Internal: a saved recipe as JSON in the shape the editor sends to inv_recipe_save / inv_recipe_preview:
--   { recipe_id, recipe_name, recipe_type, dough_code, item_id, piece_weight, piece_unit, loss_pct, ddt_f, friction_f,
--     display_unit, notes, version_no, is_active, lines [{ingredient_id | sub_recipe_id, quantity, unit, note}],
--     steps [{step_type, instruction, duration_min, temperature_f}] }
-- Also what inv_recipe_versions stores as the snapshot. No access check (callers check).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_recipe_json(p_tenant_id bigint, p_recipe_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT jsonb_build_object(
           'recipe_id', r.recipe_id, 'recipe_name', r.recipe_name, 'recipe_type', r.recipe_type, 'dough_code', r.dough_code,
           'item_id', r.item_id, 'piece_weight', r.piece_weight, 'piece_unit', r.piece_unit, 'loss_pct', r.loss_pct,
           'ddt_f', r.ddt_f, 'friction_f', r.friction_f, 'display_unit', r.display_unit, 'notes', r.notes,
           'version_no', r.version_no, 'is_active', r.is_active,
           'lines', COALESCE((SELECT jsonb_agg(jsonb_build_object('ingredient_id', l.ingredient_id, 'sub_recipe_id', l.sub_recipe_id,
                                                'quantity', l.quantity, 'unit', l.unit, 'note', l.note) ORDER BY l.line_no)
                                FROM inv_recipe_lines l WHERE l.recipe_id = r.recipe_id), '[]'::jsonb),
           'steps', COALESCE((SELECT jsonb_agg(jsonb_build_object('step_type', s.step_type, 'instruction', s.instruction,
                                                'duration_min', s.duration_min, 'temperature_f', s.temperature_f) ORDER BY s.step_no)
                                FROM inv_recipe_steps s WHERE s.recipe_id = r.recipe_id), '[]'::jsonb))
    FROM inv_recipes r WHERE r.tenant_id = p_tenant_id AND r.recipe_id = p_recipe_id;
$function$;
REVOKE EXECUTE ON FUNCTION bps.inv_recipe_json(bigint, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION bps.inv_recipe_json(bigint, bigint) TO service_role, bps_dev;
