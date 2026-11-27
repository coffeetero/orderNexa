-- ============================================================
-- Standing order posting (2026-11-27).
--   om_standing_order_postings  one row per standing-order customer + production date + production code that has been
--                               posted: the order it went to (kept when the clerk renames the department/event, cleared
--                               when the order is deleted), first and last posting time and who posted.
--   om_order_lines.is_sample    the clerk marked the line as a sample (prospects only). Posting never sets it.
-- Then load: database/functions/om_standing_orders_post.sql, om_post_standing_orders_list.sql
-- ============================================================
SET search_path = bps, public;

CREATE TABLE IF NOT EXISTS bps.om_standing_order_postings (
  posting_id       bigint PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id        bigint NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  customer_id      bigint NOT NULL REFERENCES bps.fnd_customers(customer_id) ON DELETE CASCADE,  -- the standing order's customer
  production_date  date   NOT NULL,
  production_code  text   NOT NULL,
  order_id         bigint REFERENCES bps.om_orders(order_id) ON DELETE SET NULL,
  lines_added      integer NOT NULL DEFAULT 0,                                                  -- lines added by the last posting
  post_count       integer NOT NULL DEFAULT 1,
  first_posted_at  timestamptz NOT NULL DEFAULT now(),
  last_posted_at   timestamptz NOT NULL DEFAULT now(),
  posted_by        bigint,
  CONSTRAINT uq_om_standing_order_postings_slot UNIQUE (tenant_id, customer_id, production_date, production_code)
);
ALTER TABLE bps.om_standing_order_postings OWNER TO bps_owner;
CREATE INDEX IF NOT EXISTS idx_om_standing_order_postings_date ON bps.om_standing_order_postings (tenant_id, production_date);
CREATE INDEX IF NOT EXISTS idx_om_standing_order_postings_order ON bps.om_standing_order_postings (order_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE bps.om_standing_order_postings TO authenticated;
GRANT ALL ON TABLE bps.om_standing_order_postings TO bps_dev;
ALTER TABLE bps.om_standing_order_postings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_om_standing_order_postings_read ON bps.om_standing_order_postings;
CREATE POLICY pol_om_standing_order_postings_read ON bps.om_standing_order_postings
  FOR SELECT
  USING (tenant_id::text = ANY (ARRAY(SELECT jsonb_array_elements_text(
           NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> 'allowed_tenant_ids'))));

DROP POLICY IF EXISTS pol_om_standing_order_postings_staff_write ON bps.om_standing_order_postings;
CREATE POLICY pol_om_standing_order_postings_staff_write ON bps.om_standing_order_postings
  FOR ALL
  USING (bps.fnd_is_tenant_staff(tenant_id))
  WITH CHECK (bps.fnd_is_tenant_staff(tenant_id));

ALTER TABLE bps.om_order_lines ADD COLUMN IF NOT EXISTS is_sample boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN bps.om_order_lines.is_sample IS 'Marked as a sample by the clerk (prospective customers or items). Posting standing orders never sets it.';
