SET search_path = bps, public;
-- Pricing book status (Draft / Scheduled / Approved), default dates, approver, and who/when disabled.
-- Status is informational for now: pricing still uses the book's Active flag and the assignment's status and dates.
-- New columns: fnd_pricebooks.last_used_date (refreshed nightly by fnd_pricebooks_last_used_refresh), fnd_pricebooks.status, effective_start_date, effective_end_date, approved_by, approved_at, disabled_at, disabled_by;
--              fnd_tenants.pricebook_unused_years (used later by the health check "book not used").
-- Run after add_pricing_books.sql.

ALTER TABLE bps.fnd_pricebooks
  ADD COLUMN status text NOT NULL DEFAULT 'Draft',
  ADD COLUMN effective_start_date date,
  ADD COLUMN effective_end_date date,
  ADD COLUMN approved_by bigint,
  ADD COLUMN approved_at timestamptz,
  ADD COLUMN disabled_at timestamptz,
  ADD COLUMN disabled_by bigint,
  ADD COLUMN last_used_date date,
  ADD CONSTRAINT chk_fnd_pricebooks_status CHECK (status IN ('Draft', 'Scheduled', 'Approved')),
  ADD CONSTRAINT chk_fnd_pricebooks_dates CHECK (effective_end_date IS NULL OR effective_start_date IS NULL OR effective_end_date >= effective_start_date);

-- Books that exist today are in use: treat them as approved.
UPDATE bps.fnd_pricebooks SET status = 'Approved', approved_at = COALESCE(updated_at, created_at), approved_by = COALESCE(updated_by, created_by);
UPDATE bps.fnd_pricebooks SET disabled_at = COALESCE(updated_at, created_at), disabled_by = updated_by WHERE NOT is_active;

ALTER TABLE bps.fnd_tenants ADD COLUMN pricebook_unused_years integer NOT NULL DEFAULT 2 CHECK (pricebook_unused_years >= 1);

-- Records who approved and who/when disabled; only a pricing approver may set Approved.
CREATE OR REPLACE FUNCTION bps.fnd_pricebooks_track() RETURNS trigger
LANGUAGE plpgsql SET search_path = bps, public AS $$
BEGIN
  IF NEW.status = 'Approved' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'Approved') THEN
    IF NOT bps.fnd_is_trusted() AND NOT bps.fnd_has_access('inventory.pricing', 'A') THEN
      RAISE EXCEPTION 'Only a pricing approver can set a pricing book to Approved';
    END IF;
    NEW.approved_by := bps.fnd_current_user_id();
    NEW.approved_at := now();
  ELSIF NEW.status <> 'Approved' THEN
    NEW.approved_by := NULL;
    NEW.approved_at := NULL;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.is_active AND NOT NEW.is_active THEN
      NEW.disabled_at := now();
      NEW.disabled_by := bps.fnd_current_user_id();
    ELSIF NEW.is_active THEN
      NEW.disabled_at := NULL;
      NEW.disabled_by := NULL;
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION bps.fnd_pricebooks_track() FROM PUBLIC, anon;
CREATE TRIGGER trg_fnd_pricebooks_track BEFORE INSERT OR UPDATE ON bps.fnd_pricebooks
  FOR EACH ROW EXECUTE FUNCTION bps.fnd_pricebooks_track();

-- ---------- Pricing Books screen ----------
CREATE OR REPLACE FUNCTION bps.fnd_pricebooks_list_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
-- last_used_date is stored (see fnd_pricebooks_last_used_refresh); months and is_stale (never used, or last used before the company's "unused years" ago) come from it.
DECLARE v_today date; v_cutoff date;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  v_today := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date;
  SELECT v_today - (t.pricebook_unused_years * 365) INTO v_cutoff FROM bps.fnd_tenants t WHERE t.tenant_id = p_tenant_id;
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('pricebook_id', b.pricebook_id, 'pricebook_name', b.pricebook_name, 'description', b.description,
      'is_active', b.is_active, 'status', b.status, 'effective_start_date', b.effective_start_date, 'effective_end_date', b.effective_end_date,
      'created_by_name', cu.user_name, 'approved_by_name', au.user_name, 'approved_at', b.approved_at,
      'disabled_at', b.disabled_at, 'disabled_by_name', du.user_name,
      'last_used_date', b.last_used_date,
      'last_used_months', CASE WHEN b.last_used_date IS NULL THEN NULL ELSE (extract(year FROM age(v_today, b.last_used_date)) * 12 + extract(month FROM age(v_today, b.last_used_date)))::int END,
      'is_stale', (b.last_used_date IS NULL OR b.last_used_date < v_cutoff),
      'item_count', (SELECT count(*) FROM bps.fnd_pricebook_items i WHERE i.pricebook_id = b.pricebook_id AND i.is_active),
      'assigned_count', (SELECT count(DISTINCT cp.customer_id) FROM bps.fnd_customer_pricebooks cp WHERE cp.pricebook_id = b.pricebook_id))
      ORDER BY b.pricebook_name), '[]'::jsonb)
    FROM bps.fnd_pricebooks b
    LEFT JOIN bps.fnd_users cu ON cu.user_id = b.created_by
    LEFT JOIN bps.fnd_users au ON au.user_id = b.approved_by
    LEFT JOIN bps.fnd_users du ON du.user_id = b.disabled_by
   WHERE b.tenant_id = p_tenant_id);
END $$;

-- payload: {pricebook_id?, pricebook_name, description?, is_active?, status?, effective_start_date?, effective_end_date?}; returns the pricebook_id.
-- Names are unique per company. The "made for customer" column is no longer edited here.
CREATE OR REPLACE FUNCTION bps.fnd_pricebook_save(p_tenant_id bigint, p_payload jsonb) RETURNS bigint
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_id bigint := NULLIF(p_payload ->> 'pricebook_id', '')::bigint; v_name text := btrim(COALESCE(p_payload ->> 'pricebook_name', ''));
        v_status text := COALESCE(NULLIF(p_payload ->> 'status', ''), 'Draft');
        v_from date := NULLIF(p_payload ->> 'effective_start_date', '')::date; v_to date := NULLIF(p_payload ->> 'effective_end_date', '')::date;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF v_name = '' THEN RAISE EXCEPTION 'The pricing book needs a name'; END IF;
  IF v_status NOT IN ('Draft', 'Scheduled', 'Approved') THEN RAISE EXCEPTION 'Invalid status %', v_status; END IF;
  IF v_from IS NOT NULL AND v_to IS NOT NULL AND v_to < v_from THEN RAISE EXCEPTION 'The To date is before the From date'; END IF;
  IF EXISTS (SELECT 1 FROM bps.fnd_pricebooks WHERE tenant_id = p_tenant_id AND lower(pricebook_name) = lower(v_name) AND pricebook_id IS DISTINCT FROM v_id) THEN
    RAISE EXCEPTION 'A pricing book named % already exists', v_name;
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO bps.fnd_pricebooks (tenant_id, pricebook_name, description, is_active, status, effective_start_date, effective_end_date, currency_id)
    VALUES (p_tenant_id, v_name, NULLIF(btrim(p_payload ->> 'description'), ''), COALESCE((p_payload ->> 'is_active')::boolean, true), v_status, v_from, v_to,
            (SELECT currency_id FROM bps.fnd_currencies WHERE iso_code = 'USD'))
    RETURNING pricebook_id INTO v_id;
  ELSE
    UPDATE bps.fnd_pricebooks SET pricebook_name = v_name, description = NULLIF(btrim(p_payload ->> 'description'), ''),
      is_active = COALESCE((p_payload ->> 'is_active')::boolean, is_active), status = v_status, effective_start_date = v_from, effective_end_date = v_to
     WHERE pricebook_id = v_id AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Pricing book not found'; END IF;
  END IF;
  RETURN v_id;
END $$;

-- Items now carry their category so the screen can group them.
CREATE OR REPLACE FUNCTION bps.fnd_pricebook_detail_get(p_tenant_id bigint, p_pricebook_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN jsonb_build_object(
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object('pricebook_item_id', i.pricebook_item_id, 'item_id', i.item_id, 'item_number', it.item_number,
        'item_name', it.item_name, 'category', it.category, 'item_price', i.item_price, 'is_active', i.is_active) ORDER BY it.category NULLS LAST, it.item_number)
        FROM bps.fnd_pricebook_items i JOIN bps.fnd_items it ON it.item_id = i.item_id WHERE i.pricebook_id = p_pricebook_id AND i.tenant_id = p_tenant_id), '[]'::jsonb),
    'assignments', COALESCE((SELECT jsonb_agg(jsonb_build_object('customer_id', cp.customer_id, 'customer_name', c.customer_name, 'assignment_type', cp.assignment_type,
        'status', cp.status, 'is_active', cp.is_active, 'effective_start_date', cp.effective_start_date, 'effective_end_date', cp.effective_end_date,
        'precedence', cp.precedence) ORDER BY c.customer_name, cp.precedence)
        FROM bps.fnd_customer_pricebooks cp JOIN bps.fnd_customers c ON c.customer_id = cp.customer_id
       WHERE cp.pricebook_id = p_pricebook_id AND cp.tenant_id = p_tenant_id), '[]'::jsonb));
END $$;

-- The customer Pricing tab's book list now carries each book's dates so a new assignment can default to them.
CREATE OR REPLACE FUNCTION bps.fnd_customer_pricebooks_get(p_tenant_id bigint, p_customer_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT (
    p_tenant_id::text = ANY (ARRAY(
      SELECT jsonb_array_elements_text(
        (NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb
          -> 'app_metadata' -> 'allowed_tenant_ids'
      )
    ))
  ) THEN
    RAISE EXCEPTION 'Access denied for tenant %', p_tenant_id;
  END IF;

  SELECT jsonb_build_object(
    'assignments', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'customer_pricebook_id', cp.customer_pricebook_id,
          'pricebook_id',          cp.pricebook_id,
          'pricebook_name',        pb.pricebook_name,
          'assignment_type',       cp.assignment_type,
          'status',                cp.status,
          'effective_start_date',  to_char(cp.effective_start_date, 'YYYY-MM-DD'),
          'effective_end_date',    to_char(cp.effective_end_date,   'YYYY-MM-DD'),
          'is_active',             cp.is_active,
          'precedence',            cp.precedence
        )
        ORDER BY cp.precedence, cp.effective_start_date
      )
      FROM fnd_customer_pricebooks cp
      JOIN fnd_pricebooks pb ON pb.pricebook_id = cp.pricebook_id
      WHERE cp.tenant_id   = p_tenant_id
        AND cp.customer_id = p_customer_id
    ), '[]'::jsonb),
    'pricebooks', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'pricebook_id',         pb.pricebook_id,
          'pricebook_name',       pb.pricebook_name,
          'effective_start_date', to_char(pb.effective_start_date, 'YYYY-MM-DD'),
          'effective_end_date',   to_char(pb.effective_end_date,   'YYYY-MM-DD')
        )
        ORDER BY pb.pricebook_name
      )
      FROM fnd_pricebooks pb
      WHERE pb.tenant_id = p_tenant_id
        AND pb.is_active  = TRUE
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;

-- ---------- Company setting: years without orders before a book counts as unused ----------
CREATE OR REPLACE FUNCTION bps.fnd_pricing_settings_get(p_tenant_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  RETURN (SELECT jsonb_build_object('pricebook_unused_years', pricebook_unused_years) FROM bps.fnd_tenants WHERE tenant_id = p_tenant_id);
END $$;

CREATE OR REPLACE FUNCTION bps.fnd_pricing_settings_save(p_tenant_id bigint, p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE v_years integer := NULLIF(p_payload ->> 'pricebook_unused_years', '')::integer;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.production', 'W') THEN RAISE EXCEPTION 'Not authorised to change application settings'; END IF;
  IF v_years IS NULL OR v_years < 1 OR v_years > 50 THEN RAISE EXCEPTION 'Years must be between 1 and 50'; END IF;
  UPDATE bps.fnd_tenants SET pricebook_unused_years = v_years WHERE tenant_id = p_tenant_id;
  RETURN bps.fnd_pricing_settings_get(p_tenant_id);
END $$;

-- Sets each book's last_used_date: the latest production date of an order by a customer the book is assigned to (or that customer's sites
-- and departments). One pass over the orders; meant to run nightly as a health check. Returns how many books changed.
CREATE OR REPLACE FUNCTION bps.fnd_pricebooks_last_used_refresh(p_tenant_id bigint) RETURNS integer
LANGUAGE plpgsql SET search_path = bps, public AS $$
DECLARE n integer;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  WITH used AS (
    SELECT cp.pricebook_id, max(o.production_date) AS d
      FROM bps.om_orders o
      JOIN bps.fnd_customers oc ON oc.customer_id = o.customer_id
      JOIN bps.fnd_customer_pricebooks cp ON cp.customer_id = COALESCE(oc.top_customer_id, oc.customer_id) AND cp.tenant_id = p_tenant_id
     WHERE o.tenant_id = p_tenant_id
     GROUP BY cp.pricebook_id)
  UPDATE bps.fnd_pricebooks b SET last_used_date = u.d
    FROM (SELECT pb.pricebook_id, used.d FROM bps.fnd_pricebooks pb LEFT JOIN used ON used.pricebook_id = pb.pricebook_id WHERE pb.tenant_id = p_tenant_id) u
   WHERE b.pricebook_id = u.pricebook_id AND b.last_used_date IS DISTINCT FROM u.d;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

REVOKE EXECUTE ON FUNCTION bps.fnd_pricebooks_last_used_refresh(bigint), bps.fnd_pricebooks_list_get(bigint), bps.fnd_pricebook_save(bigint, jsonb), bps.fnd_pricebook_detail_get(bigint, bigint),
  bps.fnd_customer_pricebooks_get(bigint, bigint), bps.fnd_pricing_settings_get(bigint), bps.fnd_pricing_settings_save(bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_pricebooks_last_used_refresh(bigint), bps.fnd_pricebooks_list_get(bigint), bps.fnd_pricebook_save(bigint, jsonb), bps.fnd_pricebook_detail_get(bigint, bigint),
  bps.fnd_customer_pricebooks_get(bigint, bigint), bps.fnd_pricing_settings_get(bigint), bps.fnd_pricing_settings_save(bigint, jsonb) TO authenticated, service_role, bps_dev;

-- First fill for every company.
SELECT bps.fnd_pricebooks_last_used_refresh(tenant_id) FROM bps.fnd_tenants;
