-- =====================================================================================
-- Health checks: a daily checker for setup and data consistency. Findings are logged and shown by the heart icon in the top bar
-- (grey = never run, green = clean, yellow = warnings, red blinking = errors; Information never changes the colour).
-- New tables (two): fnd_health_checks (one row per company per check: enabled flag and last result) and fnd_health_log
-- (one row per finding, type Information / Warning / Error, with remediation and fixed when/by).
-- New area admin.health. Checks are SQL functions fnd_hc_<code>(tenant) returning findings; the runner fnd_health_run reconciles
-- them with the log: a finding that is gone is closed automatically, a new one is opened.
-- Scheduling: fnd_health_run_due() runs every company whose local time is in the midnight hour and that has not run today.
-- Call it from pg_cron every hour (not installed locally):  SELECT cron.schedule('health-checks', '5 * * * *', 'SELECT bps.fnd_health_run_due()');
-- Run after add_compound_items.sql and add_pricebook_status_and_disable.sql.
-- =====================================================================================
SET search_path = bps, public;

CREATE TABLE bps.fnd_health_checks (
  tenant_id              bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  check_code             text   NOT NULL,
  name                   text   NOT NULL,
  category               text   NOT NULL CHECK (category IN ('Setup', 'Data')),
  description            text,
  runs_before_production boolean NOT NULL DEFAULT false,
  is_enabled             boolean NOT NULL DEFAULT true,
  sort_order             integer NOT NULL DEFAULT 0,
  last_run_at            timestamptz,
  last_infos             integer NOT NULL DEFAULT 0,
  last_warnings          integer NOT NULL DEFAULT 0,
  last_errors            integer NOT NULL DEFAULT 0,
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             bigint,
  PRIMARY KEY (tenant_id, check_code)
);

CREATE TABLE bps.fnd_health_log (
  log_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id     bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  check_code    text   NOT NULL,
  type          text   NOT NULL CHECK (type IN ('Information', 'Warning', 'Error')),
  run_trigger   text   NOT NULL DEFAULT 'Manual' CHECK (run_trigger IN ('Scheduled', 'Manual', 'Production Run')),
  found_at      timestamptz NOT NULL DEFAULT now(),
  findings      text   NOT NULL,
  remediation   text,
  record_type   text,
  record_id     bigint,
  customer_id   bigint,
  link_path     text,
  fixed_at      timestamptz,
  fixed_by      bigint,
  FOREIGN KEY (tenant_id, check_code) REFERENCES bps.fnd_health_checks(tenant_id, check_code) ON DELETE CASCADE
);
CREATE INDEX idx_fnd_health_log_open ON bps.fnd_health_log (tenant_id, check_code) WHERE fixed_at IS NULL;
COMMENT ON TABLE bps.fnd_health_log IS 'Findings of the health checks. Open while fixed_at is NULL; fixed_by NULL with fixed_at set means the next run found it fixed.';

REVOKE ALL ON bps.fnd_health_checks, bps.fnd_health_log FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE ON bps.fnd_health_checks, bps.fnd_health_log TO authenticated;
GRANT ALL ON bps.fnd_health_checks, bps.fnd_health_log TO bps_dev, service_role;
ALTER TABLE bps.fnd_health_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.fnd_health_log ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['fnd_health_checks', 'fnd_health_log'] LOOP
    EXECUTE format($f$CREATE POLICY pol_%1$s_read ON bps.%1$s FOR SELECT TO authenticated USING (
      bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.health','R'))))$f$, t);
    EXECUTE format($f$CREATE POLICY pol_%1$s_ins ON bps.%1$s FOR INSERT TO authenticated WITH CHECK (
      bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.health','W'))))$f$, t);
    EXECUTE format($f$CREATE POLICY pol_%1$s_upd ON bps.%1$s FOR UPDATE TO authenticated
      USING (bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.health','W'))))
      WITH CHECK (bps.fnd_is_trusted() OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('admin.health','W'))))$f$, t);
  END LOOP;
END $$;

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('admin.health', 'Admin', 'Health Checks', 'TENANT', 608) ON CONFLICT (area_key) DO NOTHING;
DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

-- ---------- the list of checks ----------
CREATE OR REPLACE FUNCTION bps.fnd_health_catalog()
RETURNS TABLE (check_code text, name text, category text, description text, runs_before_production boolean, sort_order integer)
LANGUAGE sql IMMUTABLE SET search_path = bps, public AS $$
  SELECT * FROM (VALUES
    ('users_without_role',          'Users without a role',                     'Setup', 'Active users who have no role and so can open nothing.', false, 10),
    ('accounts_without_pricebook',  'Accounts without a pricing book',          'Setup', 'Active accounts with no active, Approved pricing book assigned.', false, 20),
    ('accounts_without_contact',    'Accounts without a contact',               'Setup', 'Active accounts with no contact person.', false, 30),
    ('accounts_without_address',    'Accounts without an address',              'Setup', 'Active accounts with no address.', false, 40),
    ('compound_without_components', 'Compound items without components',        'Setup', 'Active compound items that have no components, so nothing is produced for them.', false, 50),
    ('compound_inactive_component', 'Compound items with inactive components',  'Setup', 'Active compound items that include an inactive item.', false, 60),
    ('pricebook_unused',            'Pricing books not used',                    'Setup', 'Active pricing books none of whose customers has ordered within the Stale years (Application Settings > Pricing). Also refreshes each book''s last-used date.', false, 70),
    ('orders_without_pricebook',    'Orders without a pricing book',             'Data',  'Upcoming orders whose account has no active, Approved pricing book in effect for the delivery date.', true, 110),
    ('orders_unpriced_lines',       'Orders with unpriced lines',                'Data',  'Upcoming orders with a line that no pricing book priced.', true, 120),
    ('payments_over_applied',       'Payments applied for more than received',   'Data',  'Payments whose applications to invoices add up to more than the payment amount.', false, 130),
    ('items_stale',                 'Items not ordered',                         'Data',  'Active items not ordered within the Stale years (Application Settings > Pricing). Also refreshes each item''s last-ordered date.', false, 140)
  ) v(check_code, name, category, description, runs_before_production, sort_order)
$$;

-- Adds the catalog rows a company is missing (never changes an existing row's enabled flag or result).
CREATE OR REPLACE FUNCTION bps.fnd_health_checks_ensure(p_tenant_id bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  INSERT INTO bps.fnd_health_checks (tenant_id, check_code, name, category, description, runs_before_production, sort_order)
  SELECT p_tenant_id, c.check_code, c.name, c.category, c.description, c.runs_before_production, c.sort_order FROM bps.fnd_health_catalog() c
  ON CONFLICT (tenant_id, check_code) DO UPDATE SET name = EXCLUDED.name, category = EXCLUDED.category, description = EXCLUDED.description,
    runs_before_production = EXCLUDED.runs_before_production, sort_order = EXCLUDED.sort_order;
END $$;

-- ---------- the checks: each returns its current findings ----------
CREATE OR REPLACE FUNCTION bps.fnd_hc_users_without_role(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', 'User ' || COALESCE(u.user_name, u.email, u.user_id::text) || ' has no role.', 'Give the user a role in Admin > Users.', 'USER', u.user_id, NULL::bigint, '/admin/users'
    FROM bps.fnd_users u JOIN bps.fnd_user_tenants ut ON ut.user_id = u.user_id AND ut.tenant_id = p_tenant_id AND ut.is_active
   WHERE u.is_active AND u.deleted_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM bps.fnd_user_roles ur WHERE ur.user_id = u.user_id AND ur.tenant_id = p_tenant_id)
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_accounts_without_pricebook(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', 'Account ' || c.customer_name || ' has no active, Approved pricing book.', 'Assign a pricing book and approve it on the customer''s Pricing tab.',
         'CUSTOMER', c.customer_id, c.customer_id, '/customers?customer=' || c.customer_id
    FROM bps.fnd_customers c
   WHERE c.tenant_id = p_tenant_id AND c.customer_type = 'ACCOUNT' AND c.is_active
     AND NOT EXISTS (SELECT 1 FROM bps.fnd_customer_pricebooks cp WHERE cp.customer_id = c.customer_id AND cp.is_active AND cp.status = 'Approved')
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_accounts_without_contact(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', 'Account ' || c.customer_name || ' has no contact person.', 'Add a contact on the customer''s Contacts tab.',
         'CUSTOMER', c.customer_id, c.customer_id, '/customers?customer=' || c.customer_id
    FROM bps.fnd_customers c
   WHERE c.tenant_id = p_tenant_id AND c.customer_type = 'ACCOUNT' AND c.is_active
     AND NOT EXISTS (SELECT 1 FROM bps.fnd_contacts k WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.entity_id = c.customer_id
                        AND k.is_active AND k.contact_type = 'PERSON')
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_accounts_without_address(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', 'Account ' || c.customer_name || ' has no address.', 'Add an address on the customer''s Contacts tab.',
         'CUSTOMER', c.customer_id, c.customer_id, '/customers?customer=' || c.customer_id
    FROM bps.fnd_customers c
   WHERE c.tenant_id = p_tenant_id AND c.customer_type = 'ACCOUNT' AND c.is_active
     AND NOT EXISTS (SELECT 1 FROM bps.fnd_contacts k JOIN bps.fnd_contact_points cpt ON cpt.contact_id = k.contact_id AND cpt.type = 'ADDRESS' AND cpt.is_active
                      WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.entity_id = c.customer_id AND k.is_active)
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_compound_without_components(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', 'Compound item ' || COALESCE(i.item_number, '') || ' ' || i.item_name || ' has no components.',
         'Add its components on the item''s Components tab, or turn Compound item off.', 'ITEM', i.item_id, NULL::bigint, '/inventory/item-profile?item=' || i.item_id
    FROM bps.fnd_items i
   WHERE i.tenant_id = p_tenant_id AND i.is_compound AND i.is_active
     AND NOT EXISTS (SELECT 1 FROM bps.fnd_item_bom b WHERE b.parent_item_id = i.item_id)
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_compound_inactive_component(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', 'Compound item ' || COALESCE(i.item_number, '') || ' ' || i.item_name || ' includes inactive item(s): ' || string_agg(COALESCE(c.item_number, '') || ' ' || c.item_name, ', ' ORDER BY c.item_number) || '.',
         'Replace or remove the inactive components on the compound item''s Components tab.', 'ITEM', i.item_id, NULL::bigint, '/inventory/item-profile?item=' || i.item_id
    FROM bps.fnd_items i
    JOIN bps.fnd_item_bom b ON b.parent_item_id = i.item_id
    JOIN bps.fnd_items c ON c.item_id = b.item_id AND NOT c.is_active
   WHERE i.tenant_id = p_tenant_id AND i.is_compound AND i.is_active
   GROUP BY i.item_id, i.item_number, i.item_name
$$;

-- Refreshes the books' last-used dates, then reports the books not used within the company's Stale years as one Information finding.
CREATE OR REPLACE FUNCTION bps.fnd_hc_pricebook_unused(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_years integer; v_cutoff date; n integer;
BEGIN
  PERFORM bps.fnd_pricebooks_last_used_refresh(p_tenant_id);
  SELECT t.pricebook_unused_years INTO v_years FROM bps.fnd_tenants t WHERE t.tenant_id = p_tenant_id;
  v_cutoff := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date - (v_years * 365);
  SELECT count(*) INTO n FROM bps.fnd_pricebooks b WHERE b.tenant_id = p_tenant_id AND b.is_active AND (b.last_used_date IS NULL OR b.last_used_date < v_cutoff);
  IF n > 0 THEN
    RETURN QUERY SELECT 'Information'::text, format('Found %s price book%s not used in over %s year%s.', n, CASE WHEN n = 1 THEN '' ELSE 's' END, v_years, CASE WHEN v_years = 1 THEN '' ELSE 's' END),
      'Review them on the Pricing Books page (Stale filter) and disable the ones you no longer need.', 'PRICEBOOKS'::text, NULL::bigint, NULL::bigint, '/inventory/pricing'::text;
  END IF;
END $$;

-- Refreshes the items' last-ordered dates, then reports the active items not ordered within the Stale years as one Information finding.
CREATE OR REPLACE FUNCTION bps.fnd_hc_items_stale(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_years integer; v_cutoff date; n integer;
BEGIN
  PERFORM bps.fnd_items_last_ordered_refresh(p_tenant_id);
  SELECT t.pricebook_unused_years INTO v_years FROM bps.fnd_tenants t WHERE t.tenant_id = p_tenant_id;
  v_cutoff := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date - (v_years * 365);
  SELECT count(*) INTO n FROM bps.fnd_items i WHERE i.tenant_id = p_tenant_id AND i.is_active AND (i.last_ordered_date IS NULL OR i.last_ordered_date < v_cutoff);
  IF n > 0 THEN
    RETURN QUERY SELECT 'Information'::text, format('Found %s active item%s not ordered in over %s year%s.', n, CASE WHEN n = 1 THEN '' ELSE 's' END, v_years, CASE WHEN v_years = 1 THEN '' ELSE 's' END),
      'Review them on the Item Management page (Stale filter) and make the ones you no longer sell inactive.', 'ITEMS'::text, NULL::bigint, NULL::bigint, '/inventory/item-profile'::text;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_orders_without_pricebook(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Error', 'Order ' || o.order_number || ' for ' || COALESCE(o.customer_name, c.customer_name) || ' (production ' || o.production_date || ') has no pricing book in effect for its delivery date.',
         'Assign and approve a pricing book for the account on its Pricing tab, covering the delivery date.', 'ORDER', o.order_id, o.customer_id, '/manage-orders'
    FROM bps.om_orders o
    JOIN bps.fnd_customers c ON c.customer_id = o.customer_id
   WHERE o.tenant_id = p_tenant_id
     AND o.production_date >= (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date
     AND NOT EXISTS (SELECT 1 FROM bps.fnd_customer_pricebooks cp
                      WHERE cp.tenant_id = p_tenant_id AND cp.customer_id = COALESCE(c.top_customer_id, c.customer_id) AND cp.is_active AND cp.status = 'Approved'
                        AND cp.effective_start_date <= bps.om_delivery_date_calc(p_tenant_id, o.production_date, o.production_code)
                        AND (cp.effective_end_date IS NULL OR cp.effective_end_date >= bps.om_delivery_date_calc(p_tenant_id, o.production_date, o.production_code)))
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_orders_unpriced_lines(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Warning', 'Order ' || o.order_number || ' for ' || COALESCE(o.customer_name, '') || ' has ' || count(*) || ' unpriced line(s).',
         'Add the item to one of the account''s pricing books, or enter a price on the order.', 'ORDER', o.order_id, o.customer_id, '/manage-orders'
    FROM bps.om_orders o JOIN bps.om_order_lines l ON l.order_id = o.order_id AND l.is_unpriced
   WHERE o.tenant_id = p_tenant_id AND o.production_date >= (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date
   GROUP BY o.order_id, o.order_number, o.customer_name, o.customer_id
$$;

CREATE OR REPLACE FUNCTION bps.fnd_hc_payments_over_applied(p_tenant_id bigint)
RETURNS TABLE (type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
LANGUAGE sql STABLE SET search_path = bps, public AS $$
  SELECT 'Error', 'Payment ' || COALESCE(p.payment_number, p.ar_payment_id::text) || ' of ' || p.amount || ' has ' || sum(a.applied_amount) || ' applied to invoices.',
         'Correct the payment applications so they do not exceed the payment.', 'PAYMENT', p.ar_payment_id, p.customer_id, '/financials/ar'
    FROM bps.ar_payments p JOIN bps.ar_payment_applications a ON a.ar_payment_id = p.ar_payment_id
   WHERE p.tenant_id = p_tenant_id
   GROUP BY p.ar_payment_id, p.payment_number, p.amount, p.customer_id
  HAVING sum(a.applied_amount) > p.amount
$$;

-- ---------- the runner ----------
-- Runs the enabled checks (all, or one check_code), opens new findings, updates the ones still found and closes the ones gone.
-- Returns {checks_run, infos, warnings, errors}. Manual runs need Write on admin.health; trusted callers (the schedule) are not checked.
CREATE OR REPLACE FUNCTION bps.fnd_health_run(p_tenant_id bigint, p_trigger text DEFAULT 'Manual', p_check_code text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE c record; v_found jsonb; n_run integer := 0; v_uid bigint := bps.fnd_current_user_id();
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_is_trusted() AND NOT bps.fnd_has_access('admin.health', 'W') THEN RAISE EXCEPTION 'Not authorised to run health checks'; END IF;
  IF p_trigger NOT IN ('Scheduled', 'Manual', 'Production Run') THEN RAISE EXCEPTION 'Invalid trigger %', p_trigger; END IF;
  PERFORM bps.fnd_health_checks_ensure(p_tenant_id);
  FOR c IN SELECT * FROM bps.fnd_health_checks WHERE tenant_id = p_tenant_id AND is_enabled AND (p_check_code IS NULL OR check_code = p_check_code) ORDER BY sort_order LOOP
    EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(f)), ''[]''::jsonb) FROM bps.%I($1) f', 'fnd_hc_' || c.check_code) INTO v_found USING p_tenant_id;

    -- close findings that are gone
    UPDATE bps.fnd_health_log l SET fixed_at = now()
     WHERE l.tenant_id = p_tenant_id AND l.check_code = c.check_code AND l.fixed_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM jsonb_to_recordset(v_found) AS f(type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
                        WHERE COALESCE(f.record_type, '') = COALESCE(l.record_type, '') AND COALESCE(f.record_id, 0) = COALESCE(l.record_id, 0));
    -- refresh the ones still found
    UPDATE bps.fnd_health_log l SET type = f.type, findings = f.findings, remediation = f.remediation, customer_id = f.customer_id, link_path = f.link_path
      FROM jsonb_to_recordset(v_found) AS f(type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
     WHERE l.tenant_id = p_tenant_id AND l.check_code = c.check_code AND l.fixed_at IS NULL
       AND COALESCE(f.record_type, '') = COALESCE(l.record_type, '') AND COALESCE(f.record_id, 0) = COALESCE(l.record_id, 0);
    -- open the new ones
    INSERT INTO bps.fnd_health_log (tenant_id, check_code, type, run_trigger, findings, remediation, record_type, record_id, customer_id, link_path)
    SELECT p_tenant_id, c.check_code, f.type, p_trigger, f.findings, f.remediation, f.record_type, f.record_id, f.customer_id, f.link_path
      FROM jsonb_to_recordset(v_found) AS f(type text, findings text, remediation text, record_type text, record_id bigint, customer_id bigint, link_path text)
     WHERE NOT EXISTS (SELECT 1 FROM bps.fnd_health_log l WHERE l.tenant_id = p_tenant_id AND l.check_code = c.check_code AND l.fixed_at IS NULL
                          AND COALESCE(f.record_type, '') = COALESCE(l.record_type, '') AND COALESCE(f.record_id, 0) = COALESCE(l.record_id, 0));

    UPDATE bps.fnd_health_checks h SET last_run_at = now(), updated_by = v_uid,
      last_infos    = (SELECT count(*) FROM bps.fnd_health_log l WHERE l.tenant_id = p_tenant_id AND l.check_code = c.check_code AND l.fixed_at IS NULL AND l.type = 'Information'),
      last_warnings = (SELECT count(*) FROM bps.fnd_health_log l WHERE l.tenant_id = p_tenant_id AND l.check_code = c.check_code AND l.fixed_at IS NULL AND l.type = 'Warning'),
      last_errors   = (SELECT count(*) FROM bps.fnd_health_log l WHERE l.tenant_id = p_tenant_id AND l.check_code = c.check_code AND l.fixed_at IS NULL AND l.type = 'Error')
     WHERE h.tenant_id = p_tenant_id AND h.check_code = c.check_code;
    n_run := n_run + 1;
  END LOOP;
  RETURN bps.fnd_health_status(p_tenant_id) || jsonb_build_object('checks_run', n_run);
END $$;

-- Every company whose local time is in the midnight hour and that has not run its checks today. For pg_cron (hourly).
CREATE OR REPLACE FUNCTION bps.fnd_health_run_due() RETURNS integer
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE t record; n integer := 0; v_local timestamp;
BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants WHERE is_active LOOP
    v_local := now() AT TIME ZONE bps.fnd_tenant_time_zone(t.tenant_id);
    IF extract(hour FROM v_local) = 0 AND NOT EXISTS (
         SELECT 1 FROM bps.fnd_health_checks h WHERE h.tenant_id = t.tenant_id AND (h.last_run_at AT TIME ZONE bps.fnd_tenant_time_zone(t.tenant_id))::date = v_local::date) THEN
      PERFORM bps.fnd_health_run(t.tenant_id, 'Scheduled');
      n := n + 1;
    END IF;
  END LOOP;
  RETURN n;
END $$;

-- ---------- reading ----------
-- For the heart icon: state is none (no access), never, ok, warning or error. Information does not change it.
CREATE OR REPLACE FUNCTION bps.fnd_health_status(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_last timestamptz; v_i int; v_w int; v_e int;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.health', 'R') THEN RETURN jsonb_build_object('state', 'none', 'infos', 0, 'warnings', 0, 'errors', 0, 'last_run_at', NULL); END IF;
  SELECT max(last_run_at), COALESCE(sum(last_infos), 0), COALESCE(sum(last_warnings), 0), COALESCE(sum(last_errors), 0)
    INTO v_last, v_i, v_w, v_e FROM bps.fnd_health_checks WHERE tenant_id = p_tenant_id AND is_enabled;
  RETURN jsonb_build_object('state', CASE WHEN v_last IS NULL THEN 'never' WHEN v_e > 0 THEN 'error' WHEN v_w > 0 THEN 'warning' ELSE 'ok' END,
    'infos', v_i, 'warnings', v_w, 'errors', v_e, 'last_run_at', v_last);
END $$;

-- The Health Checks page: every check with its settings and last result (a company's missing rows are added first).
CREATE OR REPLACE FUNCTION bps.fnd_health_checks_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.health', 'R') THEN RAISE EXCEPTION 'Not authorised to view health checks'; END IF;
  PERFORM bps.fnd_health_checks_ensure(p_tenant_id);
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('check_code', h.check_code, 'name', h.name, 'category', h.category, 'description', h.description,
      'runs_before_production', h.runs_before_production, 'is_enabled', h.is_enabled, 'last_run_at', h.last_run_at,
      'infos', h.last_infos, 'warnings', h.last_warnings, 'errors', h.last_errors) ORDER BY h.category DESC, h.sort_order)
    FROM bps.fnd_health_checks h WHERE h.tenant_id = p_tenant_id), '[]'::jsonb);
END $$;

-- Open findings (and recently fixed ones when p_include_fixed), errors first.
CREATE OR REPLACE FUNCTION bps.fnd_health_findings_get(p_tenant_id bigint, p_include_fixed boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.health', 'R') THEN RAISE EXCEPTION 'Not authorised to view health checks'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('log_id', l.log_id, 'check_code', l.check_code, 'check_name', h.name, 'category', h.category, 'type', l.type,
      'found_at', l.found_at, 'findings', l.findings, 'remediation', l.remediation, 'record_type', l.record_type, 'record_id', l.record_id,
      'customer_id', l.customer_id, 'link_path', l.link_path, 'fixed_at', l.fixed_at, 'fixed_by_name', u.user_name)
      ORDER BY (l.fixed_at IS NOT NULL), CASE l.type WHEN 'Error' THEN 1 WHEN 'Warning' THEN 2 ELSE 3 END, l.found_at DESC)
    FROM bps.fnd_health_log l
    JOIN bps.fnd_health_checks h ON h.tenant_id = l.tenant_id AND h.check_code = l.check_code
    LEFT JOIN bps.fnd_users u ON u.user_id = l.fixed_by
   WHERE l.tenant_id = p_tenant_id AND (l.fixed_at IS NULL OR (p_include_fixed AND l.fixed_at > now() - interval '30 days'))), '[]'::jsonb);
END $$;

-- Only an administrator (Approve on admin.health) turns a check on or off.
CREATE OR REPLACE FUNCTION bps.fnd_health_check_set_enabled(p_tenant_id bigint, p_check_code text, p_enabled boolean) RETURNS void
LANGUAGE plpgsql SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.health', 'A') THEN RAISE EXCEPTION 'Only an administrator can enable or disable a health check'; END IF;
  UPDATE bps.fnd_health_checks SET is_enabled = COALESCE(p_enabled, true), updated_by = bps.fnd_current_user_id()
   WHERE tenant_id = p_tenant_id AND check_code = p_check_code;
  IF NOT FOUND THEN RAISE EXCEPTION 'Health check not found'; END IF;
END $$;

-- A person marks a finding fixed; if the problem is still there the next run opens it again.
CREATE OR REPLACE FUNCTION bps.fnd_health_finding_fix(p_tenant_id bigint, p_log_id bigint) RETURNS void
LANGUAGE plpgsql SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  UPDATE bps.fnd_health_log SET fixed_at = now(), fixed_by = bps.fnd_current_user_id() WHERE tenant_id = p_tenant_id AND log_id = p_log_id AND fixed_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Finding not found or already fixed'; END IF;
END $$;

REVOKE EXECUTE ON FUNCTION
  bps.fnd_health_catalog(), bps.fnd_health_checks_ensure(bigint),
  bps.fnd_hc_users_without_role(bigint), bps.fnd_hc_accounts_without_pricebook(bigint), bps.fnd_hc_accounts_without_contact(bigint),
  bps.fnd_hc_accounts_without_address(bigint), bps.fnd_hc_compound_without_components(bigint), bps.fnd_hc_compound_inactive_component(bigint),
  bps.fnd_hc_pricebook_unused(bigint), bps.fnd_hc_items_stale(bigint), bps.fnd_hc_orders_without_pricebook(bigint),
  bps.fnd_hc_orders_unpriced_lines(bigint), bps.fnd_hc_payments_over_applied(bigint),
  bps.fnd_health_run(bigint, text, text), bps.fnd_health_run_due(), bps.fnd_health_status(bigint), bps.fnd_health_checks_get(bigint),
  bps.fnd_health_findings_get(bigint, boolean), bps.fnd_health_check_set_enabled(bigint, text, boolean), bps.fnd_health_finding_fix(bigint, bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  bps.fnd_health_catalog(), bps.fnd_health_checks_ensure(bigint),
  bps.fnd_hc_users_without_role(bigint), bps.fnd_hc_accounts_without_pricebook(bigint), bps.fnd_hc_accounts_without_contact(bigint),
  bps.fnd_hc_accounts_without_address(bigint), bps.fnd_hc_compound_without_components(bigint), bps.fnd_hc_compound_inactive_component(bigint),
  bps.fnd_hc_pricebook_unused(bigint), bps.fnd_hc_items_stale(bigint), bps.fnd_hc_orders_without_pricebook(bigint),
  bps.fnd_hc_orders_unpriced_lines(bigint), bps.fnd_hc_payments_over_applied(bigint),
  bps.fnd_health_run(bigint, text, text), bps.fnd_health_status(bigint), bps.fnd_health_checks_get(bigint),
  bps.fnd_health_findings_get(bigint, boolean), bps.fnd_health_check_set_enabled(bigint, text, boolean), bps.fnd_health_finding_fix(bigint, bigint)
  TO authenticated, service_role, bps_dev;
GRANT EXECUTE ON FUNCTION bps.fnd_health_run_due() TO service_role, bps_dev;
