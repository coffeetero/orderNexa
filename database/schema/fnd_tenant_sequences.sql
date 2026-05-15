-- ============================================================
-- FND_TENANT_SEQUENCES
-- Tenant-scoped reusable sequence allocator for order numbers,
-- invoice numbers, customer numbers, and future document numbers.
-- ============================================================

CREATE TABLE IF NOT EXISTS fnd_tenant_sequences (
    tenant_id         BIGINT      NOT NULL REFERENCES fnd_tenants(tenant_id) ON DELETE CASCADE,
    sequence_name     TEXT        NOT NULL,

    start_value       BIGINT      NOT NULL DEFAULT 1000,
    next_value        BIGINT      NOT NULL DEFAULT 1000,
    increment_by      BIGINT      NOT NULL DEFAULT 1,

    mask              TEXT,
    reset_period      TEXT        NOT NULL DEFAULT 'NEVER'
                                  CHECK (reset_period IN ('NEVER', 'DAILY', 'MONTHLY', 'YEARLY')),
    last_reset_key    TEXT,
    requires_gapless  BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active         BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        BIGINT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        BIGINT,

    PRIMARY KEY (tenant_id, sequence_name),
    CHECK (start_value >= 0),
    CHECK (next_value >= 0),
    CHECK (increment_by > 0)
);

-- Ownership: application tables are owned by bps_owner; runtime access is via grants + RLS.
ALTER TABLE fnd_tenant_sequences OWNER TO bps_owner;

COMMENT ON TABLE fnd_tenant_sequences IS
    'Tenant-scoped sequence definitions. Rows are locked individually during allocation.';
COMMENT ON COLUMN fnd_tenant_sequences.mask IS
    'Number mask. # runs are sequence placeholders; [YY], [YYYY], [YYYYMM], [YYYYMMDD], [YYYY-MM], and [YYYY-MM-DD] are date tokens.';
COMMENT ON COLUMN fnd_tenant_sequences.requires_gapless IS
    'When true, generated document numbers must not be physically deleted after assignment.';

CREATE INDEX IF NOT EXISTS idx_fnd_tenant_sequences_active
    ON fnd_tenant_sequences (tenant_id)
    WHERE is_active = TRUE;

CREATE OR REPLACE FUNCTION fnd_tenant_sequence_format(
    p_mask TEXT,
    p_value BIGINT,
    p_context_date DATE DEFAULT CURRENT_DATE
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_result TEXT;
    v_digits TEXT;
    v_hash_count INTEGER;
    v_idx INTEGER;
    v_pos INTEGER;
    v_char TEXT;
    v_output TEXT := '';
BEGIN
    IF p_value IS NULL THEN
        RAISE EXCEPTION 'p_value is required';
    END IF;

    IF p_mask IS NULL OR p_mask = '' THEN
        RETURN p_value::TEXT;
    END IF;

    v_result := p_mask;
    v_result := REPLACE(v_result, '[YYYY-MM-DD]', TO_CHAR(p_context_date, 'YYYY-MM-DD'));
    v_result := REPLACE(v_result, '[YYYYMMDD]', TO_CHAR(p_context_date, 'YYYYMMDD'));
    v_result := REPLACE(v_result, '[YYYY-MM]', TO_CHAR(p_context_date, 'YYYY-MM'));
    v_result := REPLACE(v_result, '[YYYYMM]', TO_CHAR(p_context_date, 'YYYYMM'));
    v_result := REPLACE(v_result, '[YYYY]', TO_CHAR(p_context_date, 'YYYY'));
    v_result := REPLACE(v_result, '[YY]', TO_CHAR(p_context_date, 'YY'));

    v_hash_count := LENGTH(v_result) - LENGTH(REPLACE(v_result, '#', ''));
    IF v_hash_count = 0 THEN
        RETURN v_result;
    END IF;

    v_digits := p_value::TEXT;
    IF LENGTH(v_digits) < v_hash_count THEN
        v_digits := LPAD(v_digits, v_hash_count, '0');
    END IF;

    v_idx := LENGTH(v_digits);
    FOR v_pos IN REVERSE LENGTH(v_result)..1 LOOP
        v_char := SUBSTRING(v_result FROM v_pos FOR 1);

        IF v_char = '#' THEN
            v_output := SUBSTRING(v_digits FROM v_idx FOR 1) || v_output;
            v_idx := v_idx - 1;

            IF v_idx > 0
               AND POSITION('#' IN SUBSTRING(v_result FROM 1 FOR v_pos - 1)) = 0 THEN
                v_output := SUBSTRING(v_digits FROM 1 FOR v_idx) || v_output;
                v_idx := 0;
            END IF;
        ELSE
            v_output := v_char || v_output;
        END IF;
    END LOOP;

    RETURN v_output;
END;
$$;

CREATE OR REPLACE FUNCTION fnd_tenant_sequence_reset_key(
    p_reset_period TEXT,
    p_context_date DATE DEFAULT CURRENT_DATE
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN CASE p_reset_period
        WHEN 'DAILY' THEN TO_CHAR(p_context_date, 'YYYYMMDD')
        WHEN 'MONTHLY' THEN TO_CHAR(p_context_date, 'YYYYMM')
        WHEN 'YEARLY' THEN TO_CHAR(p_context_date, 'YYYY')
        ELSE NULL
    END;
END;
$$;

CREATE OR REPLACE FUNCTION fnd_tenant_sequence_next(
    p_tenant_id BIGINT,
    p_sequence_name TEXT,
    p_context_date DATE DEFAULT CURRENT_DATE
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = bps, public
AS $$
DECLARE
    v_sequence fnd_tenant_sequences%ROWTYPE;
    v_reset_key TEXT;
    v_value BIGINT;
    v_result TEXT;
BEGIN
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
$$;

INSERT INTO fnd_tenant_sequences (
    tenant_id,
    sequence_name,
    start_value,
    next_value,
    increment_by,
    mask,
    reset_period,
    requires_gapless
)
SELECT
    tenant_id,
    'order_number',
    1000,
    1000,
    1,
    'ORD[YYYYMMDD]##.OP202',
    'DAILY',
    FALSE
FROM fnd_tenants
ON CONFLICT (tenant_id, sequence_name) DO NOTHING;

DROP TRIGGER IF EXISTS trg_fnd_tenant_sequences_set_updated ON fnd_tenant_sequences;
CREATE TRIGGER trg_fnd_tenant_sequences_set_updated
    BEFORE UPDATE ON fnd_tenant_sequences
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at_ts_only();

DROP TRIGGER IF EXISTS trg_fnd_tenant_sequences_audit ON fnd_tenant_sequences;
CREATE TRIGGER trg_fnd_tenant_sequences_audit
    AFTER INSERT OR UPDATE OR DELETE ON fnd_tenant_sequences
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log('sequence_name');

-- RLS policies: fnd_tenant_sequences_policies.sql
