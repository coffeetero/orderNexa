-- ============================================================
-- Seed fnd_contacts + fnd_contact_points from legacy customer table
--
-- Creates:
--   1. BILLING + SHIPPING system contacts for every customer
--   2. Billing address contact_point from legacy b_addr1/2/city/state/zip
--   3. Shipping address contact_point from legacy s_addr1/2/city/state/zip
--
-- Idempotent: deletes all customer contacts for the tenant, then rebuilds.
-- Run AFTER seed_fnd_customers.sql.
--
-- Tenant: "Alpine Bakery" (adjust tenant_name if needed).
-- Link:   fnd_customers.legacy_id = customer.cus_id
-- ============================================================

DO $$
DECLARE
  v_tenant_id  BIGINT;
  v_inserted   INTEGER;
BEGIN

  SELECT tenant_id INTO v_tenant_id
  FROM bps.fnd_tenants
  WHERE tenant_name = 'Alpine Bakery'
  LIMIT 1;

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
  END IF;

  RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

  -- ── Step 1: Clean existing customer contacts for this tenant ──────────────
  DELETE FROM bps.fnd_contacts
  WHERE tenant_id    = v_tenant_id
    AND source_table = 'fnd_customers';

  RAISE NOTICE '>>> Step 1: Existing customer contacts deleted.';

  -- ── Step 2: Create BILLING + SHIPPING system contacts ────────────────────
  INSERT INTO bps.fnd_contacts (tenant_id, entity_id, source_table, contact_name, contact_type, is_primary, is_active)
  SELECT v_tenant_id, fc.customer_id, 'fnd_customers', 'Billing Address', 'BILLING', FALSE, TRUE
  FROM bps.fnd_customers fc
  WHERE fc.tenant_id = v_tenant_id;

  INSERT INTO bps.fnd_contacts (tenant_id, entity_id, source_table, contact_name, contact_type, is_primary, is_active)
  SELECT v_tenant_id, fc.customer_id, 'fnd_customers', 'Shipping Address', 'SHIPPING', FALSE, TRUE
  FROM bps.fnd_customers fc
  WHERE fc.tenant_id = v_tenant_id;

  RAISE NOTICE '>>> Step 2: BILLING + SHIPPING contacts created for all customers.';

  -- ── Step 3: Seed billing addresses ───────────────────────────────────────
  -- Build multiline value: addr1 / addr2 (optional) / City, STATE ZIP
  -- Skip if addr1 is blank/null (nothing useful to store).

  INSERT INTO bps.fnd_contact_points (
    tenant_id, contact_id,
    type, value, label, sequence,
    is_primary, is_active, do_not_contact
  )
  SELECT
    v_tenant_id,
    con.contact_id,
    'ADDRESS',
    TRIM(
      COALESCE(NULLIF(TRIM(leg.b_addr1), ''), '')
      || CASE WHEN NULLIF(TRIM(COALESCE(leg.b_addr2, '')), '') IS NOT NULL
              THEN E'\n' || TRIM(leg.b_addr2) ELSE '' END
      || CASE WHEN NULLIF(TRIM(
                    COALESCE(leg.b_city, '') || ' ' ||
                    COALESCE(leg.b_state, '') || ' ' ||
                    COALESCE(leg.b_zip, '')), '') IS NOT NULL
              THEN E'\n' || TRIM(COALESCE(NULLIF(TRIM(leg.b_city), ''), ''))
                         || CASE WHEN NULLIF(TRIM(COALESCE(leg.b_state, '')), '') IS NOT NULL
                                 THEN ', ' || TRIM(leg.b_state) ELSE '' END
                         || CASE WHEN NULLIF(TRIM(COALESCE(leg.b_zip, '')), '') IS NOT NULL
                                 THEN ' ' || TRIM(leg.b_zip) ELSE '' END
              ELSE '' END
    ),
    'Billing',
    1,
    TRUE,   -- is_primary
    TRUE,   -- is_active
    FALSE   -- do_not_contact
  FROM bps.customer leg
  JOIN bps.fnd_customers fc
    ON fc.legacy_id  = leg.cus_id::BIGINT
   AND fc.tenant_id  = v_tenant_id
  JOIN bps.fnd_contacts con
    ON con.entity_id    = fc.customer_id
   AND con.source_table = 'fnd_customers'
   AND con.contact_type = 'BILLING'
  WHERE NULLIF(TRIM(COALESCE(leg.b_addr1, '')), '') IS NOT NULL;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RAISE NOTICE '>>> Step 3: % billing addresses inserted.', v_inserted;

  -- ── Step 4: Seed shipping addresses ──────────────────────────────────────
  -- Skip if shipping address is identical to billing address (already inserted under SHIPPING)
  -- but still insert it — they live under separate contacts.
  -- Skip if s_addr1 is blank/null.

  INSERT INTO bps.fnd_contact_points (
    tenant_id, contact_id,
    type, value, label, sequence,
    is_primary, is_active, do_not_contact
  )
  SELECT
    v_tenant_id,
    con.contact_id,
    'ADDRESS',
    TRIM(
      COALESCE(NULLIF(TRIM(leg.s_addr1), ''), '')
      || CASE WHEN NULLIF(TRIM(COALESCE(leg.s_addr2, '')), '') IS NOT NULL
              THEN E'\n' || TRIM(leg.s_addr2) ELSE '' END
      || CASE WHEN NULLIF(TRIM(
                    COALESCE(leg.s_city, '') || ' ' ||
                    COALESCE(leg.s_state, '') || ' ' ||
                    COALESCE(leg.s_zip, '')), '') IS NOT NULL
              THEN E'\n' || TRIM(COALESCE(NULLIF(TRIM(leg.s_city), ''), ''))
                         || CASE WHEN NULLIF(TRIM(COALESCE(leg.s_state, '')), '') IS NOT NULL
                                 THEN ', ' || TRIM(leg.s_state) ELSE '' END
                         || CASE WHEN NULLIF(TRIM(COALESCE(leg.s_zip, '')), '') IS NOT NULL
                                 THEN ' ' || TRIM(leg.s_zip) ELSE '' END
              ELSE '' END
    ),
    'Delivery',
    1,
    TRUE,   -- is_primary
    TRUE,   -- is_active
    FALSE   -- do_not_contact
  FROM bps.customer leg
  JOIN bps.fnd_customers fc
    ON fc.legacy_id  = leg.cus_id::BIGINT
   AND fc.tenant_id  = v_tenant_id
  JOIN bps.fnd_contacts con
    ON con.entity_id    = fc.customer_id
   AND con.source_table = 'fnd_customers'
   AND con.contact_type = 'SHIPPING'
  WHERE NULLIF(TRIM(COALESCE(leg.s_addr1, '')), '') IS NOT NULL;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RAISE NOTICE '>>> Step 4: % shipping addresses inserted.', v_inserted;

  RAISE NOTICE 'seed_fnd_contacts.sql complete.';
END $$;
