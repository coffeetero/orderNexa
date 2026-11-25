-- ============================================================
-- inv_item_nutrition_approve
-- p_approve true: approves the item's label (needs Approve on inventory.labels and a label with no issues: every mandatory
-- nutrient, serving size, servings per container, ingredient statement, named fish/shellfish/tree nuts, consistent amounts).
-- p_approve false: puts it back to DRAFT. Returns inv_item_nutrition_get.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.inv_item_nutrition_approve(p_tenant_id bigint, p_item_id bigint, p_approve boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_prof jsonb; v_issues jsonb; v_user bigint := bps.fnd_current_user_id();
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('inventory.labels', 'A') THEN RAISE EXCEPTION 'Only a nutrition label approver can approve labels'; END IF;
  v_prof := bps.inv_item_nutrition_payload(p_tenant_id, p_item_id);
  IF v_prof IS NULL THEN RAISE EXCEPTION 'This item has no nutrition profile'; END IF;
  IF p_approve THEN
    v_issues := bps.inv_nutrition_label_build(p_tenant_id, v_prof) -> 'issues';
    IF jsonb_array_length(v_issues) > 0 THEN
      RAISE EXCEPTION 'Cannot approve: %', (SELECT string_agg(x, '; ') FROM jsonb_array_elements_text(v_issues) x);
    END IF;
    UPDATE inv_item_nutrition SET status = 'APPROVED', approved_at = now(), approved_by = v_user, updated_at = now(), updated_by = v_user
     WHERE tenant_id = p_tenant_id AND item_id = p_item_id AND status <> 'APPROVED';
  ELSE
    UPDATE inv_item_nutrition SET status = 'DRAFT', approved_at = NULL, approved_by = NULL, updated_at = now(), updated_by = v_user
     WHERE tenant_id = p_tenant_id AND item_id = p_item_id AND status <> 'DRAFT';
  END IF;
  RETURN bps.inv_item_nutrition_get(p_tenant_id, p_item_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.inv_item_nutrition_approve(bigint, bigint, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.inv_item_nutrition_approve(bigint, bigint, boolean) TO authenticated, service_role, bps_dev;
