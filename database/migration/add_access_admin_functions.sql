-- =====================================================================================
-- Access administration API (no new tables or columns): roles + access matrix, users, customer groups, channel numbers.
-- All functions are SECURITY INVOKER: row security (area access, tenant, scope) decides what each caller may read or change.
-- Apply after add_rls_access_model.sql.
-- =====================================================================================
SET search_path = bps, public;

-- ---------- roles ----------
CREATE OR REPLACE FUNCTION bps.fnd_roles_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'role_id', r.role_id, 'role_name', r.role_name, 'role_audience', r.role_audience, 'owner_customer_id', r.owner_customer_id,
      'is_system', r.is_system, 'is_active', r.is_active,
      'user_count', (SELECT count(*) FROM bps.fnd_user_roles ur WHERE ur.role_id = r.role_id),
      'area_count', (SELECT count(*) FROM bps.fnd_role_area_access a WHERE a.role_id = r.role_id AND a.can_read))
    ORDER BY r.role_audience, r.is_system DESC, r.role_name), '[]'::jsonb)
  FROM bps.fnd_roles r WHERE r.tenant_id = p_tenant_id
$$;

-- All areas of the role's audience with the role's flags (all false for a new role: pass p_audience).
CREATE OR REPLACE FUNCTION bps.fnd_role_access_get(p_tenant_id bigint, p_role_id bigint DEFAULT NULL, p_audience text DEFAULT 'TENANT') RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_aud text := p_audience;
BEGIN
  IF p_role_id IS NOT NULL THEN
    SELECT role_audience INTO v_aud FROM bps.fnd_roles WHERE role_id = p_role_id AND tenant_id = p_tenant_id;
    IF v_aud IS NULL THEN RAISE EXCEPTION 'Role not found'; END IF;
  END IF;
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'area_key', a.area_key, 'module', a.module, 'area_name', a.area_name,
      'can_read', COALESCE(x.can_read, false), 'can_write', COALESCE(x.can_write, false), 'can_approve', COALESCE(x.can_approve, false),
      'can_void', COALESCE(x.can_void, false), 'can_delete', COALESCE(x.can_delete, false)) ORDER BY a.display_order), '[]'::jsonb)
    FROM bps.fnd_areas a
    LEFT JOIN bps.fnd_role_area_access x ON x.role_id = p_role_id AND x.area_key = a.area_key
    WHERE a.audience = v_aud);
END $$;

-- payload: {role_id?, role_name, role_audience, owner_customer_id?, is_active, access: [{area_key, can_read, can_write, can_approve, can_void, can_delete}]}
-- Any action flag implies read. System roles keep their name and access.
CREATE OR REPLACE FUNCTION bps.fnd_role_save(p_tenant_id bigint, p_payload jsonb) RETURNS bigint
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_id bigint := NULLIF(p_payload ->> 'role_id', '')::bigint; v_sys boolean; a jsonb; v_keys text[] := '{}'; v_name text := btrim(COALESCE(p_payload ->> 'role_name', ''));
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF v_id IS NULL THEN
    IF v_name = '' THEN RAISE EXCEPTION 'Role name is required'; END IF;
    INSERT INTO bps.fnd_roles (tenant_id, role_name, role_audience, owner_customer_id, is_active)
    VALUES (p_tenant_id, v_name, COALESCE(NULLIF(p_payload ->> 'role_audience', ''), 'TENANT'),
            NULLIF(p_payload ->> 'owner_customer_id', '')::bigint, COALESCE((p_payload ->> 'is_active')::boolean, true))
    RETURNING role_id INTO v_id;
  ELSE
    SELECT is_system INTO v_sys FROM bps.fnd_roles WHERE role_id = v_id AND tenant_id = p_tenant_id;
    IF v_sys IS NULL THEN RAISE EXCEPTION 'Role not found'; END IF;
    IF v_sys THEN RAISE EXCEPTION 'System roles cannot be edited'; END IF;
    IF v_name = '' THEN RAISE EXCEPTION 'Role name is required'; END IF;
    UPDATE bps.fnd_roles SET role_name = v_name, is_active = COALESCE((p_payload ->> 'is_active')::boolean, is_active)
     WHERE role_id = v_id AND tenant_id = p_tenant_id;
  END IF;
  FOR a IN SELECT * FROM jsonb_array_elements(COALESCE(p_payload -> 'access', '[]'::jsonb)) LOOP
    IF (a ->> 'can_read')::boolean OR (a ->> 'can_write')::boolean OR (a ->> 'can_approve')::boolean OR (a ->> 'can_void')::boolean OR (a ->> 'can_delete')::boolean THEN
      v_keys := v_keys || (a ->> 'area_key');
      INSERT INTO bps.fnd_role_area_access (tenant_id, role_id, area_key, can_read, can_write, can_approve, can_void, can_delete)
      VALUES (p_tenant_id, v_id, a ->> 'area_key', true, COALESCE((a ->> 'can_write')::boolean, false), COALESCE((a ->> 'can_approve')::boolean, false),
              COALESCE((a ->> 'can_void')::boolean, false), COALESCE((a ->> 'can_delete')::boolean, false))
      ON CONFLICT (role_id, area_key) DO UPDATE SET can_read = true, can_write = EXCLUDED.can_write, can_approve = EXCLUDED.can_approve,
        can_void = EXCLUDED.can_void, can_delete = EXCLUDED.can_delete;
    END IF;
  END LOOP;
  DELETE FROM bps.fnd_role_area_access WHERE role_id = v_id AND tenant_id = p_tenant_id AND NOT (area_key = ANY (v_keys));
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_role_delete(p_tenant_id bigint, p_role_id bigint) RETURNS void
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE n int;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  DELETE FROM bps.fnd_roles WHERE role_id = p_role_id AND tenant_id = p_tenant_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RAISE EXCEPTION 'Role not found or you may not delete it'; END IF;
END $$;

-- ---------- users ----------
CREATE OR REPLACE FUNCTION bps.fnd_users_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'user_id', u.user_id, 'user_name', u.user_name, 'email', u.email, 'user_type', u.user_type,
      'is_active', ut.is_active AND u.is_active,
      'role_ids', COALESCE((SELECT jsonb_agg(ur.role_id ORDER BY ur.role_id) FROM bps.fnd_user_roles ur WHERE ur.user_id = u.user_id AND ur.tenant_id = p_tenant_id), '[]'::jsonb),
      'group_ids', COALESCE((SELECT jsonb_agg(g.group_id ORDER BY g.group_id) FROM bps.fnd_user_customer_groups g WHERE g.user_id = u.user_id AND g.tenant_id = p_tenant_id), '[]'::jsonb),
      'customers', COALESCE((SELECT jsonb_agg(c.customer_name ORDER BY c.customer_name) FROM bps.fnd_user_customers uc JOIN bps.fnd_customers c ON c.customer_id = uc.customer_id
                              WHERE uc.user_id = u.user_id AND uc.tenant_id = p_tenant_id AND uc.is_active), '[]'::jsonb))
    ORDER BY u.user_type, u.user_name), '[]'::jsonb)
  FROM bps.fnd_user_tenants ut JOIN bps.fnd_users u ON u.user_id = ut.user_id
  WHERE ut.tenant_id = p_tenant_id
$$;

-- Replaces a user's roles and (tenant users) customer groups for this tenancy and sets their membership status.
CREATE OR REPLACE FUNCTION bps.fnd_user_access_save(p_tenant_id bigint, p_user_id bigint, p_role_ids bigint[], p_group_ids bigint[], p_is_active boolean) RETURNS void
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_type text; r bigint; g bigint;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_is_trusted() AND p_user_id = bps.fnd_current_user_id() THEN
    RAISE EXCEPTION 'Ask another administrator to change your own access';
  END IF;
  SELECT u.user_type INTO v_type FROM bps.fnd_users u JOIN bps.fnd_user_tenants ut ON ut.user_id = u.user_id AND ut.tenant_id = p_tenant_id WHERE u.user_id = p_user_id;
  IF v_type IS NULL THEN RAISE EXCEPTION 'User not found in this tenancy'; END IF;
  UPDATE bps.fnd_user_tenants SET is_active = COALESCE(p_is_active, is_active) WHERE user_id = p_user_id AND tenant_id = p_tenant_id;
  DELETE FROM bps.fnd_user_roles WHERE user_id = p_user_id AND tenant_id = p_tenant_id;
  FOREACH r IN ARRAY COALESCE(p_role_ids, '{}') LOOP
    INSERT INTO bps.fnd_user_roles (tenant_id, user_id, role_id) VALUES (p_tenant_id, p_user_id, r);
  END LOOP;
  IF v_type = 'TENANCY_USER' THEN
    DELETE FROM bps.fnd_user_customer_groups WHERE user_id = p_user_id AND tenant_id = p_tenant_id;
    FOREACH g IN ARRAY COALESCE(p_group_ids, '{}') LOOP
      INSERT INTO bps.fnd_user_customer_groups (tenant_id, user_id, group_id) VALUES (p_tenant_id, p_user_id, g);
    END LOOP;
  END IF;
END $$;

-- ---------- customer groups ----------
CREATE OR REPLACE FUNCTION bps.fnd_customer_groups_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'group_id', g.group_id, 'group_name', g.group_name, 'is_all_customers', g.is_all_customers, 'is_active', g.is_active,
      'customer_ids', COALESCE((SELECT jsonb_agg(m.customer_id ORDER BY m.customer_id) FROM bps.fnd_customer_group_members m WHERE m.group_id = g.group_id), '[]'::jsonb),
      'effective_count', (SELECT count(*) FROM bps.fnd_customer_group_effective e WHERE e.group_id = g.group_id),
      'user_count', (SELECT count(*) FROM bps.fnd_user_customer_groups ug WHERE ug.group_id = g.group_id))
    ORDER BY g.is_all_customers DESC, g.group_name), '[]'::jsonb)
  FROM bps.fnd_customer_groups g WHERE g.tenant_id = p_tenant_id
$$;

CREATE OR REPLACE FUNCTION bps.fnd_customer_options_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('customer_id', c.customer_id, 'customer_number', c.customer_number, 'customer_name', c.customer_name,
      'customer_type', c.customer_type, 'customer_parent_id', c.customer_parent_id) ORDER BY c.customer_name), '[]'::jsonb)
  FROM bps.fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.customer_parent_id IS NULL
$$;

-- payload: {group_id?, group_name, is_active, customer_ids: [..]}  Members are the top-level (and any explicit) customers; departments and sites inherit.
CREATE OR REPLACE FUNCTION bps.fnd_customer_group_save(p_tenant_id bigint, p_payload jsonb) RETURNS bigint
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_id bigint := NULLIF(p_payload ->> 'group_id', '')::bigint; v_name text := btrim(COALESCE(p_payload ->> 'group_name', '')); v_all boolean; v_ids bigint[];
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF v_name = '' THEN RAISE EXCEPTION 'Group name is required'; END IF;
  SELECT COALESCE(array_agg(x::bigint), '{}') INTO v_ids FROM jsonb_array_elements_text(COALESCE(p_payload -> 'customer_ids', '[]'::jsonb)) x;
  IF v_id IS NULL THEN
    INSERT INTO bps.fnd_customer_groups (tenant_id, group_name, is_active) VALUES (p_tenant_id, v_name, COALESCE((p_payload ->> 'is_active')::boolean, true)) RETURNING group_id INTO v_id;
  ELSE
    SELECT is_all_customers INTO v_all FROM bps.fnd_customer_groups WHERE group_id = v_id AND tenant_id = p_tenant_id;
    IF v_all IS NULL THEN RAISE EXCEPTION 'Group not found'; END IF;
    IF v_all THEN RAISE EXCEPTION 'The All Customers group cannot be edited'; END IF;
    UPDATE bps.fnd_customer_groups SET group_name = v_name, is_active = COALESCE((p_payload ->> 'is_active')::boolean, is_active) WHERE group_id = v_id AND tenant_id = p_tenant_id;
  END IF;
  DELETE FROM bps.fnd_customer_group_members WHERE group_id = v_id AND tenant_id = p_tenant_id AND NOT (customer_id = ANY (v_ids));
  INSERT INTO bps.fnd_customer_group_members (tenant_id, group_id, customer_id)
  SELECT p_tenant_id, v_id, c FROM unnest(v_ids) c
   WHERE NOT EXISTS (SELECT 1 FROM bps.fnd_customer_group_members m WHERE m.group_id = v_id AND m.customer_id = c);
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_customer_group_delete(p_tenant_id bigint, p_group_id bigint) RETURNS void
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE n int;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  DELETE FROM bps.fnd_customer_groups WHERE group_id = p_group_id AND tenant_id = p_tenant_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RAISE EXCEPTION 'Group not found or you may not delete it'; END IF;
END $$;

-- ---------- phone / messaging numbers ----------
CREATE OR REPLACE FUNCTION bps.fnd_phone_numbers_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('phone_number_id', n.phone_number_id, 'phone_number', n.phone_number, 'channel', n.channel,
      'label', n.label, 'is_active', n.is_active) ORDER BY n.channel, n.phone_number), '[]'::jsonb)
  FROM bps.fnd_tenant_phone_numbers n WHERE n.tenant_id = p_tenant_id
$$;

-- payload: {phone_number_id?, phone_number, channel (VOICE|SMS|WHATSAPP), label, is_active}; numbers are stored in E.164 form (+digits).
CREATE OR REPLACE FUNCTION bps.fnd_phone_number_save(p_tenant_id bigint, p_payload jsonb) RETURNS bigint
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_id bigint := NULLIF(p_payload ->> 'phone_number_id', '')::bigint; v_num text := '+' || regexp_replace(COALESCE(p_payload ->> 'phone_number', ''), '[^0-9]', '', 'g');
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF length(v_num) < 8 THEN RAISE EXCEPTION 'Enter the number with country code, e.g. +15551234567'; END IF;
  IF v_id IS NULL THEN
    INSERT INTO bps.fnd_tenant_phone_numbers (tenant_id, phone_number, channel, label, is_active)
    VALUES (p_tenant_id, v_num, upper(COALESCE(p_payload ->> 'channel', 'VOICE')), NULLIF(btrim(p_payload ->> 'label'), ''), COALESCE((p_payload ->> 'is_active')::boolean, true))
    RETURNING phone_number_id INTO v_id;
  ELSE
    UPDATE bps.fnd_tenant_phone_numbers SET phone_number = v_num, channel = upper(COALESCE(p_payload ->> 'channel', channel)),
      label = NULLIF(btrim(p_payload ->> 'label'), ''), is_active = COALESCE((p_payload ->> 'is_active')::boolean, is_active)
     WHERE phone_number_id = v_id AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Number not found'; END IF;
  END IF;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_phone_number_delete(p_tenant_id bigint, p_phone_number_id bigint) RETURNS void
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE n int;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  DELETE FROM bps.fnd_tenant_phone_numbers WHERE phone_number_id = p_phone_number_id AND tenant_id = p_tenant_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RAISE EXCEPTION 'Number not found or you may not delete it'; END IF;
END $$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA bps FROM PUBLIC, anon;
GRANT  EXECUTE ON ALL FUNCTIONS IN SCHEMA bps TO authenticated, service_role, bps_dev;
REVOKE EXECUTE ON FUNCTION
  bps.bps_access_token_hook(jsonb), bps.handle_auth_user_created(), bps.handle_new_user(), bps.fn_audit_log(),
  bps.fnd_tenant_access_seed(bigint), bps.fnd_customer_group_effective_rebuild(bigint),
  bps.fnd_cgm_rebuild_ins(), bps.fnd_cgm_rebuild_del(), bps.fnd_customers_group_sync(), bps.fnd_tenants_access_seed_trg(),
  bps.fnd_ucg_guard(), bps.fnd_user_roles_guard(), bps.fnd_roles_guard(), bps.fnd_groups_guard(), bps.fnd_role_access_guard(),
  bps.fnd_users_guard(), bps.fnd_cgm_before(), bps.fnd_cgm_no_update()
FROM authenticated;
GRANT EXECUTE ON FUNCTION bps.bps_access_token_hook(jsonb) TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION bps.handle_auth_user_created(), bps.handle_new_user() TO supabase_auth_admin;
