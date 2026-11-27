-- ============================================================
-- Call Up List (2026-11-27): which standing order customers the clerks phone each day.
--   om_standing_order_calls  per standing order customer + day of the week + production time: call (yes/no) and the
--                            clerk assigned to make the call (blank = anyone). Set on Manage Standing Orders.
--   om_call_up_called        per customer + date: the clerk ticked Called (one call covers all of that day's times).
-- Then load: functions/om_standing_order_call_get.sql, om_standing_order_call_save.sql, om_call_up_list_get.sql,
--   om_call_up_called_set.sql
-- ============================================================
SET search_path = bps, public;

CREATE TABLE IF NOT EXISTS bps.om_standing_order_calls (
  standing_order_call_id bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id        bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  customer_id      bigint NOT NULL REFERENCES bps.fnd_customers(customer_id) ON DELETE CASCADE,
  production_dow   text   NOT NULL CONSTRAINT chk_om_standing_order_calls_dow CHECK (production_dow IN ('MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN')),
  production_code  text   NOT NULL,
  is_call          boolean NOT NULL DEFAULT false,
  assigned_user_id bigint REFERENCES bps.fnd_users(user_id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       bigint,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       bigint,
  CONSTRAINT uq_om_standing_order_calls_slot UNIQUE (tenant_id, customer_id, production_dow, production_code)
);
ALTER TABLE bps.om_standing_order_calls OWNER TO bps_owner;
CREATE INDEX IF NOT EXISTS idx_om_standing_order_calls_dow ON bps.om_standing_order_calls (tenant_id, production_dow) WHERE is_call;

CREATE TABLE IF NOT EXISTS bps.om_call_up_called (
  call_up_called_id bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id   bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  customer_id bigint NOT NULL REFERENCES bps.fnd_customers(customer_id) ON DELETE CASCADE,
  call_date   date   NOT NULL,
  called_at   timestamptz NOT NULL DEFAULT now(),
  called_by   bigint,
  CONSTRAINT uq_om_call_up_called UNIQUE (tenant_id, customer_id, call_date)
);
ALTER TABLE bps.om_call_up_called OWNER TO bps_owner;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['om_standing_order_calls', 'om_call_up_called'] LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE bps.%I TO authenticated', t);
    EXECUTE format('GRANT ALL ON TABLE bps.%I TO bps_dev', t);
    EXECUTE format('ALTER TABLE bps.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS pol_%1$s_read ON bps.%1$I', t);
    EXECUTE format($p$CREATE POLICY pol_%1$s_read ON bps.%1$I FOR SELECT USING (tenant_id::text = ANY (ARRAY(SELECT jsonb_array_elements_text(
                       NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'))))$p$, t);
    EXECUTE format('DROP POLICY IF EXISTS pol_%1$s_staff_write ON bps.%1$I', t);
    EXECUTE format('CREATE POLICY pol_%1$s_staff_write ON bps.%1$I FOR ALL USING (bps.fnd_is_tenant_staff(tenant_id)) WITH CHECK (bps.fnd_is_tenant_staff(tenant_id))', t);
  END LOOP;
END $$;

DROP TRIGGER IF EXISTS trg_om_standing_order_calls_set_updated ON bps.om_standing_order_calls;
CREATE TRIGGER trg_om_standing_order_calls_set_updated BEFORE UPDATE ON bps.om_standing_order_calls
  FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
