-- ============================================================
-- Seed fnd_contacts + fnd_contact_points from legacy customer table
--
-- Creates per customer:
--   1. ADDRESSES contact ("Billing & Shipping")
--      - Billing address point:
--          display_name = b_contact
--          value        = addr1 / addr2 / City, STATE ZIP
--          use_as_shipping = TRUE when billing = shipping (addr + contact)
--      - Shipping address point (only when use_as_shipping = FALSE):
--          display_name = s_contact (if different from b_contact, else same)
--          value        = s_addr lines
--   2. OTHER_CONTACTS contact ("Other Contacts")
--      - One NOTE point aggregating cus_phone1/2, cus_fax, cus_beeper,
--        cus_ar_contact for tenant cleanup (only when any field non-blank)
--
-- Idempotent: deletes all customer contacts for the tenant, then rebuilds.
-- Run AFTER seed_fnd_customers.sql.
-- ============================================================

DO $$
DECLARE
  v_tenant_id BIGINT;
  v_inserted  INTEGER;
BEGIN

  SELECT tenant_id INTO v_tenant_id
  FROM bps.fnd_tenants
  WHERE tenant_name = 'Alpine Bakery'
  LIMIT 1;

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
  END IF;

  RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

  -- ── Step 1: Clean existing customer contacts ──────────────────────────────
  DELETE FROM bps.fnd_contacts
  WHERE tenant_id    = v_tenant_id
    AND source_table = 'fnd_customers';

  RAISE NOTICE '>>> Step 1: Existing customer contacts deleted.';

  -- ── Step 2: Create ADDRESSES contact for every customer ───────────────────
  INSERT INTO bps.fnd_contacts (tenant_id, entity_id, source_table, card_name, contact_type, is_primary, is_active)
  SELECT v_tenant_id, fc.customer_id, 'fnd_customers', 'Billing & Shipping', 'ADDRESSES', FALSE, TRUE
  FROM bps.fnd_customers fc
  WHERE fc.tenant_id = v_tenant_id;

  RAISE NOTICE '>>> Step 2: ADDRESSES contacts created.';

  -- ── Step 3: Seed billing address points ───────────────────────────────────
  INSERT INTO bps.fnd_contact_points (
    tenant_id, contact_id, type, value, label, sequence,
    is_primary, is_active, do_not_contact, use_as_shipping
  )
  SELECT
    v_tenant_id,
    con.contact_id,
    'ADDRESS',
    -- value: address lines only
    TRIM(
      COALESCE(NULLIF(TRIM(leg.b_addr1), ''), '')
      || CASE WHEN NULLIF(TRIM(COALESCE(leg.b_addr2, '')), '') IS NOT NULL
              THEN E'\n' || TRIM(leg.b_addr2) ELSE '' END
      || CASE WHEN NULLIF(TRIM(COALESCE(leg.b_city,'') || COALESCE(leg.b_state,'') || COALESCE(leg.b_zip,'')), '') IS NOT NULL
              THEN E'\n'
                || COALESCE(NULLIF(TRIM(leg.b_city), ''), '')
                || CASE WHEN NULLIF(TRIM(COALESCE(leg.b_state,'')), '') IS NOT NULL THEN ', ' || TRIM(leg.b_state) ELSE '' END
                || CASE WHEN NULLIF(TRIM(COALESCE(leg.b_zip,'')),   '') IS NOT NULL THEN ' '  || TRIM(leg.b_zip)   ELSE '' END
              ELSE '' END
    ),
    'Billing', 1, TRUE, TRUE, FALSE,
    -- use_as_shipping: TRUE when addr lines AND contact match
    (
      COALESCE(NULLIF(TRIM(leg.b_addr1),  ''), '') = COALESCE(NULLIF(TRIM(leg.s_addr1),  ''), '')
      AND COALESCE(NULLIF(TRIM(COALESCE(leg.b_addr2,  '')), ''), '') = COALESCE(NULLIF(TRIM(COALESCE(leg.s_addr2,  '')), ''), '')
      AND COALESCE(NULLIF(TRIM(COALESCE(leg.b_city,   '')), ''), '') = COALESCE(NULLIF(TRIM(COALESCE(leg.s_city,   '')), ''), '')
      AND COALESCE(NULLIF(TRIM(COALESCE(leg.b_state,  '')), ''), '') = COALESCE(NULLIF(TRIM(COALESCE(leg.s_state,  '')), ''), '')
      AND COALESCE(NULLIF(TRIM(COALESCE(leg.b_zip,    '')), ''), '') = COALESCE(NULLIF(TRIM(COALESCE(leg.s_zip,    '')), ''), '')
      AND COALESCE(NULLIF(TRIM(COALESCE(leg.b_contact,'')), ''), '') = COALESCE(NULLIF(TRIM(COALESCE(leg.s_contact,'')), ''), '')
    )
  FROM bps.customer leg
  JOIN bps.fnd_customers fc  ON fc.legacy_id = leg.cus_id::BIGINT AND fc.tenant_id = v_tenant_id
  JOIN bps.fnd_contacts  con ON con.entity_id = fc.customer_id AND con.source_table = 'fnd_customers' AND con.contact_type = 'ADDRESSES'
  WHERE NULLIF(TRIM(COALESCE(leg.b_addr1, '')), '') IS NOT NULL;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RAISE NOTICE '>>> Step 3: % billing address points inserted.', v_inserted;

  -- ── Step 4: Seed shipping address points ──────────────────────────────────
  INSERT INTO bps.fnd_contact_points (
    tenant_id, contact_id, type, value, label, sequence,
    is_primary, is_active, do_not_contact, use_as_shipping
  )
  SELECT
    v_tenant_id,
    con.contact_id,
    'ADDRESS',
    -- value: shipping address lines
    TRIM(
      COALESCE(NULLIF(TRIM(leg.s_addr1), ''), '')
      || CASE WHEN NULLIF(TRIM(COALESCE(leg.s_addr2, '')), '') IS NOT NULL
              THEN E'\n' || TRIM(leg.s_addr2) ELSE '' END
      || CASE WHEN NULLIF(TRIM(COALESCE(leg.s_city,'') || COALESCE(leg.s_state,'') || COALESCE(leg.s_zip,'')), '') IS NOT NULL
              THEN E'\n'
                || COALESCE(NULLIF(TRIM(leg.s_city), ''), '')
                || CASE WHEN NULLIF(TRIM(COALESCE(leg.s_state,'')), '') IS NOT NULL THEN ', ' || TRIM(leg.s_state) ELSE '' END
                || CASE WHEN NULLIF(TRIM(COALESCE(leg.s_zip,'')),   '') IS NOT NULL THEN ' '  || TRIM(leg.s_zip)   ELSE '' END
              ELSE '' END
    ),
    'Shipping', 2, FALSE, TRUE, FALSE, FALSE
  FROM bps.customer leg
  JOIN bps.fnd_customers fc  ON fc.legacy_id = leg.cus_id::BIGINT AND fc.tenant_id = v_tenant_id
  JOIN bps.fnd_contacts  con ON con.entity_id = fc.customer_id AND con.source_table = 'fnd_customers' AND con.contact_type = 'ADDRESSES'
  WHERE NULLIF(TRIM(COALESCE(leg.s_addr1, '')), '') IS NOT NULL
    AND NOT (
      COALESCE(NULLIF(TRIM(leg.b_addr1),  ''), '') = COALESCE(NULLIF(TRIM(leg.s_addr1),  ''), '')
      AND COALESCE(NULLIF(TRIM(COALESCE(leg.b_addr2,  '')), ''), '') = COALESCE(NULLIF(TRIM(COALESCE(leg.s_addr2,  '')), ''), '')
      AND COALESCE(NULLIF(TRIM(COALESCE(leg.b_city,   '')), ''), '') = COALESCE(NULLIF(TRIM(COALESCE(leg.s_city,   '')), ''), '')
      AND COALESCE(NULLIF(TRIM(COALESCE(leg.b_state,  '')), ''), '') = COALESCE(NULLIF(TRIM(COALESCE(leg.s_state,  '')), ''), '')
      AND COALESCE(NULLIF(TRIM(COALESCE(leg.b_zip,    '')), ''), '') = COALESCE(NULLIF(TRIM(COALESCE(leg.s_zip,    '')), ''), '')
      AND COALESCE(NULLIF(TRIM(COALESCE(leg.b_contact,'')), ''), '') = COALESCE(NULLIF(TRIM(COALESCE(leg.s_contact,'')), ''), '')
    );

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RAISE NOTICE '>>> Step 4: % shipping address points inserted.', v_inserted;

  -- ── Step 5: Create OTHER_CONTACTS + NOTE for legacy phone/contact data ────
  INSERT INTO bps.fnd_contacts (tenant_id, entity_id, source_table, card_name, contact_type, is_primary, is_active)
  SELECT v_tenant_id, fc.customer_id, 'fnd_customers', 'Other Contacts', 'OTHER_CONTACTS', FALSE, TRUE
  FROM bps.customer leg
  JOIN bps.fnd_customers fc ON fc.legacy_id = leg.cus_id::BIGINT AND fc.tenant_id = v_tenant_id
  WHERE NULLIF(TRIM(COALESCE(leg.cus_phone1,    '')), '') IS NOT NULL
     OR NULLIF(TRIM(COALESCE(leg.cus_phone2,    '')), '') IS NOT NULL
     OR NULLIF(TRIM(COALESCE(leg.cus_fax,       '')), '') IS NOT NULL
     OR NULLIF(TRIM(COALESCE(leg.cus_beeper,    '')), '') IS NOT NULL
     OR NULLIF(TRIM(COALESCE(leg.cus_ar_contact,'')), '') IS NOT NULL;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RAISE NOTICE '>>> Step 5: % OTHER_CONTACTS contacts created.', v_inserted;

  -- ── Step 6: Seed NOTE point with aggregated legacy data ───────────────────
  INSERT INTO bps.fnd_contact_points (
    tenant_id, contact_id, type, value, label, sequence,
    is_primary, is_active, do_not_contact, use_as_shipping
  )
  SELECT
    v_tenant_id, con.contact_id, 'NOTE',
    TRIM(
      CASE WHEN NULLIF(TRIM(COALESCE(leg.cus_phone1,    '')), '') IS NOT NULL THEN 'Phone1: '     || TRIM(leg.cus_phone1)    || E'\n' ELSE '' END
      || CASE WHEN NULLIF(TRIM(COALESCE(leg.cus_phone2,    '')), '') IS NOT NULL THEN 'Phone2: '   || TRIM(leg.cus_phone2)    || E'\n' ELSE '' END
      || CASE WHEN NULLIF(TRIM(COALESCE(leg.cus_fax,       '')), '') IS NOT NULL THEN 'Fax: '      || TRIM(leg.cus_fax)       || E'\n' ELSE '' END
      || CASE WHEN NULLIF(TRIM(COALESCE(leg.cus_beeper,    '')), '') IS NOT NULL THEN 'Beeper: '   || TRIM(leg.cus_beeper)    || E'\n' ELSE '' END
      || CASE WHEN NULLIF(TRIM(COALESCE(leg.cus_ar_contact,'')), '') IS NOT NULL THEN 'AR Contact: '|| TRIM(leg.cus_ar_contact)|| E'\n' ELSE '' END
    ),
    'Legacy Data', 1, FALSE, TRUE, FALSE, FALSE
  FROM bps.customer leg
  JOIN bps.fnd_customers fc  ON fc.legacy_id = leg.cus_id::BIGINT AND fc.tenant_id = v_tenant_id
  JOIN bps.fnd_contacts  con ON con.entity_id = fc.customer_id AND con.source_table = 'fnd_customers' AND con.contact_type = 'OTHER_CONTACTS';

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RAISE NOTICE '>>> Step 6: % legacy NOTE points inserted.', v_inserted;

  RAISE NOTICE 'seed_fnd_contacts.sql complete.';
END $$;
