-- ============================================================
-- SEED ITEM PREP OPTION VALUESET
--
-- Upserts the ITEMPREP valueset and its three values (SLICED, WRAPPED, COVERED).
-- allowed_prep_options / default_prep_options on fnd_items are now seeded
-- directly in seed_fnd_items.sql from the legacy item table.
--
-- Prerequisites:
--   • fnd_valuesets.sql applied
--   • seed_fnd_items.sql has run
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_valueset_id BIGINT;
    v_values_inserted INT;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    INSERT INTO fnd_valuesets (
        tenant_id,
        valueset_code,
        valueset_name,
        value_type,
        control_type,
        source_type,
        refresh_mode,
        refresh_status,
        last_refreshed_at,
        is_active
    )
    VALUES (
        v_tenant_id,
        'ITEMPREP',
        'Item Preparation',
        'TEXT',
        'multiselect',
        'STATIC',
        'MANUAL',
        'SUCCESS',
        now(),
        TRUE
    )
    ON CONFLICT (tenant_id, valueset_code) DO UPDATE
       SET valueset_name = EXCLUDED.valueset_name,
           value_type = EXCLUDED.value_type,
           control_type = EXCLUDED.control_type,
           source_type = EXCLUDED.source_type,
           refresh_mode = EXCLUDED.refresh_mode,
           refresh_status = EXCLUDED.refresh_status,
           last_refreshed_at = EXCLUDED.last_refreshed_at,
           last_refresh_error = NULL,
           is_active = TRUE;

    SELECT valueset_id INTO v_valueset_id
    FROM fnd_valuesets
    WHERE tenant_id = v_tenant_id
      AND valueset_code = 'ITEMPREP';

    INSERT INTO fnd_valueset_values (
        tenant_id,
        valueset_id,
        value,
        label,
        display_order,
        is_default,
        is_disabled,
        metadata,
        refreshed_at
    )
    VALUES
        (v_tenant_id, v_valueset_id, 'SLICED',  'Sliced',  10, FALSE, FALSE, '{}'::JSONB, now()),
        (v_tenant_id, v_valueset_id, 'WRAPPED', 'Wrapped', 20, FALSE, FALSE, '{}'::JSONB, now()),
        (v_tenant_id, v_valueset_id, 'COVERED', 'Covered', 30, FALSE, FALSE, '{}'::JSONB, now())
    ON CONFLICT (tenant_id, valueset_id, value) DO UPDATE
       SET label = EXCLUDED.label,
           display_order = EXCLUDED.display_order,
           is_default = EXCLUDED.is_default,
           is_disabled = EXCLUDED.is_disabled,
           metadata = EXCLUDED.metadata,
           refreshed_at = EXCLUDED.refreshed_at;

    GET DIAGNOSTICS v_values_inserted = ROW_COUNT;

    RAISE NOTICE 'ITEMPREP valueset_id: %', v_valueset_id;
    RAISE NOTICE 'ITEMPREP values upserted: %', v_values_inserted;
END $$;

SELECT
    vs.valueset_code,
    vv.value,
    vv.label,
    vv.display_order
FROM fnd_valuesets vs
JOIN fnd_valueset_values vv
  ON vv.valueset_id = vs.valueset_id
 AND vv.tenant_id = vs.tenant_id
WHERE vs.valueset_code = 'ITEMPREP'
ORDER BY vv.display_order;
