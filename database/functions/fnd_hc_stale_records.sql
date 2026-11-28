-- ============================================================
-- Items not ordered / Pricing books not used: one finding per record (owner decision 2026-11-28), replacing the single
-- "Found n …" line from migration/add_health_checks.sql, so the Health Checks page can list them and inactivate the ones
-- picked (fnd_health_records_inactivate).
-- Both still refresh the last-ordered / last-used dates first and use the Stale years (Application Settings > Pricing).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_hc_items_stale(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_years integer; v_cutoff date;
BEGIN
  PERFORM bps.fnd_items_last_ordered_refresh(p_tenant_id);
  SELECT t.pricebook_unused_years INTO v_years FROM bps.fnd_tenants t WHERE t.tenant_id = p_tenant_id;
  v_cutoff := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date - (v_years * 365);
  RETURN QUERY
  SELECT 'Information'::text,
         concat_ws(' · ', i.item_number, i.item_name) || CASE WHEN i.last_ordered_date IS NULL THEN ' — never ordered' ELSE ' — last ordered ' || to_char(i.last_ordered_date, 'Mon FMDD, YYYY') END,
         format('Inactivate the items you no longer sell (tick them and press Inactivate), or on Item Management. Not ordered in over %s year%s.', v_years, CASE WHEN v_years = 1 THEN '' ELSE 's' END),
         'ITEM'::text, i.item_id, NULL::bigint, '/inventory/item-profile'::text
    FROM bps.fnd_items i
   WHERE i.tenant_id = p_tenant_id AND i.is_active AND (i.last_ordered_date IS NULL OR i.last_ordered_date < v_cutoff)
   ORDER BY i.item_number;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_pricebook_unused(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_years integer; v_cutoff date;
BEGIN
  PERFORM bps.fnd_pricebooks_last_used_refresh(p_tenant_id);
  SELECT t.pricebook_unused_years INTO v_years FROM bps.fnd_tenants t WHERE t.tenant_id = p_tenant_id;
  v_cutoff := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date - (v_years * 365);
  RETURN QUERY
  SELECT 'Information'::text,
         b.pricebook_name || CASE WHEN b.last_used_date IS NULL THEN ' — never used' ELSE ' — last used ' || to_char(b.last_used_date, 'Mon FMDD, YYYY') END,
         format('Disable the pricing books you no longer need (tick them and press Disable), or on the Pricing Books page. Not used in over %s year%s.', v_years, CASE WHEN v_years = 1 THEN '' ELSE 's' END),
         'PRICEBOOK'::text, b.pricebook_id, NULL::bigint, '/inventory/pricing'::text
    FROM bps.fnd_pricebooks b
   WHERE b.tenant_id = p_tenant_id AND b.is_active AND (b.last_used_date IS NULL OR b.last_used_date < v_cutoff)
   ORDER BY b.pricebook_name;
END $$;

-- Inactivates the items / disables the pricing books behind the given open findings and marks those findings fixed.
-- Needs Health Checks read access plus item write access (Item Management) for items and pricing write access for books.
-- SECURITY DEFINER so a reader of the checks can mark the finding fixed; the access checks above are explicit. Returns how many records changed.
CREATE OR REPLACE FUNCTION bps.fnd_health_records_inactivate(p_tenant_id bigint, p_log_ids bigint[]) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = bps, public AS $$
DECLARE n_items integer := 0; n_books integer := 0;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.health', 'R') THEN RAISE EXCEPTION 'Not authorised to view health checks'; END IF;
  IF EXISTS (SELECT 1 FROM bps.fnd_health_log l WHERE l.tenant_id = p_tenant_id AND l.log_id = ANY (p_log_ids) AND l.record_type = 'ITEM')
     AND NOT bps.fnd_has_access_any(ARRAY['inventory.item-profile', 'inventory.manage'], 'W') THEN
    RAISE EXCEPTION 'Not authorised to change items';
  END IF;
  IF EXISTS (SELECT 1 FROM bps.fnd_health_log l WHERE l.tenant_id = p_tenant_id AND l.log_id = ANY (p_log_ids) AND l.record_type = 'PRICEBOOK')
     AND NOT bps.fnd_has_access_any(ARRAY['customers.pricing', 'inventory.pricing'], 'W') THEN
    RAISE EXCEPTION 'Not authorised to change pricing books';
  END IF;

  UPDATE bps.fnd_items i SET is_active = false
    FROM bps.fnd_health_log l
   WHERE l.tenant_id = p_tenant_id AND l.log_id = ANY (p_log_ids) AND l.fixed_at IS NULL AND l.record_type = 'ITEM'
     AND i.tenant_id = p_tenant_id AND i.item_id = l.record_id AND i.is_active;
  GET DIAGNOSTICS n_items = ROW_COUNT;
  UPDATE bps.fnd_pricebooks b SET is_active = false
    FROM bps.fnd_health_log l
   WHERE l.tenant_id = p_tenant_id AND l.log_id = ANY (p_log_ids) AND l.fixed_at IS NULL AND l.record_type = 'PRICEBOOK'
     AND b.tenant_id = p_tenant_id AND b.pricebook_id = l.record_id AND b.is_active;
  GET DIAGNOSTICS n_books = ROW_COUNT;

  UPDATE bps.fnd_health_log SET fixed_at = now(), fixed_by = bps.fnd_current_user_id()
   WHERE tenant_id = p_tenant_id AND log_id = ANY (p_log_ids) AND fixed_at IS NULL AND record_type IN ('ITEM', 'PRICEBOOK');
  RETURN n_items + n_books;
END $$;

REVOKE EXECUTE ON FUNCTION bps.fnd_health_records_inactivate(bigint, bigint[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_health_records_inactivate(bigint, bigint[]) TO authenticated, service_role, bps_dev;
