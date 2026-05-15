-- ============================================================
-- SEED PRODUCTIONCODE VALUESET
--
-- Upserts the PRODUCTIONCODE valueset and its values.
-- Used by the production code selector throughout the system
-- (Enter Orders, Standing Order Mgmt, Post Standing Orders).
--
-- Value   → Label     (internal code → display name)
-- MORNING → AM
-- LUNCH   → PM
-- DINNER  → PM2
-- SPECIAL1→ Special 1
-- SPECIAL2→ Special 2
--
-- Prerequisites: fnd_valuesets.sql applied
-- ============================================================

DO $$
DECLARE
    v_tenant_id   BIGINT;
    v_valueset_id BIGINT;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants WHERE tenant_name = 'Alpine Bakery' LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    RAISE NOTICE 'Using tenant_id: %', v_tenant_id;

    INSERT INTO fnd_valuesets (
        tenant_id, valueset_code, valueset_name,
        value_type, control_type, source_type,
        refresh_mode, refresh_status, last_refreshed_at, is_active
    ) VALUES (
        v_tenant_id, 'PRODUCTIONCODE', 'Production Code',
        'TEXT', 'select', 'STATIC',
        'MANUAL', 'SUCCESS', now(), TRUE
    )
    ON CONFLICT (tenant_id, valueset_code) DO UPDATE
       SET valueset_name      = EXCLUDED.valueset_name,
           value_type         = EXCLUDED.value_type,
           control_type       = EXCLUDED.control_type,
           source_type        = EXCLUDED.source_type,
           refresh_mode       = EXCLUDED.refresh_mode,
           refresh_status     = EXCLUDED.refresh_status,
           last_refreshed_at  = EXCLUDED.last_refreshed_at,
           last_refresh_error = NULL,
           is_active          = TRUE;

    SELECT valueset_id INTO v_valueset_id
    FROM fnd_valuesets
    WHERE tenant_id = v_tenant_id AND valueset_code = 'PRODUCTIONCODE';

    INSERT INTO fnd_valueset_values (
        tenant_id, valueset_id, value, label, display_order,
        is_default, is_disabled, metadata, refreshed_at
    ) VALUES
        (v_tenant_id, v_valueset_id, 'MORNING',  'AM',        10, FALSE, FALSE, '{}'::JSONB, now()),
        (v_tenant_id, v_valueset_id, 'LUNCH',    'PM',        20, FALSE, FALSE, '{}'::JSONB, now()),
        (v_tenant_id, v_valueset_id, 'DINNER',   'PM2',       30, FALSE, FALSE, '{}'::JSONB, now()),
        (v_tenant_id, v_valueset_id, 'SPECIAL1', 'Special 1', 40, FALSE, FALSE, '{}'::JSONB, now()),
        (v_tenant_id, v_valueset_id, 'SPECIAL2', 'Special 2', 50, FALSE, FALSE, '{}'::JSONB, now())
    ON CONFLICT (tenant_id, valueset_id, value) DO UPDATE
       SET label         = EXCLUDED.label,
           display_order = EXCLUDED.display_order,
           is_default    = EXCLUDED.is_default,
           is_disabled   = EXCLUDED.is_disabled,
           metadata      = EXCLUDED.metadata,
           refreshed_at  = EXCLUDED.refreshed_at;

    RAISE NOTICE 'PRODUCTIONCODE: 5 values upserted.';
END $$;
