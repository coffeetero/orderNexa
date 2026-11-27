-- ============================================================
-- add_customer_segments
-- Segment of an account: the kind of business it is (Hotels, Restaurants, Corporations, Aggregators, …), for sales by
-- segment on the Dashboard. Set on the ACCOUNT; its sites and departments count under it.
--   fnd_customers.segment_code   a value of the company's CUSTOMERSEGMENT list (NULL = Unassigned)
--   value set CUSTOMERSEGMENT     one list per company, seeded with the values below (kept like item categories)
-- ============================================================
SET search_path = bps, public;   -- the value set triggers use unqualified names

ALTER TABLE bps.fnd_customers ADD COLUMN IF NOT EXISTS segment_code text;
COMMENT ON COLUMN bps.fnd_customers.segment_code IS 'Account segment (CUSTOMERSEGMENT value set); NULL = Unassigned. Set on accounts; sites and departments count under their account.';

DO $$
DECLARE t record; v_set bigint;
BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP
    SELECT valueset_id INTO v_set FROM bps.fnd_valuesets WHERE tenant_id = t.tenant_id AND valueset_code = 'CUSTOMERSEGMENT';
    IF v_set IS NULL THEN
      INSERT INTO bps.fnd_valuesets (tenant_id, valueset_code, valueset_name, value_type, control_type, source_type, refresh_mode, refresh_status, is_active)
      VALUES (t.tenant_id, 'CUSTOMERSEGMENT', 'Customer Segment', 'TEXT', 'select', 'STATIC', 'MANUAL', 'NEVER', TRUE)
      RETURNING valueset_id INTO v_set;
      INSERT INTO bps.fnd_valueset_values (tenant_id, valueset_id, value, label, display_order)
      VALUES (t.tenant_id, v_set, 'AGGREGATORS', 'Aggregators', 1),
             (t.tenant_id, v_set, 'CATERERS', 'Caterers', 2),
             (t.tenant_id, v_set, 'CORPORATIONS', 'Corporations', 3),
             (t.tenant_id, v_set, 'HOTELS', 'Hotels', 4),
             (t.tenant_id, v_set, 'RESTAURANTS', 'Restaurants', 5),
             (t.tenant_id, v_set, 'RETAIL', 'Retail', 6),
             (t.tenant_id, v_set, 'OTHER', 'Other', 7);
    END IF;
  END LOOP;
END $$;
