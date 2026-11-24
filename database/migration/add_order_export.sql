-- Order export (2026-11-24): import and export files share one layout:
--   Cus no, Customer, Department/Event, Item no, Item description, Qty
-- Department/Event: rows of one customer number with different events become separate orders (resellers put their own
-- customer code here). Customer: optional; when filled it is compared with the customer's name (fuzzy, pg_trgm) and a
-- clear mismatch is a warning.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
ALTER TABLE bps.om_order_import_rows ADD COLUMN IF NOT EXISTS department_event text;
ALTER TABLE bps.om_order_import_rows ADD COLUMN IF NOT EXISTS customer_name text;
