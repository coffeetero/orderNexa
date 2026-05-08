-- ============================================================
-- SEED fnd_tenant_sequences
--
-- Tenant: Alpine Bakery
-- Source: legacy ordr.ordr_no
--
-- Alpine uses grouped numeric order numbers. The configured start_value
-- preserves the legacy maximum; next_value advances one past it so new
-- saved orders do not collide with imported order numbers.
-- ============================================================

DO $$
DECLARE
    v_tenant_id BIGINT;
    v_legacy_ordr_table REGCLASS;
    v_legacy_max_ordr_no BIGINT;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM fnd_tenants
    WHERE tenant_name = 'Alpine Bakery'
    LIMIT 1;

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    v_legacy_ordr_table := COALESCE(
        to_regclass('ordr'),
        to_regclass('bps.ordr'),
        to_regclass('public.ordr')
    );

    IF v_legacy_ordr_table IS NULL THEN
        RAISE EXCEPTION 'legacy ordr table not found';
    END IF;

    EXECUTE format(
        'SELECT MAX(ordr_no::BIGINT) FROM %s WHERE ordr_no IS NOT NULL',
        v_legacy_ordr_table
    )
    INTO v_legacy_max_ordr_no;

    INSERT INTO fnd_tenant_sequences (
        tenant_id,
        sequence_name,
        start_value,
        next_value,
        increment_by,
        mask,
        reset_period,
        requires_gapless,
        is_active
    )
    VALUES (
        v_tenant_id,
        'order_number',
        COALESCE(v_legacy_max_ordr_no, 1000),
        COALESCE(v_legacy_max_ordr_no + 1, 1000),
        1,
        '####-####',
        'NEVER',
        FALSE,
        TRUE
    )
    ON CONFLICT (tenant_id, sequence_name) DO UPDATE
    SET start_value = EXCLUDED.start_value,
        next_value = GREATEST(fnd_tenant_sequences.next_value, EXCLUDED.next_value),
        increment_by = EXCLUDED.increment_by,
        mask = EXCLUDED.mask,
        reset_period = EXCLUDED.reset_period,
        requires_gapless = EXCLUDED.requires_gapless,
        is_active = EXCLUDED.is_active,
        updated_at = now();

    RAISE NOTICE
        'fnd_tenant_sequences: Alpine Bakery order_number start_value=%, next_value=%',
        COALESCE(v_legacy_max_ordr_no, 1000),
        COALESCE(v_legacy_max_ordr_no + 1, 1000);
END $$;

SELECT
    seq.tenant_id,
    seq.sequence_name,
    seq.start_value,
    seq.next_value,
    seq.mask,
    seq.reset_period
FROM fnd_tenant_sequences seq
INNER JOIN fnd_tenants tnt
    ON tnt.tenant_id = seq.tenant_id
WHERE tnt.tenant_name = 'Alpine Bakery'
  AND seq.sequence_name = 'order_number';
