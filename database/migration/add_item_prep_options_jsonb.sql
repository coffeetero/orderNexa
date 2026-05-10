-- ============================================================
-- ADD ITEM PREP OPTIONS JSONB + CACHED VALUESET TABLES
--
-- One-time additive apply script for existing databases.
-- Keeps legacy sliced/wrapped/covered boolean columns for compatibility.
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_valuesets (
    tenant_id             BIGINT      NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    valueset_id           BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),

    valueset_code         TEXT        NOT NULL,
    valueset_name         TEXT        NOT NULL,
    value_type            TEXT        NOT NULL DEFAULT 'TEXT',
    control_type          TEXT        NOT NULL DEFAULT 'select',
    source_type           TEXT        NOT NULL DEFAULT 'STATIC'
                                      CHECK (source_type IN ('STATIC', 'SQL')),
    source_sql            TEXT,

    refresh_mode          TEXT        NOT NULL DEFAULT 'MANUAL'
                                      CHECK (refresh_mode IN ('MANUAL', 'SCHEDULED', 'ON_DEMAND')),
    refresh_status        TEXT        NOT NULL DEFAULT 'NEVER'
                                      CHECK (refresh_status IN ('NEVER', 'SUCCESS', 'FAILED')),
    last_refreshed_at     TIMESTAMPTZ,
    last_refresh_error    TEXT,

    is_active             BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by            BIGINT,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by            BIGINT,

    CONSTRAINT uq_fnd_valuesets_tenant_code UNIQUE (tenant_id, valueset_code),
    CONSTRAINT chk_fnd_valuesets_code_not_blank CHECK (NULLIF(TRIM(valueset_code), '') IS NOT NULL),
    CONSTRAINT chk_fnd_valuesets_sql_source CHECK (
        source_type <> 'SQL'
        OR NULLIF(TRIM(COALESCE(source_sql, '')), '') IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS idx_fnd_valuesets_tenant
    ON fnd_valuesets (tenant_id);

CREATE INDEX IF NOT EXISTS idx_fnd_valuesets_tenant_active
    ON fnd_valuesets (tenant_id, valueset_code)
    WHERE is_active = TRUE;

DROP TRIGGER IF EXISTS trg_fnd_valuesets_set_updated ON fnd_valuesets;
CREATE TRIGGER trg_fnd_valuesets_set_updated
    BEFORE UPDATE ON fnd_valuesets
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_valuesets_audit ON fnd_valuesets;
CREATE TRIGGER trg_fnd_valuesets_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_valuesets
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('valueset_id');

CREATE TABLE IF NOT EXISTS fnd_valueset_values (
    tenant_id             BIGINT      NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    valueset_value_id     BIGINT      PRIMARY KEY DEFAULT nextval('fnd_entity_id_seq'::regclass),
    valueset_id           BIGINT      NOT NULL REFERENCES fnd_valuesets(valueset_id) ON DELETE CASCADE,

    value                 TEXT        NOT NULL,
    label                 TEXT        NOT NULL,
    display_order         INT         NOT NULL DEFAULT 0 CHECK (display_order >= 0),
    is_default            BOOLEAN     NOT NULL DEFAULT FALSE,
    is_disabled           BOOLEAN     NOT NULL DEFAULT FALSE,
    metadata              JSONB       NOT NULL DEFAULT '{}'::JSONB,

    source_hash           TEXT,
    refreshed_at          TIMESTAMPTZ,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by            BIGINT,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by            BIGINT,

    CONSTRAINT uq_fnd_valueset_values_tenant_valueset_value UNIQUE (tenant_id, valueset_id, value),
    CONSTRAINT chk_fnd_valueset_values_value_not_blank CHECK (NULLIF(TRIM(value), '') IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_fnd_valueset_values_tenant_valueset
    ON fnd_valueset_values (tenant_id, valueset_id);

CREATE INDEX IF NOT EXISTS idx_fnd_valueset_values_ui
    ON fnd_valueset_values (tenant_id, valueset_id, display_order, label)
    WHERE is_disabled = FALSE;

DROP TRIGGER IF EXISTS trg_fnd_valueset_values_set_updated ON fnd_valueset_values;
CREATE TRIGGER trg_fnd_valueset_values_set_updated
    BEFORE UPDATE ON fnd_valueset_values
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_valueset_values_audit ON fnd_valueset_values;
CREATE TRIGGER trg_fnd_valueset_values_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_valueset_values
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('valueset_value_id');

ALTER TABLE fnd_items
    ADD COLUMN IF NOT EXISTS allowed_prep_options JSONB NOT NULL DEFAULT '[]'::JSONB;

ALTER TABLE fnd_items
    ADD COLUMN IF NOT EXISTS default_prep_options JSONB NOT NULL DEFAULT '[]'::JSONB;

ALTER TABLE om_order_lines
    ADD COLUMN IF NOT EXISTS prep_options JSONB NOT NULL DEFAULT '[]'::JSONB;

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_valueset_id BIGINT;
    v_items_updated INT;
    v_lines_updated INT;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

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

    WITH legacy_prep AS (
        SELECT
            trim(d.ordr_no::BIGINT::TEXT) AS order_number,
            d.item_id::INT AS legacy_item_id,
            bool_or(
                COALESCE(UPPER(TRIM(d.od_item_sliced::TEXT)), '') IN ('Y', 'YES', 'TRUE', '1')
                OR COALESCE(UPPER(TRIM(d.od_item_canopy_sliced::TEXT)), '') IN ('Y', 'YES', 'TRUE', '1')
            ) AS is_sliced,
            bool_or(COALESCE(UPPER(TRIM(d.od_item_wrapped::TEXT)), '') IN ('Y', 'YES', 'TRUE', '1')) AS is_wrapped,
            bool_or(COALESCE(UPPER(TRIM(d.od_item_covered::TEXT)), '') IN ('Y', 'YES', 'TRUE', '1')) AS is_covered
        FROM ordr_detail d
        GROUP BY trim(d.ordr_no::BIGINT::TEXT), d.item_id::INT
    ),
    line_prep AS (
        SELECT
            l.order_line_id,
            COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object('value', v.value, 'label', v.label)
                        ORDER BY v.display_order
                    )
                    FROM (
                        VALUES
                            ('SLICED',  'Sliced',  10, lp.is_sliced),
                            ('WRAPPED', 'Wrapped', 20, lp.is_wrapped),
                            ('COVERED', 'Covered', 30, lp.is_covered)
                    ) AS v(value, label, display_order, selected)
                    WHERE v.selected
                ),
                '[]'::JSONB
            ) AS prep_options
        FROM om_order_lines l
        JOIN om_orders o
          ON o.tenant_id = l.tenant_id
         AND o.order_id = l.order_id
        JOIN fnd_items i
          ON i.tenant_id = l.tenant_id
         AND i.item_id = l.item_id
        JOIN legacy_prep lp
          ON lp.order_number = o.order_number
         AND lp.legacy_item_id = i.legacy_id
        WHERE l.tenant_id = v_tenant_id
    )
    UPDATE om_order_lines l
       SET prep_options = line_prep.prep_options
      FROM line_prep
     WHERE line_prep.order_line_id = l.order_line_id
       AND l.tenant_id = v_tenant_id;

    GET DIAGNOSTICS v_lines_updated = ROW_COUNT;

    RAISE NOTICE 'ITEMPREP valueset_id: %', v_valueset_id;
    RAISE NOTICE 'fnd_items prep options updated: %', v_items_updated;
    RAISE NOTICE 'om_order_lines prep options updated: %', v_lines_updated;
END $$;

DO $$
DECLARE
    v_valuesets INT;
    v_values INT;
    v_items INT;
    v_lines INT;
BEGIN
    SELECT COUNT(*) INTO v_valuesets
    FROM fnd_valuesets
    WHERE valueset_code = 'ITEMPREP';

    SELECT COUNT(*) INTO v_values
    FROM fnd_valuesets vs
    JOIN fnd_valueset_values vv
      ON vv.valueset_id = vs.valueset_id
     AND vv.tenant_id = vs.tenant_id
    WHERE vs.valueset_code = 'ITEMPREP'
      AND vv.value IN ('SLICED', 'WRAPPED', 'COVERED');

    SELECT COUNT(*) INTO v_items
    FROM fnd_items
    WHERE allowed_prep_options <> '[]'::JSONB
       OR default_prep_options <> '[]'::JSONB;

    SELECT COUNT(*) INTO v_lines
    FROM om_order_lines
    WHERE prep_options <> '[]'::JSONB;

    RAISE NOTICE 'QA ITEMPREP valuesets: %', v_valuesets;
    RAISE NOTICE 'QA ITEMPREP values: %', v_values;
    RAISE NOTICE 'QA fnd_items with prep JSONB: %', v_items;
    RAISE NOTICE 'QA om_order_lines with prep JSONB: %', v_lines;
END $$;
