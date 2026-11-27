-- ============================================================
-- Operations › Delivery › Routes Maintenance: delivery routes and their stops per day of week and production code.
--
--   om_routes                : the tenant's routes (code, name, sort order, default driver, start time, notes, active).
--   om_route_stops           : ship-to locations on a route for one delivery day of week + production code, in stop order.
--                              A ship-to is on at most one route per day + code. Window from/to and driver notes per stop.
--   om_route_stop_exceptions : one-off changes for a single delivery date + code: skip a ship-to (route_id NULL) or put it on
--                              a route at a stop number (add or move) for that date only.
--   om_shipments.route_id / route_stop_no : stamped by om_production_run_process (om_shipments_route_stamp) for own-fleet
--                              shipments; om_shipments.route (text) keeps the route name for display and back-compat.
--
-- Ship-to locations are the customers shipments are made to (om_shipments.ship_to_customer_id): accounts and
-- departments. A department with no stop of its own follows its nearest ancestor's stop. Sites are delivered with their
-- parent (their orders are stored under it), so they cannot be stops.
--
-- New access area delivery.routes (granted to the system Company Administrator role through fnd_tenant_access_seed).
-- Then load (database/functions/): om_route_dow.sql, om_route_check.sql, om_route_stops_renumber.sql, om_route_plan.sql,
--   om_routes_get.sql, om_route_save.sql, om_route_delete.sql, om_route_stops_get.sql, om_route_stop_add.sql,
--   om_route_stop_save.sql, om_route_stop_move.sql, om_route_stop_delete.sql, om_route_stops_copy.sql,
--   om_route_unassigned_get.sql, om_route_exceptions_get.sql, om_route_exception_save.sql, om_route_exception_delete.sql,
--   om_route_sheet_get.sql, om_customer_routes_get.sql, om_shipments_route_stamp.sql,
--   om_production_run_process.sql (stamps routes), om_report_delivery_get.sql (route order, stop number)
-- Then (Alpine only) database/migration/seed_om_routes.sql.
-- ============================================================

INSERT INTO bps.fnd_areas (area_key, module, area_name, audience, display_order)
VALUES ('delivery.routes', 'Delivery', 'Routes Maintenance', 'TENANT', 250)
ON CONFLICT (area_key) DO NOTHING;

DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tenant_id FROM bps.fnd_tenants LOOP PERFORM bps.fnd_tenant_access_seed(t.tenant_id); END LOOP;
END $$;

-- ── om_routes ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bps.om_routes (
  route_id               bigint  PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id              bigint  NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  route_code             text    NOT NULL CONSTRAINT chk_om_routes_code CHECK (btrim(route_code) <> '' AND length(route_code) <= 20),
  route_name             text    NOT NULL CONSTRAINT chk_om_routes_name CHECK (btrim(route_name) <> '' AND length(route_name) <= 80),
  sort_order             integer NOT NULL DEFAULT 0,
  is_active              boolean NOT NULL DEFAULT true,
  default_driver_user_id bigint  REFERENCES bps.fnd_users(user_id) ON DELETE SET NULL,
  start_time             time,
  notes                  text    CONSTRAINT chk_om_routes_notes CHECK (notes IS NULL OR length(notes) <= 2000),
  legacy_id              integer,
  created_at             timestamptz NOT NULL DEFAULT now(),
  created_by             bigint,
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             bigint
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_om_routes_code   ON bps.om_routes (tenant_id, upper(route_code));
CREATE UNIQUE INDEX IF NOT EXISTS uq_om_routes_legacy ON bps.om_routes (tenant_id, legacy_id) WHERE legacy_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_om_routes_driver ON bps.om_routes (default_driver_user_id) WHERE default_driver_user_id IS NOT NULL;
COMMENT ON TABLE  bps.om_routes IS 'Delivery routes of a tenant (Operations › Delivery › Routes Maintenance).';
COMMENT ON COLUMN bps.om_routes.sort_order IS 'Order of routes on screens and the Route Delivery Report.';
COMMENT ON COLUMN bps.om_routes.default_driver_user_id IS 'Usual driver (a staff user); optional.';
COMMENT ON COLUMN bps.om_routes.legacy_id IS 'Old BPS route.route_id (migration only).';

-- ── om_route_stops ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bps.om_route_stops (
  route_stop_id       bigint  PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id           bigint  NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  route_id            bigint  NOT NULL REFERENCES bps.om_routes(route_id) ON DELETE CASCADE,
  day_of_week         text    NOT NULL CONSTRAINT chk_om_route_stops_dow CHECK (day_of_week IN ('MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN')),
  production_code     text    NOT NULL,
  ship_to_customer_id bigint  NOT NULL REFERENCES bps.fnd_customers(customer_id) ON DELETE CASCADE,
  stop_no             integer NOT NULL CONSTRAINT chk_om_route_stops_stop_no CHECK (stop_no > 0),
  window_from         time,
  window_to           time,
  driver_notes        text    CONSTRAINT chk_om_route_stops_notes CHECK (driver_notes IS NULL OR length(driver_notes) <= 500),
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          bigint,
  updated_at          timestamptz NOT NULL DEFAULT now(),
  updated_by          bigint,
  CONSTRAINT fk_om_route_stops_code FOREIGN KEY (tenant_id, production_code)
    REFERENCES bps.om_production_codes(tenant_id, production_code) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT chk_om_route_stops_window CHECK (window_from IS NULL OR window_to IS NULL OR window_to >= window_from),
  -- one route per ship-to per day and code: nobody is on two routes, so stamping is never ambiguous
  CONSTRAINT uq_om_route_stops_ship_to UNIQUE (tenant_id, day_of_week, production_code, ship_to_customer_id),
  CONSTRAINT uq_om_route_stops_stop_no UNIQUE (route_id, day_of_week, production_code, stop_no) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX IF NOT EXISTS idx_om_route_stops_customer ON bps.om_route_stops (tenant_id, ship_to_customer_id);
COMMENT ON TABLE  bps.om_route_stops IS 'Ship-to locations on a route for one delivery day of week and production code, in stop order (stop_no 1..n, kept by om_route_stops_renumber).';

-- ── om_route_stop_exceptions ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bps.om_route_stop_exceptions (
  exception_id        bigint  PRIMARY KEY DEFAULT nextval('bps.fnd_entity_id_seq'),
  tenant_id           bigint  NOT NULL REFERENCES bps.fnd_tenants(tenant_id) ON DELETE CASCADE,
  exception_date      date    NOT NULL,
  production_code     text    NOT NULL,
  ship_to_customer_id bigint  NOT NULL REFERENCES bps.fnd_customers(customer_id) ON DELETE CASCADE,
  route_id            bigint  REFERENCES bps.om_routes(route_id) ON DELETE CASCADE,
  stop_no             integer CONSTRAINT chk_om_route_stop_exceptions_stop_no CHECK (stop_no IS NULL OR stop_no > 0),
  notes               text    CONSTRAINT chk_om_route_stop_exceptions_notes CHECK (notes IS NULL OR length(notes) <= 500),
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          bigint,
  updated_at          timestamptz NOT NULL DEFAULT now(),
  updated_by          bigint,
  CONSTRAINT fk_om_route_stop_exceptions_code FOREIGN KEY (tenant_id, production_code)
    REFERENCES bps.om_production_codes(tenant_id, production_code) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT chk_om_route_stop_exceptions_kind CHECK ((route_id IS NULL) = (stop_no IS NULL)),
  CONSTRAINT uq_om_route_stop_exceptions UNIQUE (tenant_id, exception_date, production_code, ship_to_customer_id)
);
CREATE INDEX IF NOT EXISTS idx_om_route_stop_exceptions_route ON bps.om_route_stop_exceptions (route_id) WHERE route_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_om_route_stop_exceptions_customer ON bps.om_route_stop_exceptions (ship_to_customer_id);
COMMENT ON TABLE  bps.om_route_stop_exceptions IS 'One-off route changes for one delivery date and production code: route_id NULL = skip the ship-to that day; otherwise it is on route_id at stop_no for that date (add or move).';

-- ── om_shipments: stamped route ────────────────────────────────────────────────
ALTER TABLE bps.om_shipments
  ADD COLUMN IF NOT EXISTS route_id      bigint REFERENCES bps.om_routes(route_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS route_stop_no integer;
CREATE INDEX IF NOT EXISTS idx_om_shipments_route ON bps.om_shipments (route_id) WHERE route_id IS NOT NULL;
COMMENT ON COLUMN bps.om_shipments.route_id      IS 'Route stamped by Process run from Routes Maintenance (delivery day of week + production code, date changes applied).';
COMMENT ON COLUMN bps.om_shipments.route_stop_no IS 'Stop number on route_id stamped by Process run.';

-- Unassigned check: active customers by type.
CREATE INDEX IF NOT EXISTS idx_fnd_customers_ship_to ON bps.fnd_customers (tenant_id, customer_type) WHERE is_active;

-- ── Triggers ───────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_om_routes_set_updated ON bps.om_routes;
CREATE TRIGGER trg_om_routes_set_updated BEFORE UPDATE ON bps.om_routes FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
DROP TRIGGER IF EXISTS trg_om_routes_audit ON bps.om_routes;
CREATE TRIGGER trg_om_routes_audit AFTER INSERT OR DELETE OR UPDATE ON bps.om_routes FOR EACH ROW EXECUTE FUNCTION bps.fn_audit_log('route_id');
DROP TRIGGER IF EXISTS trg_om_route_stops_set_updated ON bps.om_route_stops;
CREATE TRIGGER trg_om_route_stops_set_updated BEFORE UPDATE ON bps.om_route_stops FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
DROP TRIGGER IF EXISTS trg_om_route_stop_exceptions_set_updated ON bps.om_route_stop_exceptions;
CREATE TRIGGER trg_om_route_stop_exceptions_set_updated BEFORE UPDATE ON bps.om_route_stop_exceptions FOR EACH ROW EXECUTE FUNCTION bps.fn_set_updated_at_ts_only();
DROP TRIGGER IF EXISTS trg_om_route_stop_exceptions_audit ON bps.om_route_stop_exceptions;
CREATE TRIGGER trg_om_route_stop_exceptions_audit AFTER INSERT OR DELETE OR UPDATE ON bps.om_route_stop_exceptions FOR EACH ROW EXECUTE FUNCTION bps.fn_audit_log('exception_id');

-- ── Row security (the route functions are SECURITY DEFINER and check access themselves) ──
ALTER TABLE bps.om_routes                ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.om_route_stops           ENABLE ROW LEVEL SECURITY;
ALTER TABLE bps.om_route_stop_exceptions ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON bps.om_routes, bps.om_route_stops, bps.om_route_stop_exceptions TO authenticated;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['om_routes', 'om_route_stops', 'om_route_stop_exceptions'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS pol_%1$s_read ON bps.%1$s', t);
    -- route names are also read by the Route Delivery Report, Process run and Confirm Deliveries (SECURITY INVOKER)
    EXECUTE format($p$CREATE POLICY pol_%1$s_read ON bps.%1$s FOR SELECT TO authenticated USING (
      (SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access_any(%2$L::text[], 'R'))))$p$,
      t, CASE WHEN t = 'om_routes' THEN '{delivery.routes,production.routes,production.process,production.deliveries}' ELSE '{delivery.routes}' END);
    EXECUTE format('DROP POLICY IF EXISTS pol_%1$s_write ON bps.%1$s', t);
    EXECUTE format($p$CREATE POLICY pol_%1$s_write ON bps.%1$s FOR ALL TO authenticated
      USING ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('delivery.routes', 'W'))))
      WITH CHECK ((SELECT bps.fnd_is_trusted()) OR (tenant_id = (SELECT bps.fnd_active_tenant_id()) AND (SELECT bps.fnd_has_access('delivery.routes', 'W'))))$p$, t);
  END LOOP;
END $$;
