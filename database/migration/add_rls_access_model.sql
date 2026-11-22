-- =====================================================================================
-- Access model, step (c): row-level security rewritten for every fnd_/om_/ar_ table.
--
--  * Every policy keys on the ONE active tenancy (app_metadata.tenant_id) and on the caller's role access
--    (fnd_has_access / fnd_has_access_any), and, for customer-linked rows, on data scope (groups for tenant users,
--    own customer tree for customer users). The old allowed_tenant_ids / restricted_tenant_ids lists are no longer used.
--  * anon (the public browser key) gets no table or function access in schema bps.
--  * TRUNCATE / REFERENCES / TRIGGER are revoked from anon and authenticated (TRUNCATE bypasses RLS).
--  * Former SECURITY DEFINER API functions that bypassed RLS now run as the caller (SECURITY INVOKER), so the policies
--    below are the single source of truth. The few helpers that stay definer assert the active tenant.
-- Apply after add_access_model_tables.sql, add_access_model_functions.sql and add_active_tenancy.sql.
-- =====================================================================================
SET search_path = bps, public;

-- ---------- helpers ----------
CREATE OR REPLACE FUNCTION bps.fnd_assert_active_tenant(p_tenant_id bigint) RETURNS void
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  IF bps.fnd_is_trusted() THEN RETURN; END IF;
  IF p_tenant_id IS NULL OR p_tenant_id IS DISTINCT FROM bps.fnd_active_tenant_id() THEN
    RAISE EXCEPTION 'Tenant access denied for tenant_id %', p_tenant_id USING ERRCODE = '42501';
  END IF;
END $$;

-- any of the areas grants the action
CREATE OR REPLACE FUNCTION bps.fnd_has_access_any(p_areas text[], p_action text DEFAULT 'R') RETURNS boolean
LANGUAGE sql STABLE SET search_path = bps, public AS
$$ SELECT EXISTS (SELECT 1 FROM unnest(p_areas) a WHERE bps.fnd_has_access(a, p_action)) $$;

-- the caller holds the action on at least one area of their audience (reference data such as items and valuesets)
CREATE OR REPLACE FUNCTION bps.fnd_has_any_access(p_action text DEFAULT 'R') RETURNS boolean
LANGUAGE sql STABLE SET search_path = bps, public AS
$$ SELECT EXISTS (SELECT 1 FROM bps.fnd_areas a WHERE bps.fnd_has_access(a.area_key, p_action)) $$;

-- Staff = a tenant-side user of the ACTIVE tenancy (trusted connections count as staff).
CREATE OR REPLACE FUNCTION bps.fnd_is_tenant_staff(p_tenant_id bigint) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = bps, public AS $$
BEGIN
  IF bps.fnd_is_trusted() THEN RETURN true; END IF;
  IF p_tenant_id IS NULL OR p_tenant_id IS DISTINCT FROM bps.fnd_active_tenant_id() THEN RETURN false; END IF;
  RETURN EXISTS (SELECT 1 FROM bps.fnd_users u JOIN bps.fnd_user_tenants ut ON ut.user_id = u.user_id AND ut.tenant_id = p_tenant_id AND ut.is_active
                  WHERE u.user_id = bps.fnd_current_user_id() AND u.is_active AND u.deleted_at IS NULL AND u.user_type = 'TENANCY_USER');
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_user_in_active_tenant(p_user_id bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = bps, public AS
$$ SELECT EXISTS (SELECT 1 FROM bps.fnd_user_tenants ut WHERE ut.user_id = p_user_id AND ut.tenant_id = bps.fnd_active_tenant_id() AND ut.is_active) $$;

-- fnd_users: a user may edit their own display preferences, but never their own type, status, tenant or login link.
CREATE OR REPLACE FUNCTION bps.fnd_users_guard() RETURNS trigger LANGUAGE plpgsql SET search_path = bps, public AS $$
BEGIN
  IF bps.fnd_is_trusted() THEN RETURN NEW; END IF;
  IF (NEW.user_type IS DISTINCT FROM OLD.user_type OR NEW.is_active IS DISTINCT FROM OLD.is_active OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
      OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id OR NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id OR NEW.can_debug IS DISTINCT FROM OLD.can_debug)
     AND NOT bps.fnd_has_access('admin.users', 'W') THEN
    RAISE EXCEPTION 'Only a user administrator can change type, status or tenant of a user' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_fnd_users_guard ON bps.fnd_users;
CREATE TRIGGER trg_fnd_users_guard BEFORE UPDATE ON bps.fnd_users FOR EACH ROW EXECUTE FUNCTION bps.fnd_users_guard();

-- ---------- privilege hygiene ----------
REVOKE ALL ON ALL TABLES    IN SCHEMA bps FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA bps FROM anon;
REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA bps FROM authenticated;
-- unprefixed legacy migration tables: nobody but the owners / migration scripts
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'bps' AND c.relkind = 'r' AND c.relname !~ '^(fnd_|om_|ar_)' LOOP
    EXECUTE format('ALTER TABLE bps.%I ENABLE ROW LEVEL SECURITY', r.relname);
    EXECUTE format('REVOKE ALL ON bps.%I FROM authenticated, anon', r.relname);
  END LOOP;
END $$;
-- the tables that had row security switched off
ALTER TABLE bps.fnd_customers      ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_users          ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_user_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_contacts       ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_contact_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.om_standing_orders ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON bps.fnd_contacts, bps.fnd_contact_points, bps.om_standing_orders TO authenticated;
GRANT ALL ON bps.fnd_contacts, bps.fnd_contact_points, bps.om_standing_orders TO bps_dev;
REVOKE ALL ON bps.fnd_slug_registry FROM anon;

-- ---------- policy generator ----------
-- spec: tbl, read areas, write areas, delete areas (NULL = any role), scope column (NULL = none), extra predicate for read, extra for write
CREATE OR REPLACE FUNCTION pg_temp.make_policies(p_tbl text, p_read text[], p_write text[], p_delete text[], p_scope_col text, p_extra text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record; act text := '(tenant_id = (SELECT bps.fnd_active_tenant_id()))'; scope text := ''; extra text := ''; rd text; wr text; dl text;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE schemaname = 'bps' AND tablename = p_tbl LOOP
    EXECUTE format('DROP POLICY %I ON bps.%I', r.policyname, p_tbl);
  END LOOP;
  IF p_scope_col IS NOT NULL THEN
    scope := format(' AND ((SELECT bps.fnd_scope_is_all()) OR %I = ANY (COALESCE((SELECT bps.fnd_scope_customer_ids()), ''{}''::bigint[])))', p_scope_col);
  END IF;
  IF p_extra IS NOT NULL THEN extra := ' AND (' || p_extra || ')'; END IF;
  rd := CASE WHEN p_read  IS NULL THEN '(SELECT bps.fnd_has_any_access(''R''))' ELSE format('(SELECT bps.fnd_has_access_any(%L::text[], ''R''))', p_read) END;
  wr := CASE WHEN p_write IS NULL THEN '(SELECT bps.fnd_has_any_access(''W''))' ELSE format('(SELECT bps.fnd_has_access_any(%L::text[], ''W''))', p_write) END;
  dl := CASE WHEN p_delete IS NULL THEN '(SELECT bps.fnd_has_any_access(''D''))' ELSE format('(SELECT bps.fnd_has_access_any(%L::text[], ''D''))', p_delete) END;
  EXECUTE format('CREATE POLICY pol_%s_read ON bps.%I FOR SELECT TO authenticated USING (bps.fnd_is_trusted() OR (%s AND %s%s%s))', p_tbl, p_tbl, act, rd, scope, extra);
  IF p_write <> ARRAY['-'] THEN
    EXECUTE format('CREATE POLICY pol_%s_ins ON bps.%I FOR INSERT TO authenticated WITH CHECK (bps.fnd_is_trusted() OR (%s AND %s%s%s))', p_tbl, p_tbl, act, wr, scope, extra);
    EXECUTE format('CREATE POLICY pol_%s_upd ON bps.%I FOR UPDATE TO authenticated USING (bps.fnd_is_trusted() OR (%s AND %s%s%s)) WITH CHECK (bps.fnd_is_trusted() OR (%s AND %s%s%s))', p_tbl, p_tbl, act, wr, scope, extra, act, wr, scope, extra);
  END IF;
  IF p_delete <> ARRAY['-'] THEN
    EXECUTE format('CREATE POLICY pol_%s_del ON bps.%I FOR DELETE TO authenticated USING (bps.fnd_is_trusted() OR (%s AND %s%s%s))', p_tbl, p_tbl, act, dl, scope, extra);
  END IF;
END $$;

-- Area groups (read lists include the customer-portal areas where portal users legitimately see the rows).
-- Orders and everything that prints, ships or bills from them
SELECT pg_temp.make_policies('om_orders',
  ARRAY['orders.enter','orders.manage','orders.standing-post','production.process','production.report','production.labels','production.packaging','production.routes','production.deliveries','financials.ar','financials.credits','financials.statements','portal.orders','portal.order-history'],
  ARRAY['orders.enter','orders.manage','orders.standing-post','production.process','portal.orders'],
  ARRAY['orders.manage','portal.orders'], 'customer_id');
SELECT pg_temp.make_policies('om_order_lines',
  ARRAY['orders.enter','orders.manage','orders.standing-post','production.process','production.report','production.labels','production.packaging','production.routes','production.deliveries','financials.ar','financials.credits','financials.statements','portal.orders','portal.order-history'],
  ARRAY['orders.enter','orders.manage','orders.standing-post','production.process','production.deliveries','portal.orders'],
  ARRAY['orders.manage','portal.orders'], NULL, 'order_id IN (SELECT order_id FROM bps.om_orders)');
SELECT pg_temp.make_policies('om_standing_orders',
  ARRAY['orders.standing-mgmt','orders.standing-post','orders.enter','portal.orders'],
  ARRAY['orders.standing-mgmt','portal.orders'], ARRAY['orders.standing-mgmt','portal.orders'], 'customer_id');
-- Production settings and runs
SELECT pg_temp.make_policies('om_production_codes', NULL, ARRAY['admin.production'], ARRAY['admin.production'], NULL);
SELECT pg_temp.make_policies('om_delivery_methods',  NULL, ARRAY['admin.production'], ARRAY['admin.production'], NULL);
SELECT pg_temp.make_policies('om_production_runs',   NULL,
  ARRAY['production.process','production.report','production.labels','production.packaging','production.routes','production.deliveries','admin.production'],
  ARRAY['admin.production'], NULL);
SELECT pg_temp.make_policies('om_shipments',
  ARRAY['production.deliveries','production.process','production.routes','production.packaging','production.labels','financials.ar','financials.credits'],
  ARRAY['production.process','production.deliveries'], ARRAY['production.process'], 'ship_to_customer_id');
SELECT pg_temp.make_policies('om_shipment_lines',
  ARRAY['production.deliveries','production.process','production.routes','production.packaging','production.labels','financials.ar','financials.credits'],
  ARRAY['production.process','production.deliveries'], ARRAY['production.process'], NULL, 'shipment_id IN (SELECT shipment_id FROM bps.om_shipments)');
-- Receivables
SELECT pg_temp.make_policies('ar_transactions',
  ARRAY['financials.ar','financials.aging','financials.statements','financials.credits','financials.payments','financials.sales','production.packaging','production.process','production.deliveries','portal.invoicing','portal.invoice-history'],
  ARRAY['financials.credits','financials.payments','production.process','production.packaging','production.deliveries'],
  ARRAY['financials.credits','production.process'], 'customer_id');
SELECT pg_temp.make_policies('ar_transaction_lines',
  ARRAY['financials.ar','financials.aging','financials.statements','financials.credits','financials.payments','financials.sales','production.packaging','production.process','production.deliveries','portal.invoicing','portal.invoice-history'],
  ARRAY['financials.credits','financials.payments','production.process','production.packaging','production.deliveries'],
  ARRAY['financials.credits','production.process'], NULL, 'ar_transaction_id IN (SELECT ar_transaction_id FROM bps.ar_transactions)');
SELECT pg_temp.make_policies('ar_payments',
  ARRAY['financials.payments','financials.cash','financials.ar','portal.payments','portal.payment-history'],
  ARRAY['financials.payments','portal.payments'], ARRAY['financials.payments'], 'customer_id');
SELECT pg_temp.make_policies('ar_payment_applications',
  ARRAY['financials.payments','financials.cash','financials.ar','portal.payments','portal.payment-history'],
  ARRAY['financials.payments'], ARRAY['financials.payments'], NULL, 'ar_payment_id IN (SELECT ar_payment_id FROM bps.ar_payments)');
-- Customers and what hangs off them
SELECT pg_temp.make_policies('fnd_customers', NULL, ARRAY['customers.profiles'], ARRAY['customers.profiles'], 'customer_id');
SELECT pg_temp.make_policies('fnd_customer_pricebooks',
  ARRAY['customers.pricing','customers.profiles','orders.enter','orders.manage','portal.orders'],
  ARRAY['customers.pricing','customers.profiles'], ARRAY['customers.pricing','customers.profiles'], 'customer_id');
SELECT pg_temp.make_policies('fnd_contacts', NULL, ARRAY['customers.profiles','inventory.item-profile'], ARRAY['customers.profiles','inventory.item-profile'], NULL,
  $x$source_table <> 'fnd_customers' OR (SELECT bps.fnd_scope_is_all()) OR entity_id = ANY (COALESCE((SELECT bps.fnd_scope_customer_ids()), '{}'::bigint[]))$x$);
SELECT pg_temp.make_policies('fnd_contact_points', NULL, ARRAY['customers.profiles','inventory.item-profile'], ARRAY['customers.profiles','inventory.item-profile'], NULL,
  'contact_id IN (SELECT contact_id FROM bps.fnd_contacts)');
SELECT pg_temp.make_policies('fnd_notes', NULL, ARRAY['customers.profiles','inventory.item-profile','orders.manage','orders.enter'], ARRAY['customers.profiles','inventory.item-profile','orders.manage'], NULL,
  $x$source_table <> 'fnd_customers' OR (SELECT bps.fnd_scope_is_all()) OR entity_id = ANY (COALESCE((SELECT bps.fnd_scope_customer_ids()), '{}'::bigint[]))$x$);
-- Items, prices, value lists
SELECT pg_temp.make_policies('fnd_items',    NULL, ARRAY['inventory.item-profile','inventory.manage'], ARRAY['inventory.item-profile','inventory.manage'], NULL);
SELECT pg_temp.make_policies('fnd_item_bom', NULL, ARRAY['inventory.item-profile','inventory.manage'], ARRAY['inventory.item-profile','inventory.manage'], NULL);
SELECT pg_temp.make_policies('fnd_pricebooks',
  ARRAY['customers.pricing','inventory.pricing','inventory.item-profile','customers.profiles','orders.enter','orders.manage'],
  ARRAY['customers.pricing','inventory.pricing'], ARRAY['customers.pricing','inventory.pricing'], NULL);
-- a portal user sees only price books assigned to customers inside their own scope
CREATE POLICY pol_fnd_pricebooks_assigned ON bps.fnd_pricebooks FOR SELECT TO authenticated USING (
  tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('portal.orders', 'R'))
  AND pricebook_id IN (SELECT pricebook_id FROM bps.fnd_customer_pricebooks));
SELECT pg_temp.make_policies('fnd_pricebook_items', NULL, ARRAY['inventory.pricing','inventory.item-profile','customers.pricing'], ARRAY['inventory.pricing','inventory.item-profile','customers.pricing'], NULL,
  'pricebook_id IN (SELECT pricebook_id FROM bps.fnd_pricebooks)');
SELECT pg_temp.make_policies('fnd_valuesets',       NULL, ARRAY['admin.production','inventory.item-profile','customers.profiles'], ARRAY['admin.production'], NULL);
SELECT pg_temp.make_policies('fnd_valueset_values', NULL, ARRAY['admin.production','inventory.item-profile','customers.profiles'], ARRAY['admin.production'], NULL);
-- Settings and logs
SELECT pg_temp.make_policies('fnd_tenant_sequences', ARRAY['admin.production'], ARRAY['admin.production'], ARRAY['-'], NULL);
SELECT pg_temp.make_policies('fnd_audit_log', ARRAY['admin.roles'], ARRAY['-'], ARRAY['-'], NULL);

-- ---------- tenant guard inside the remaining SECURITY DEFINER helpers ----------

CREATE OR REPLACE FUNCTION bps.fnd_tenant_sequence_next(p_tenant_id bigint, p_sequence_name text, p_context_date date DEFAULT CURRENT_DATE)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_sequence fnd_tenant_sequences%ROWTYPE;
    v_reset_key TEXT;
    v_value BIGINT;
    v_result TEXT;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;

    IF NULLIF(TRIM(p_sequence_name), '') IS NULL THEN
        RAISE EXCEPTION 'p_sequence_name is required';
    END IF;

    SELECT *
      INTO v_sequence
      FROM fnd_tenant_sequences
     WHERE tenant_id = p_tenant_id
       AND sequence_name = TRIM(p_sequence_name)
       AND is_active = TRUE
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tenant sequence % was not found for tenant %', p_sequence_name, p_tenant_id;
    END IF;

    v_reset_key := fnd_tenant_sequence_reset_key(v_sequence.reset_period, p_context_date);

    IF v_reset_key IS NOT NULL
       AND v_sequence.last_reset_key IS DISTINCT FROM v_reset_key THEN
        v_sequence.next_value := v_sequence.start_value;
        v_sequence.last_reset_key := v_reset_key;
    END IF;

    v_value := v_sequence.next_value;
    v_result := fnd_tenant_sequence_format(v_sequence.mask, v_value, p_context_date);

    UPDATE fnd_tenant_sequences
       SET next_value = v_value + v_sequence.increment_by,
           last_reset_key = v_sequence.last_reset_key,
           updated_at = now()
     WHERE tenant_id = p_tenant_id
       AND sequence_name = TRIM(p_sequence_name);

    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION bps.om_production_run_get_or_create(p_tenant_id bigint, p_production_date date, p_production_code text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE
    v_claims jsonb := NULLIF(current_setting('request.jwt.claims', true), '')::jsonb;
    v_code   text  := NULLIF(UPPER(TRIM(p_production_code)), '');
    v_pc     om_production_codes%ROWTYPE;
    v_id     bigint;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
    IF p_tenant_id IS NULL THEN
        RAISE EXCEPTION 'p_tenant_id is required';
    END IF;
    IF v_claims IS NOT NULL AND NOT (p_tenant_id::text = ANY (ARRAY(
            SELECT jsonb_array_elements_text(v_claims -> 'app_metadata' -> 'allowed_tenant_ids')))) THEN
        RAISE EXCEPTION 'Not authorised for tenant %', p_tenant_id;
    END IF;
    IF p_production_date IS NULL OR v_code IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT production_run_id INTO v_id
      FROM om_production_runs
     WHERE tenant_id = p_tenant_id AND production_date = p_production_date AND production_code = v_code;
    IF v_id IS NOT NULL THEN
        RETURN v_id;
    END IF;

    SELECT * INTO v_pc
      FROM om_production_codes
     WHERE tenant_id = p_tenant_id AND production_code = v_code AND is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Production code % has no cutoff settings for this tenant (Admin > Production Codes).', v_code;
    END IF;

    INSERT INTO om_production_runs (tenant_id, production_date, production_code, delivery_date, cutoff_at)
    VALUES (
        p_tenant_id, p_production_date, v_code,
        p_production_date + v_pc.delivery_days_after,
        bps.om_production_cutoff_calc(p_tenant_id, p_production_date, v_code)
    )
    ON CONFLICT (tenant_id, production_date, production_code) DO NOTHING
    RETURNING production_run_id INTO v_id;

    IF v_id IS NULL THEN
        SELECT production_run_id INTO v_id
          FROM om_production_runs
         WHERE tenant_id = p_tenant_id AND production_date = p_production_date AND production_code = v_code;
    END IF;
    RETURN v_id;
END;
$function$;


CREATE OR REPLACE FUNCTION bps.fnd_tenant_time_zone(p_tenant_id bigint)
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'bps', 'public' AS $$
    SELECT t.time_zone FROM bps.fnd_tenants t
     WHERE t.tenant_id = p_tenant_id AND (bps.fnd_is_trusted() OR p_tenant_id = bps.fnd_active_tenant_id());
$$;

CREATE OR REPLACE FUNCTION bps.om_customer_cutoff_extra_minutes(p_tenant_id bigint, p_customer_id bigint)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'bps', 'public' AS $$
    WITH RECURSIVE up AS (
        SELECT c.customer_id, c.customer_parent_id, c.cutoff_extra_minutes, 0 AS depth
          FROM fnd_customers c
         WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
           AND (bps.fnd_is_trusted() OR p_tenant_id = bps.fnd_active_tenant_id())
        UNION ALL
        SELECT c.customer_id, c.customer_parent_id, c.cutoff_extra_minutes, up.depth + 1
          FROM fnd_customers c JOIN up ON c.customer_id = up.customer_parent_id
         WHERE c.tenant_id = p_tenant_id AND up.depth < 10
    )
    SELECT COALESCE((SELECT cutoff_extra_minutes FROM up WHERE cutoff_extra_minutes IS NOT NULL ORDER BY depth LIMIT 1), 0);
$$;

CREATE OR REPLACE FUNCTION bps.om_customer_ship_address(p_tenant_id bigint, p_customer_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'bps', 'public'
AS $function$
BEGIN
    IF NOT bps.fnd_is_tenant_staff(p_tenant_id) OR NOT bps.fnd_customer_in_scope(p_customer_id) THEN
        RETURN NULL;
    END IF;
    RETURN (SELECT cp.value
              FROM fnd_contacts ct
              JOIN fnd_contact_points cp ON cp.contact_id = ct.contact_id AND cp.tenant_id = ct.tenant_id
             WHERE ct.tenant_id = p_tenant_id AND ct.entity_id = p_customer_id AND ct.source_table = 'fnd_customers'
               AND cp.type = 'ADDRESS' AND cp.is_active
             ORDER BY cp.use_as_shipping DESC, cp.is_primary DESC, cp.sequence
             LIMIT 1);
END;
$function$;

-- fnd_tenants_get returns only the active tenancy once one is selected
CREATE OR REPLACE FUNCTION bps.fnd_tenants_get()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_ctx      record;
  v_result   jsonb;
  v_jwt_raw  text;
  v_claims   jsonb;
BEGIN
  -- 1. Grab the raw string. This is a GUC, not a schema object.
  v_jwt_raw := current_setting('request.jwt.claims', true);
  
  -- 2. Convert to JSONB.
  v_claims := COALESCE(NULLIF(v_jwt_raw, ''), '{}')::jsonb;

  -- 3. Resolve the user from the UUID string in the claims
  WITH resolved AS (
    SELECT 
      u.user_id,
      u.tenant_id AS primary_tenant_id,
      COALESCE(u.can_debug, false) AS can_debug,
      COALESCE(current_setting('request.method.query.debug', true) = 'true', false) AS debug_requested
    FROM fnd_users u
    WHERE u.auth_user_id = (v_claims ->> 'sub')::uuid
      AND u.is_active IS TRUE
    LIMIT 1
  )
  SELECT 
    *, 
    (can_debug AND debug_requested) AS is_debug 
  INTO v_ctx 
  FROM resolved;

  -- 4. Handshake Guard
  IF v_ctx.user_id IS NULL THEN
    RAISE EXCEPTION 'BPS_AUTH_ERROR: User sub % not found in fnd_users', (v_claims ->> 'sub');
  END IF;

  -- 5. Debug Logging (The whole point of today!)
  IF v_ctx.is_debug THEN
    RAISE NOTICE 'BPS_DEBUG: Handshake successful for user_id: %', v_ctx.user_id;
  END IF;

  -- 6. Fetch Tenants
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'tenant_id', tnt.tenant_id,
        'tenant_name', tnt.tenant_name,
        'is_primary', (tnt.tenant_id = v_ctx.primary_tenant_id)
      )
      ORDER BY tnt.tenant_name, tnt.tenant_id
    ),
    '[]'::jsonb
  ) INTO v_result
  FROM fnd_user_tenants ut
  JOIN fnd_tenants tnt ON tnt.tenant_id = ut.tenant_id
  WHERE ut.user_id = v_ctx.user_id
    AND ut.is_active IS TRUE
    AND (bps.fnd_active_tenant_id() IS NULL OR ut.tenant_id = bps.fnd_active_tenant_id());

  IF v_ctx.is_debug THEN
    RAISE NOTICE 'BPS_DEBUG: Found % tenants.', jsonb_array_length(v_result);
  END IF;

  RETURN v_result;
END;
$function$;


-- ---------- former SECURITY DEFINER API functions now run as the caller, so RLS applies ----------
ALTER FUNCTION bps.fnd_contacts_get(bigint, bigint, text) SECURITY INVOKER;
ALTER FUNCTION bps.fnd_contacts_save(bigint, bigint, text, jsonb) SECURITY INVOKER;
ALTER FUNCTION bps.fnd_customer_pricebooks_get(bigint, bigint) SECURITY INVOKER;
ALTER FUNCTION bps.fnd_customer_pricebooks_save(bigint, bigint, jsonb) SECURITY INVOKER;
ALTER FUNCTION bps.fnd_customers_save(bigint, bigint, text, jsonb) SECURITY INVOKER;
ALTER FUNCTION bps.fnd_notes_delete(bigint, bigint) SECURITY INVOKER;
ALTER FUNCTION bps.fnd_notes_save(bigint, jsonb) SECURITY INVOKER;
ALTER FUNCTION bps.fnd_pricebook_items_get(bigint, bigint) SECURITY INVOKER;
ALTER FUNCTION bps.fnd_pricebook_items_save(bigint, bigint, jsonb) SECURITY INVOKER;
ALTER FUNCTION bps.om_post_standing_orders_list(bigint, date, text[]) SECURITY INVOKER;
ALTER FUNCTION bps.om_standing_orders_get(bigint, bigint, text, text) SECURITY INVOKER;
ALTER FUNCTION bps.om_standing_orders_save(bigint, bigint, text[], text, jsonb) SECURITY INVOKER;
ALTER FUNCTION bps.om_invoices_get(bigint, bigint, date, text, bigint) SECURITY INVOKER;
ALTER FUNCTION bps.get_customers(bigint) SECURITY INVOKER;
ALTER FUNCTION bps.get_customers_debug(bigint) SECURITY INVOKER;
ALTER FUNCTION bps.get_tenants() SECURITY INVOKER;

-- ---------- users, memberships, tenants ----------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'bps'
            AND tablename IN ('fnd_users','fnd_user_tenants','fnd_user_customers','fnd_tenants','fnd_user_recent_records') LOOP
    EXECUTE format('DROP POLICY %I ON bps.%I', r.policyname, r.tablename);
  END LOOP;
END $$;

CREATE POLICY pol_fnd_users_read ON bps.fnd_users FOR SELECT TO authenticated USING (
  bps.fnd_is_trusted() OR user_id = (SELECT bps.fnd_current_user_id())
  OR (bps.fnd_user_in_active_tenant(user_id) AND ((SELECT bps.fnd_has_access('admin.users','R'))
      OR ((SELECT bps.fnd_has_access('portal.users','R')) AND bps.fnd_user_in_customer_scope(user_id)))));
CREATE POLICY pol_fnd_users_ins ON bps.fnd_users FOR INSERT TO authenticated WITH CHECK (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.users','W'))));
CREATE POLICY pol_fnd_users_upd ON bps.fnd_users FOR UPDATE TO authenticated USING (
  bps.fnd_is_trusted() OR user_id = (SELECT bps.fnd_current_user_id())
  OR (bps.fnd_user_in_active_tenant(user_id) AND (SELECT bps.fnd_has_access('admin.users','W'))))
  WITH CHECK (bps.fnd_is_trusted() OR user_id = (SELECT bps.fnd_current_user_id())
  OR (bps.fnd_user_in_active_tenant(user_id) AND (SELECT bps.fnd_has_access('admin.users','W'))));
CREATE POLICY pol_fnd_users_del ON bps.fnd_users FOR DELETE TO authenticated USING (
  bps.fnd_is_trusted() OR (bps.fnd_user_in_active_tenant(user_id) AND (SELECT bps.fnd_has_access('admin.users','D'))));

CREATE POLICY pol_fnd_user_tenants_read ON bps.fnd_user_tenants FOR SELECT TO authenticated USING (
  bps.fnd_is_trusted() OR user_id = (SELECT bps.fnd_current_user_id())
  OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND ((SELECT bps.fnd_has_access('admin.users','R'))
      OR ((SELECT bps.fnd_has_access('portal.users','R')) AND bps.fnd_user_in_customer_scope(user_id)))));
CREATE POLICY pol_fnd_user_tenants_ins ON bps.fnd_user_tenants FOR INSERT TO authenticated WITH CHECK (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.users','W'))));
CREATE POLICY pol_fnd_user_tenants_upd ON bps.fnd_user_tenants FOR UPDATE TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.users','W'))))
  WITH CHECK (bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.users','W'))));
CREATE POLICY pol_fnd_user_tenants_del ON bps.fnd_user_tenants FOR DELETE TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.users','D'))));

CREATE POLICY pol_fnd_user_customers_read ON bps.fnd_user_customers FOR SELECT TO authenticated USING (
  bps.fnd_is_trusted() OR user_id = (SELECT bps.fnd_current_user_id())
  OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND ((SELECT bps.fnd_has_access('admin.users','R'))
      OR ((SELECT bps.fnd_has_access('portal.users','R')) AND customer_id = ANY (COALESCE((SELECT bps.fnd_scope_customer_ids()), '{}'::bigint[]))))));
CREATE POLICY pol_fnd_user_customers_ins ON bps.fnd_user_customers FOR INSERT TO authenticated WITH CHECK (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND ((SELECT bps.fnd_has_access('admin.users','W'))
      OR ((SELECT bps.fnd_has_access('portal.users','W')) AND customer_id = ANY (COALESCE((SELECT bps.fnd_scope_customer_ids()), '{}'::bigint[]))))));
CREATE POLICY pol_fnd_user_customers_upd ON bps.fnd_user_customers FOR UPDATE TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND ((SELECT bps.fnd_has_access('admin.users','W'))
      OR ((SELECT bps.fnd_has_access('portal.users','W')) AND customer_id = ANY (COALESCE((SELECT bps.fnd_scope_customer_ids()), '{}'::bigint[]))))))
  WITH CHECK (bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND ((SELECT bps.fnd_has_access('admin.users','W'))
      OR ((SELECT bps.fnd_has_access('portal.users','W')) AND customer_id = ANY (COALESCE((SELECT bps.fnd_scope_customer_ids()), '{}'::bigint[]))))));
CREATE POLICY pol_fnd_user_customers_del ON bps.fnd_user_customers FOR DELETE TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND ((SELECT bps.fnd_has_access('admin.users','D'))
      OR ((SELECT bps.fnd_has_access('portal.users','D')) AND customer_id = ANY (COALESCE((SELECT bps.fnd_scope_customer_ids()), '{}'::bigint[]))))));

CREATE POLICY pol_fnd_tenants_read ON bps.fnd_tenants FOR SELECT TO authenticated USING (
  bps.fnd_is_trusted() OR tenant_id = (SELECT bps.fnd_active_tenant_id()));
CREATE POLICY pol_fnd_tenants_upd ON bps.fnd_tenants FOR UPDATE TO authenticated USING (
  bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.roles','W'))))
  WITH CHECK (bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.roles','W'))));

CREATE POLICY pol_fnd_user_recent_records_owner ON bps.fnd_user_recent_records FOR ALL TO authenticated
  USING (user_id = (SELECT bps.fnd_nav_app_user_id()) AND tenant_id = (SELECT bps.fnd_active_tenant_id()))
  WITH CHECK (user_id = (SELECT bps.fnd_nav_app_user_id()) AND tenant_id = (SELECT bps.fnd_active_tenant_id()));

-- ---------- function privileges: nothing for anon / PUBLIC; the caller roles get what the policies and guards police ----------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA bps FROM PUBLIC, anon;
GRANT  EXECUTE ON ALL FUNCTIONS IN SCHEMA bps TO authenticated, service_role, bps_dev;
GRANT  EXECUTE ON FUNCTION bps.bps_access_token_hook(jsonb) TO supabase_auth_admin;
GRANT  EXECUTE ON FUNCTION bps.handle_auth_user_created(), bps.handle_new_user() TO supabase_auth_admin;
-- internal helpers and trigger functions are not callable by app users
REVOKE EXECUTE ON FUNCTION
  bps.bps_access_token_hook(jsonb), bps.handle_auth_user_created(), bps.handle_new_user(), bps.fn_audit_log(),
  bps.fnd_tenant_access_seed(bigint), bps.fnd_customer_group_effective_rebuild(bigint),
  bps.fnd_cgm_rebuild_ins(), bps.fnd_cgm_rebuild_del(), bps.fnd_customers_group_sync(), bps.fnd_tenants_access_seed_trg(),
  bps.fnd_ucg_guard(), bps.fnd_user_roles_guard(), bps.fnd_roles_guard(), bps.fnd_groups_guard(), bps.fnd_role_access_guard(),
  bps.fnd_users_guard(), bps.fnd_cgm_before(), bps.fnd_cgm_no_update()
FROM authenticated;

-- A cutoff applies to callers who are not tenant staff (customer-side users); staff and trusted connections are exempt.
CREATE OR REPLACE FUNCTION bps.om_production_cutoff_assert(p_tenant_id bigint, p_production_date date, p_production_code text, p_customer_id bigint DEFAULT NULL::bigint)
 RETURNS void LANGUAGE plpgsql STABLE SET search_path TO 'bps', 'public' AS $function$
DECLARE
    v_info jsonb;
BEGIN
    IF bps.fnd_is_tenant_staff(p_tenant_id) THEN
        RETURN;
    END IF;

    v_info := bps.om_production_cutoff_get(p_tenant_id, p_production_date, p_production_code, p_customer_id);
    IF (v_info ->> 'is_open')::boolean THEN
        RETURN;
    END IF;

    RAISE EXCEPTION 'Ordering for % (%) closed %. Please call the bakery to add or change this order.',
        p_production_date, UPPER(TRIM(p_production_code)),
        COALESCE(to_char((v_info ->> 'effective_cutoff_at')::timestamptz AT TIME ZONE (v_info ->> 'time_zone'),
                         'Dy Mon DD "at" HH12:MI AM'), 'already');
END;
$function$;
