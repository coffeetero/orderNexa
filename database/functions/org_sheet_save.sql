-- ============================================================
-- org_sheet_save
-- Creates or updates a sheet. p_payload: { sheet_id (omit for a new sheet), sheet_name, visibility, workbook, version }
-- version must be the one the caller loaded; a sheet saved by someone else in the meantime is refused, not overwritten.
-- Only the owner may rename a sheet or change its visibility. A workbook is limited to 5 MB.
-- Returns the sheet without its workbook (as org_sheets_get lists it).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.org_sheet_save(p_tenant_id bigint, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user    bigint := bps.fnd_current_user_id();
  v_id      bigint := NULLIF(p_payload ->> 'sheet_id', '')::bigint;
  v_name    text   := NULLIF(btrim(p_payload ->> 'sheet_name'), '');
  v_vis     text   := COALESCE(NULLIF(upper(btrim(p_payload ->> 'visibility')), ''), 'PRIVATE');
  v_book    jsonb  := p_payload -> 'workbook';
  v_version integer := NULLIF(p_payload ->> 'version', '')::integer;
  v_cur     bps.org_sheets;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('organizer.sheets', 'W') THEN RAISE EXCEPTION 'You do not have access to edit sheets'; END IF;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Give the sheet a name'; END IF;
  IF v_vis NOT IN ('PRIVATE', 'SHARED') THEN RAISE EXCEPTION 'Visibility must be PRIVATE or SHARED'; END IF;
  IF v_book IS NULL OR jsonb_typeof(v_book) <> 'object' THEN RAISE EXCEPTION 'The workbook is missing'; END IF;
  IF octet_length(v_book::text) > 5 * 1024 * 1024 THEN RAISE EXCEPTION 'The sheet is larger than 5 MB'; END IF;

  IF v_id IS NULL THEN
    INSERT INTO org_sheets (tenant_id, owner_user_id, sheet_name, visibility, workbook, created_by, updated_by)
    VALUES (p_tenant_id, v_user, v_name, v_vis, v_book, v_user, v_user)
    RETURNING sheet_id INTO v_id;
  ELSE
    SELECT * INTO v_cur FROM org_sheets WHERE tenant_id = p_tenant_id AND sheet_id = v_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Sheet not found'; END IF;
    IF v_version IS DISTINCT FROM v_cur.version THEN
      RAISE EXCEPTION 'Someone else saved this sheet since you opened it. Reload it to see their changes.';
    END IF;
    IF v_cur.owner_user_id IS DISTINCT FROM v_user AND (v_name <> v_cur.sheet_name OR v_vis <> v_cur.visibility) THEN
      RAISE EXCEPTION 'Only the owner can rename the sheet or change who can see it';
    END IF;
    UPDATE org_sheets SET sheet_name = v_name, visibility = v_vis, workbook = v_book, version = version + 1,
                          updated_at = now(), updated_by = v_user
     WHERE sheet_id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'You cannot edit this sheet'; END IF;
  END IF;

  RETURN (SELECT jsonb_build_object('sheet_id', s.sheet_id, 'sheet_name', s.sheet_name, 'visibility', s.visibility,
                                    'version', s.version, 'is_owner', s.owner_user_id = v_user, 'updated_at', s.updated_at)
            FROM org_sheets s WHERE s.sheet_id = v_id);
END $function$;
REVOKE EXECUTE ON FUNCTION bps.org_sheet_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.org_sheet_save(bigint, jsonb) TO authenticated, service_role, bps_dev;
