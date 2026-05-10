-- ============================================================
-- SEED ITEM PREP OPTION VALUESET + FND_ITEMS JSONB DEFAULTS
--
-- Immediate static item-prep values for Alpine Bakery:
--   SLICED, WRAPPED, COVERED
--
-- This script creates the cached valueset values and backfills item-level
-- allowed/default prep options from bps_items capabilities/defaults.
--
-- Prerequisites:
--   • fnd_valuesets.sql applied
--   • seed_fnd_items.sql and seed_bps_items.sql have run
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_valueset_id BIGINT;
    v_values_inserted INT;
    v_items_updated INT;
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

    WITH prep AS (
        SELECT
            i.item_id,
            COALESCE(
                (
                    SELECT jsonb_agg(v.code ORDER BY v.sort_order)
                    FROM (
                        VALUES
                            ('SLICED',  10, COALESCE(b.is_sliceable, FALSE)),
                            ('WRAPPED', 20, COALESCE(b.is_wrappable, FALSE)),
                            ('COVERED', 30, COALESCE(b.is_coverable, FALSE))
                    ) AS v(code, sort_order, enabled)
                    WHERE v.enabled
                ),
                '[]'::JSONB
            ) AS allowed_prep_options,
            COALESCE(
                (
                    SELECT jsonb_agg(v.code ORDER BY v.sort_order)
                    FROM (
                        VALUES
                            ('SLICED',  10, COALESCE(b.default_sliced, FALSE)),
                            ('WRAPPED', 20, COALESCE(b.default_wrapped, FALSE)),
                            ('COVERED', 30, COALESCE(b.default_covered, FALSE))
                    ) AS v(code, sort_order, enabled)
                    WHERE v.enabled
                ),
                '[]'::JSONB
            ) AS default_prep_options
        FROM fnd_items i
        LEFT JOIN bps_items b
               ON b.tenant_id = i.tenant_id
              AND b.item_id = i.item_id
        WHERE i.tenant_id = v_tenant_id
    )
    UPDATE fnd_items i
       SET allowed_prep_options = prep.allowed_prep_options,
           default_prep_options = prep.default_prep_options
      FROM prep
     WHERE prep.item_id = i.item_id
       AND i.tenant_id = v_tenant_id;

    GET DIAGNOSTICS v_items_updated = ROW_COUNT;

    RAISE NOTICE 'ITEMPREP valueset_id: %', v_valueset_id;
    RAISE NOTICE 'ITEMPREP values upserted: %', v_values_inserted;
    RAISE NOTICE 'fnd_items prep options updated: %', v_items_updated;
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
