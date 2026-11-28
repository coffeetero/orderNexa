-- ============================================================
-- add_address_roles
-- Customer addresses get two roles, each held by exactly one of the customer's addresses (one address may hold both):
--   use_as_billing   (new)      Bill to: invoices and statements
--   use_as_shipping  (existing) Ship to: routes, the map, delivery slips
-- and a place for Google's correction, which staff accept or reject on the customer's Contacts tab:
--   suggested_address (new)     Google's version of the address (NULL = none waiting)
-- Google's verdict is kept in google_geocode_response -> 'validation' ({status, at, granularity, ...}).
-- Changing an address's text clears its verification, its suggestion and Google's verdict (and re-queues geocoding),
-- unless the same update marks it verified (accepting Google's suggestion).
-- Backfill: each customer's Bill to = its address labelled Billing, else its primary address, else its first; a customer
-- with no Ship to takes its address labelled Shipping.
-- Revert: ALTER TABLE bps.fnd_contact_points DROP COLUMN use_as_billing, DROP COLUMN suggested_address; and re-create
--         fn_contact_point_geocode_status from database/schema/fnd_contact_points.sql.
-- ============================================================
SET search_path = bps, public;

ALTER TABLE bps.fnd_contact_points ADD COLUMN IF NOT EXISTS use_as_billing boolean NOT NULL DEFAULT false;
ALTER TABLE bps.fnd_contact_points ADD COLUMN IF NOT EXISTS suggested_address text;
COMMENT ON COLUMN bps.fnd_contact_points.use_as_billing IS 'Bill to: the customer address used on invoices and statements. One per customer (the address may also be Ship to).';
COMMENT ON COLUMN bps.fnd_contact_points.suggested_address IS 'Google''s corrected version of this address, waiting for staff to accept or reject. NULL = none.';

CREATE OR REPLACE FUNCTION bps.fn_contact_point_geocode_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.type != 'ADDRESS' THEN
        NEW.geocode_status := 'SKIPPED';
    ELSIF TG_OP = 'UPDATE' AND NEW.value IS DISTINCT FROM OLD.value THEN
        -- Address text changed: queue for re-geocoding
        NEW.geocode_status   := 'PENDING';
        NEW.geocode_attempts := 0;
        NEW.geocoded_at      := NULL;
        -- ...and for verification again, unless this same update verifies it (accepting Google's suggestion)
        IF NEW.is_verified IS NOT DISTINCT FROM OLD.is_verified THEN
            NEW.is_verified       := false;
            NEW.verified_at       := NULL;
            NEW.suggested_address := NULL;
            NEW.google_geocode_response := NEW.google_geocode_response - 'validation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- Bill to backfill: one address per customer
WITH ranked AS (
  SELECT cp.contact_point_id,
         row_number() OVER (PARTITION BY k.tenant_id, k.entity_id
                            ORDER BY cp.use_as_billing DESC, (cp.label = 'Billing') DESC, cp.is_primary DESC, cp.sequence, cp.contact_point_id) AS rn
    FROM bps.fnd_contacts k
    JOIN bps.fnd_contact_points cp ON cp.contact_id = k.contact_id AND cp.tenant_id = k.tenant_id
   WHERE k.source_table = 'fnd_customers' AND k.is_active AND cp.type = 'ADDRESS' AND cp.is_active)
UPDATE bps.fnd_contact_points cp SET use_as_billing = (r.rn = 1)
  FROM ranked r
 WHERE cp.contact_point_id = r.contact_point_id AND cp.use_as_billing IS DISTINCT FROM (r.rn = 1);

-- Ship to backfill: a customer with no Ship to takes its address labelled Shipping (the old system's delivery address)
WITH ranked AS (
  SELECT cp.contact_point_id,
         row_number() OVER (PARTITION BY k.tenant_id, k.entity_id ORDER BY cp.is_primary DESC, cp.sequence, cp.contact_point_id) AS rn
    FROM bps.fnd_contacts k
    JOIN bps.fnd_contact_points cp ON cp.contact_id = k.contact_id AND cp.tenant_id = k.tenant_id
   WHERE k.source_table = 'fnd_customers' AND k.is_active AND cp.type = 'ADDRESS' AND cp.is_active AND cp.label = 'Shipping'
     AND NOT EXISTS (SELECT 1 FROM bps.fnd_contacts k2 JOIN bps.fnd_contact_points c2 ON c2.contact_id = k2.contact_id
                      WHERE k2.tenant_id = k.tenant_id AND k2.source_table = 'fnd_customers' AND k2.entity_id = k.entity_id
                        AND c2.type = 'ADDRESS' AND c2.is_active AND c2.use_as_shipping))
UPDATE bps.fnd_contact_points cp SET use_as_shipping = true
  FROM ranked r
 WHERE cp.contact_point_id = r.contact_point_id AND r.rn = 1;

-- Instructions: delivery directions that belong to an address ("Delivery entrance on 55th St"), kept apart from the postal
-- address so Google checks only the address; the Shipping address's instructions print at the bottom of the invoice.
ALTER TABLE bps.fnd_contact_points ADD COLUMN IF NOT EXISTS instructions text;
COMMENT ON COLUMN bps.fnd_contact_points.instructions IS 'Delivery instructions of an address; the Shipping address''s print at the bottom of the invoice.';

-- Old-system addresses kept directions as middle lines ("(BETWEEN 49TH & 50TH ST)", "CORNER OF 44TH AND 1ST AVE"): move each
-- middle line to instructions unless it looks like part of the address (suite, floor, unit, PO box, or starts with a number).
-- The moved lines are recorded in google_geocode_response -> 'moved_to_instructions' for spot-checking.
WITH pts AS (
  SELECT cp.contact_point_id, x.line, x.n, count(*) OVER (PARTITION BY cp.contact_point_id) AS tot
    FROM bps.fnd_contact_points cp
    JOIN bps.fnd_contacts k ON k.contact_id = cp.contact_id AND k.source_table = 'fnd_customers'
    CROSS JOIN LATERAL regexp_split_to_table(cp.value, '\s*\n\s*') WITH ORDINALITY x(line, n)
   WHERE cp.type = 'ADDRESS' AND cp.instructions IS NULL AND btrim(x.line) <> ''
), marked AS (
  SELECT contact_point_id, line, n,
         n > 1 AND n < tot AND btrim(line) !~* '^(STE|SUITE|FL|FLOOR|APT|UNIT|#|RM|ROOM|BLDG|BUILDING|DEPT|PO BOX|P\.?O\.?\s*BOX)\M' AND btrim(line) !~ '^\d' AS move
    FROM pts
), split AS (
  SELECT contact_point_id,
         string_agg(btrim(line), E'\n' ORDER BY n) FILTER (WHERE NOT move) AS address,
         string_agg(btrim(line), ' ' ORDER BY n) FILTER (WHERE move) AS moved
    FROM marked GROUP BY contact_point_id
)
UPDATE bps.fnd_contact_points cp
   SET value = s.address, instructions = s.moved,
       google_geocode_response = COALESCE(cp.google_geocode_response, '{}'::jsonb) || jsonb_build_object('moved_to_instructions', s.moved)
  FROM split s
 WHERE cp.contact_point_id = s.contact_point_id AND s.moved IS NOT NULL;
-- only a direction line left the address: its map point still holds (the change above re-queued it for geocoding)
UPDATE bps.fnd_contact_points
   SET geocode_status = 'OK'
 WHERE type = 'ADDRESS' AND geocode_status = 'PENDING' AND latitude IS NOT NULL AND google_geocode_response ? 'moved_to_instructions';
