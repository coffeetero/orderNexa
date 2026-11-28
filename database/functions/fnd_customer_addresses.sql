-- ============================================================
-- Customer addresses: Bill to / Ship to roles, Google's suggested corrections, review counts.
-- A customer's addresses are the ADDRESS points of its 'ADDRESSES' contact (card "Billing & Shipping").
-- A customer with no active address of its own uses its nearest parent's (a department delivered to, and billed
-- through, its aggregator account).
--
--   fnd_customer_address_owner(tenant, customer)        → the customer whose addresses apply (itself or an ancestor)
--   fnd_customer_address_pick(tenant, customer, role)    → contact_point_id of the Bill to ('BILL') or Ship to ('SHIP')
--                                                          address. Ship to falls back to Bill to until it is set.
--   fnd_customer_addresses_get(tenant, customer)          → the Contacts tab's Addresses section
--   fnd_customer_address_save(tenant, customer, id, address, instructions, bill, ship, validated)
--                                                         → add (id NULL) or save an address card: its text, its
--                                                           instructions and its Billing / Shipping / Validated boxes
--   fnd_customer_address_action(tenant, customer, id, action)
--       BILL / SHIP  move that role to this address          ACCEPT  take Google's suggestion, mark verified
--       REJECT       keep the typed address, mark verified   VERIFY  staff confirm the address as typed
--       REMOVE       retire the address (not while it is Bill to or Ship to)
--   fnd_address_review_get(tenant)                        → counts and customers for the Dashboard warning
-- Tenant staff only. SECURITY DEFINER because app users have no direct access to the contact tables.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_customer_address_owner(p_tenant_id bigint, p_customer_id bigint)
RETURNS bigint
LANGUAGE sql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
  WITH RECURSIVE chain AS (
    SELECT c.customer_id, c.customer_parent_id, 0 AS depth FROM fnd_customers c
     WHERE c.tenant_id = p_tenant_id AND c.customer_id = p_customer_id
    UNION ALL
    SELECT c.customer_id, c.customer_parent_id, chain.depth + 1 FROM fnd_customers c
      JOIN chain ON c.customer_id = chain.customer_parent_id
     WHERE c.tenant_id = p_tenant_id AND chain.depth < 6)
  SELECT COALESCE((
    SELECT chain.customer_id FROM chain
     WHERE EXISTS (SELECT 1 FROM fnd_contacts k JOIN fnd_contact_points cp ON cp.contact_id = k.contact_id AND cp.tenant_id = k.tenant_id
                    WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.entity_id = chain.customer_id
                      AND k.is_active AND cp.type = 'ADDRESS' AND cp.is_active)
     ORDER BY chain.depth LIMIT 1), p_customer_id);
$function$;

CREATE OR REPLACE FUNCTION bps.fnd_customer_address_pick(p_tenant_id bigint, p_customer_id bigint, p_role text)
RETURNS bigint
LANGUAGE sql
STABLE
SET search_path TO 'bps', 'public'
AS $function$
  SELECT cp.contact_point_id
    FROM fnd_contacts k
    JOIN fnd_contact_points cp ON cp.contact_id = k.contact_id AND cp.tenant_id = k.tenant_id
   WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.is_active
     AND k.entity_id = bps.fnd_customer_address_owner(p_tenant_id, p_customer_id)
     AND cp.type = 'ADDRESS' AND cp.is_active
   ORDER BY CASE WHEN upper(p_role) = 'SHIP' THEN cp.use_as_shipping ELSE cp.use_as_billing END DESC,
            cp.use_as_billing DESC, cp.is_primary DESC, cp.sequence, cp.contact_point_id
   LIMIT 1;
$function$;
-- SECURITY INVOKER: callers read the contact tables with their own rights (or their SECURITY DEFINER function's)
REVOKE EXECUTE ON FUNCTION bps.fnd_customer_address_owner(bigint, bigint), bps.fnd_customer_address_pick(bigint, bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_customer_address_owner(bigint, bigint), bps.fnd_customer_address_pick(bigint, bigint, text) TO authenticated, service_role, bps_dev;

CREATE OR REPLACE FUNCTION bps.fnd_customer_addresses_get(p_tenant_id bigint, p_customer_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_owner bigint; v_cust fnd_customers; v_pickup boolean; v_list jsonb;
BEGIN
  IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN RAISE EXCEPTION 'Only tenant staff can see customer addresses'; END IF;
  SELECT * INTO v_cust FROM fnd_customers WHERE tenant_id = p_tenant_id AND customer_id = p_customer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
  v_owner  := bps.fnd_customer_address_owner(p_tenant_id, p_customer_id);
  v_pickup := COALESCE(v_cust.delivery_method_code, '') = 'PICKUP';
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'contact_point_id', cp.contact_point_id, 'address', cp.value,
           'instructions', cp.instructions, 'bill', cp.use_as_billing, 'ship', cp.use_as_shipping,
           'is_verified', cp.is_verified, 'suggested_address', cp.suggested_address,
           'validation_status', cp.google_geocode_response -> 'validation' ->> 'status',
           'geocode_status', cp.geocode_status, 'latitude', cp.latitude, 'longitude', cp.longitude)
           ORDER BY cp.use_as_billing DESC, cp.use_as_shipping DESC, cp.sequence, cp.contact_point_id), '[]'::jsonb)
    INTO v_list
    FROM fnd_contacts k JOIN fnd_contact_points cp ON cp.contact_id = k.contact_id AND cp.tenant_id = k.tenant_id
   WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.entity_id = v_owner AND k.is_active
     AND cp.type = 'ADDRESS' AND cp.is_active;
  RETURN jsonb_build_object(
    'customer_id', p_customer_id,
    'pickup', v_pickup,
    'inherited_from', CASE WHEN v_owner <> p_customer_id THEN
        (SELECT jsonb_build_object('customer_id', o.customer_id, 'customer_name', o.customer_name) FROM fnd_customers o WHERE o.customer_id = v_owner) END,
    'addresses', v_list,
    -- owner rules 2026-11-28: only accounts need a Billing address; departments need no Shipping address of their own
    'missing_bill', v_cust.customer_type = 'ACCOUNT' AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_list) e WHERE (e ->> 'bill')::boolean),
    'missing_ship', NOT v_pickup AND v_cust.customer_type <> 'DEPARTMENT'
                    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_list) e WHERE (e ->> 'ship')::boolean));
END;
$function$;

DROP FUNCTION IF EXISTS bps.fnd_customer_address_save(bigint, bigint, bigint, text);
CREATE OR REPLACE FUNCTION bps.fnd_customer_address_save(p_tenant_id bigint, p_customer_id bigint, p_contact_point_id bigint, p_address text,
  p_instructions text DEFAULT NULL, p_bill boolean DEFAULT NULL, p_ship boolean DEFAULT NULL, p_validated boolean DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE
  v_user bigint := bps.fnd_current_user_id(); v_text text; v_ins text; v_contact bigint; v_pickup boolean; v_first boolean;
  v_pt fnd_contact_points; v_bill boolean; v_ship boolean;
BEGIN
  IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN RAISE EXCEPTION 'Only tenant staff can change customer addresses'; END IF;
  -- one line per row, no blank lines or stray spaces
  v_text := btrim((SELECT string_agg(btrim(l), E'\n' ORDER BY n) FROM regexp_split_to_table(COALESCE(p_address, ''), '\n') WITH ORDINALITY x(l, n) WHERE btrim(l) <> ''));
  IF v_text IS NULL OR v_text = '' THEN RAISE EXCEPTION 'Enter the address'; END IF;
  v_ins := NULLIF(btrim(COALESCE(p_instructions, '')), '');
  SELECT COALESCE(delivery_method_code, '') = 'PICKUP' INTO v_pickup FROM fnd_customers WHERE tenant_id = p_tenant_id AND customer_id = p_customer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;

  IF p_contact_point_id IS NOT NULL THEN
    SELECT cp.* INTO v_pt FROM fnd_contact_points cp JOIN fnd_contacts k ON k.contact_id = cp.contact_id AND k.tenant_id = cp.tenant_id
     WHERE cp.contact_point_id = p_contact_point_id AND cp.tenant_id = p_tenant_id AND cp.type = 'ADDRESS' AND cp.is_active
       AND k.source_table = 'fnd_customers' AND k.entity_id = p_customer_id AND k.contact_type = 'ADDRESSES'
     FOR UPDATE OF cp;
    IF NOT FOUND THEN RAISE EXCEPTION 'Address not found on this customer'; END IF;
    IF v_pt.use_as_billing AND p_bill IS FALSE THEN
      RAISE EXCEPTION 'A customer needs a Billing address: tick Billing Address on another address instead';
    END IF;
    -- Validated: ticked now by staff → verified; unticked → not; an edited address is checked again unless ticked now
    UPDATE fnd_contact_points
       SET value = v_text, instructions = v_ins,
           is_verified = CASE WHEN p_validated IS TRUE AND NOT is_verified THEN true
                              WHEN p_validated IS FALSE THEN false ELSE is_verified END,
           verified_at = CASE WHEN p_validated IS TRUE AND NOT is_verified THEN now()
                              WHEN p_validated IS FALSE THEN NULL ELSE verified_at END,
           suggested_address = CASE WHEN p_validated IS TRUE AND NOT is_verified THEN NULL ELSE suggested_address END,
           google_geocode_response = CASE WHEN p_validated IS TRUE AND NOT is_verified
             THEN jsonb_set(COALESCE(google_geocode_response, '{}'::jsonb), '{validation}',
                            COALESCE(google_geocode_response -> 'validation', '{}'::jsonb) || '{"status":"STAFF"}', true)
             ELSE google_geocode_response END,
           use_as_shipping = CASE WHEN p_ship IS FALSE THEN false ELSE use_as_shipping END,
           updated_by = v_user
     WHERE contact_point_id = p_contact_point_id;
    v_bill := p_bill IS TRUE AND NOT v_pt.use_as_billing;
    v_ship := p_ship IS TRUE AND NOT v_pt.use_as_shipping;
  ELSE
    SELECT contact_id INTO v_contact FROM fnd_contacts
     WHERE tenant_id = p_tenant_id AND source_table = 'fnd_customers' AND entity_id = p_customer_id AND contact_type = 'ADDRESSES' AND is_active
     ORDER BY contact_id LIMIT 1;
    IF v_contact IS NULL THEN
      INSERT INTO fnd_contacts (tenant_id, entity_id, source_table, card_name, contact_type, is_primary, is_active, created_by, updated_by)
      VALUES (p_tenant_id, p_customer_id, 'fnd_customers', 'Billing & Shipping', 'ADDRESSES', false, true, v_user, v_user)
      RETURNING contact_id INTO v_contact;
    END IF;
    -- the customer's first address of its own takes both roles (it stops using its parent's)
    v_first := NOT EXISTS (SELECT 1 FROM fnd_contacts k JOIN fnd_contact_points cp ON cp.contact_id = k.contact_id
                            WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.entity_id = p_customer_id
                              AND k.is_active AND cp.type = 'ADDRESS' AND cp.is_active);
    INSERT INTO fnd_contact_points (tenant_id, contact_id, type, value, instructions, sequence, is_primary, is_active, is_verified, verified_at, created_by, updated_by)
    VALUES (p_tenant_id, v_contact, 'ADDRESS', v_text, v_ins,
            COALESCE((SELECT max(sequence) + 1 FROM fnd_contact_points WHERE contact_id = v_contact), 1),
            v_first, true, COALESCE(p_validated, false), CASE WHEN p_validated THEN now() END, v_user, v_user)
    RETURNING contact_point_id INTO p_contact_point_id;
    v_bill := v_first OR p_bill IS TRUE;
    v_ship := (v_first AND NOT v_pickup AND p_ship IS NOT FALSE) OR p_ship IS TRUE;
  END IF;

  IF v_bill THEN PERFORM bps.fnd_customer_address_action(p_tenant_id, p_customer_id, p_contact_point_id, 'BILL'); END IF;
  IF v_ship THEN PERFORM bps.fnd_customer_address_action(p_tenant_id, p_customer_id, p_contact_point_id, 'SHIP'); END IF;
  RETURN jsonb_build_object('contact_point_id', p_contact_point_id);
END;
$function$;

CREATE OR REPLACE FUNCTION bps.fnd_customer_address_action(p_tenant_id bigint, p_customer_id bigint, p_contact_point_id bigint, p_action text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
DECLARE v_user bigint := bps.fnd_current_user_id(); v_pt fnd_contact_points; v_action text := upper(btrim(COALESCE(p_action, '')));
BEGIN
  IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN RAISE EXCEPTION 'Only tenant staff can change customer addresses'; END IF;
  SELECT cp.* INTO v_pt
    FROM fnd_contact_points cp JOIN fnd_contacts k ON k.contact_id = cp.contact_id AND k.tenant_id = cp.tenant_id
   WHERE cp.tenant_id = p_tenant_id AND cp.contact_point_id = p_contact_point_id AND cp.type = 'ADDRESS' AND cp.is_active
     AND k.source_table = 'fnd_customers' AND k.entity_id = p_customer_id AND k.contact_type = 'ADDRESSES' AND k.is_active
   FOR UPDATE OF cp;
  IF NOT FOUND THEN RAISE EXCEPTION 'Address not found on this customer'; END IF;

  IF v_action IN ('BILL', 'SHIP') THEN
    -- the role moves: off the customer's other addresses, onto this one
    UPDATE fnd_contact_points cp
       SET use_as_billing  = CASE WHEN v_action = 'BILL' THEN cp.contact_point_id = p_contact_point_id ELSE cp.use_as_billing END,
           use_as_shipping = CASE WHEN v_action = 'SHIP' THEN cp.contact_point_id = p_contact_point_id ELSE cp.use_as_shipping END,
           updated_by = v_user
      FROM fnd_contacts k
     WHERE k.contact_id = cp.contact_id AND k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.entity_id = p_customer_id
       AND cp.type = 'ADDRESS'
       AND (cp.contact_point_id = p_contact_point_id OR (v_action = 'BILL' AND cp.use_as_billing) OR (v_action = 'SHIP' AND cp.use_as_shipping));
  ELSIF v_action = 'ACCEPT' THEN
    IF v_pt.suggested_address IS NULL THEN RAISE EXCEPTION 'Google has no suggestion for this address'; END IF;
    UPDATE fnd_contact_points SET value = suggested_address, suggested_address = NULL, is_verified = true, verified_at = now(),
           google_geocode_response = jsonb_set(COALESCE(google_geocode_response, '{}'::jsonb), '{validation,status}', '"ACCEPTED"', true),
           updated_by = v_user
     WHERE contact_point_id = p_contact_point_id;
  ELSIF v_action IN ('REJECT', 'VERIFY') THEN
    UPDATE fnd_contact_points SET suggested_address = NULL, is_verified = true, verified_at = now(),
           google_geocode_response = jsonb_set(COALESCE(google_geocode_response, '{}'::jsonb), '{validation}',
             COALESCE(google_geocode_response -> 'validation', '{}'::jsonb) || jsonb_build_object('status', CASE WHEN v_action = 'REJECT' THEN 'REJECTED' ELSE 'STAFF' END), true),
           updated_by = v_user
     WHERE contact_point_id = p_contact_point_id;
  ELSIF v_action = 'REMOVE' THEN
    IF v_pt.use_as_billing OR v_pt.use_as_shipping THEN
      RAISE EXCEPTION 'Move Bill to and Ship to to another address before removing this one';
    END IF;
    UPDATE fnd_contact_points SET is_active = false, is_primary = false, updated_by = v_user WHERE contact_point_id = p_contact_point_id;
  ELSE
    RAISE EXCEPTION 'Unknown address action %', p_action;
  END IF;
  RETURN jsonb_build_object('contact_point_id', p_contact_point_id, 'action', v_action);
END;
$function$;

CREATE OR REPLACE FUNCTION bps.fnd_address_review_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
  IF NOT bps.fnd_is_tenant_staff(p_tenant_id) THEN RAISE EXCEPTION 'Only tenant staff can see customer addresses'; END IF;
  RETURN (
    WITH cust AS (
      SELECT c.customer_id, COALESCE(c.delivery_method_code, '') = 'PICKUP' AS pickup,
             bps.fnd_customer_address_owner(p_tenant_id, c.customer_id) AS owner_id
        FROM fnd_customers c WHERE c.tenant_id = p_tenant_id AND c.is_active
    ), pts AS (
      SELECT k.entity_id, cp.use_as_billing, cp.use_as_shipping, cp.suggested_address, cp.is_verified, cp.geocode_status,
             cp.google_geocode_response -> 'validation' ->> 'status' AS vstatus
        FROM fnd_contacts k JOIN fnd_contact_points cp ON cp.contact_id = k.contact_id AND cp.tenant_id = k.tenant_id
       WHERE k.tenant_id = p_tenant_id AND k.source_table = 'fnd_customers' AND k.is_active AND cp.type = 'ADDRESS' AND cp.is_active
    ), per AS (
      SELECT cu.customer_id,
             (SELECT count(*) FROM pts WHERE pts.entity_id = cu.customer_id AND pts.suggested_address IS NOT NULL) AS suggestions,
             (SELECT count(*) FROM pts WHERE pts.entity_id = cu.customer_id AND NOT pts.is_verified AND pts.suggested_address IS NULL
                AND (pts.vstatus IN ('NOT_FOUND', 'UNCONFIRMED') OR (pts.vstatus IS NULL AND pts.geocode_status = 'ZERO_RESULTS'))) AS not_found,
             NOT EXISTS (SELECT 1 FROM pts WHERE pts.entity_id = cu.owner_id AND pts.use_as_billing) AS no_bill,
             NOT cu.pickup AND NOT EXISTS (SELECT 1 FROM pts WHERE pts.entity_id = cu.owner_id AND pts.use_as_shipping) AS no_ship
        FROM cust cu
    )
    SELECT jsonb_build_object(
      'suggestions', COALESCE(sum(suggestions), 0),
      'not_found',   COALESCE(sum(not_found), 0),
      'no_bill',     count(*) FILTER (WHERE no_bill),
      'no_ship',     count(*) FILTER (WHERE no_ship AND NOT no_bill),   -- a customer with no address at all counts once, as no Bill to
      'total',       COALESCE(sum(suggestions + not_found), 0) + count(*) FILTER (WHERE no_bill) + count(*) FILTER (WHERE no_ship AND NOT no_bill),
      'customer_ids', COALESCE(jsonb_agg(customer_id ORDER BY customer_id) FILTER (WHERE suggestions > 0 OR not_found > 0 OR no_bill OR no_ship), '[]'::jsonb))
      FROM per);
END;
$function$;

REVOKE EXECUTE ON FUNCTION bps.fnd_customer_addresses_get(bigint, bigint), bps.fnd_customer_address_save(bigint, bigint, bigint, text, text, boolean, boolean, boolean),
  bps.fnd_customer_address_action(bigint, bigint, bigint, text), bps.fnd_address_review_get(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.fnd_customer_addresses_get(bigint, bigint), bps.fnd_customer_address_save(bigint, bigint, bigint, text, text, boolean, boolean, boolean),
  bps.fnd_customer_address_action(bigint, bigint, bigint, text), bps.fnd_address_review_get(bigint) TO authenticated, service_role, bps_dev;
