-- ============================================================
-- Seed production-code cutoffs, delivery methods and invoice/shipment/credit-memo numbering for tenant "Alpine Bakery" (local data).
-- Cutoffs are defaults only (4:00 PM the day before, delivery the day after): adjust in Admin > Production Codes.
-- Idempotent. Prerequisites: om_production_codes.sql, om_delivery_methods.sql, PRODUCTIONCODE valueset seeded.
-- ============================================================
DO $$
DECLARE v_tenant_id BIGINT;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM bps.fnd_tenants WHERE tenant_name = 'Alpine Bakery' LIMIT 1;
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Tenant "Alpine Bakery" not found in fnd_tenants';
    END IF;

    INSERT INTO bps.om_production_codes (tenant_id, production_code, cutoff_time, cutoff_days_before, delivery_days_after)
    SELECT v_tenant_id, UPPER(v.value), TIME '16:00', 1, 1
      FROM bps.fnd_valuesets s JOIN bps.fnd_valueset_values v ON v.valueset_id = s.valueset_id
     WHERE s.tenant_id = v_tenant_id AND s.valueset_code = 'PRODUCTIONCODE'
    ON CONFLICT (tenant_id, production_code) DO NOTHING;

    INSERT INTO bps.om_delivery_methods (tenant_id, delivery_method_code, delivery_method_name, is_own_fleet, requires_tracking)
    VALUES
        (v_tenant_id, 'OWN_TRUCK', 'Own truck',  TRUE,  FALSE),
        (v_tenant_id, 'CARRIER',   'Carrier (UPS, FedEx)', FALSE, TRUE),
        (v_tenant_id, 'COURIER',   'Courier (Uber)',       FALSE, FALSE),
        (v_tenant_id, 'PICKUP',    'Customer pickup',      FALSE, FALSE)
    ON CONFLICT (tenant_id, delivery_method_code) DO NOTHING;

    -- Numbering (settings are editable in Admin > Production Settings)
    INSERT INTO bps.fnd_tenant_sequences (tenant_id, sequence_name, start_value, next_value, increment_by, mask, reset_period, requires_gapless)
    VALUES
        (v_tenant_id, 'invoice_number',     1000, 1000, 1, 'INV-######', 'NEVER', FALSE),
        (v_tenant_id, 'shipment_number',    1000, 1000, 1, 'SHP-######', 'NEVER', FALSE),
        (v_tenant_id, 'credit_memo_number', 1000, 1000, 1, 'CM-######',  'NEVER', FALSE),
        (v_tenant_id, 'debit_memo_number',  1000, 1000, 1, 'DM-######',  'NEVER', FALSE)
    ON CONFLICT (tenant_id, sequence_name) DO NOTHING;
END $$;
