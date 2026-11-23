-- Order-level shipping: an order is one delivery (one method, shipped or not). Replaces the per-line shipment link for new work.
-- om_orders gets the delivery facts; ar_transaction_lines gets order_id so an invoice line knows its order.
-- The shipment tables stay until the delivery pages are reworked. Then load database/functions/ar_invoice_recognized_amount.sql.
SET search_path = bps, public;

ALTER TABLE bps.om_orders
  ADD COLUMN delivery_method_code text,
  ADD COLUMN shipped_at timestamptz,
  ADD COLUMN shipped_by bigint,
  ADD COLUMN carrier text,
  ADD COLUMN tracking_reference text,
  ADD COLUMN delivery_cost numeric(12,2),
  ADD CONSTRAINT fk_om_orders_delivery_method FOREIGN KEY (tenant_id, delivery_method_code) REFERENCES bps.om_delivery_methods (tenant_id, delivery_method_code),
  ADD CONSTRAINT chk_om_orders_delivery_cost CHECK (delivery_cost IS NULL OR delivery_cost >= 0);

ALTER TABLE bps.ar_transaction_lines
  ADD COLUMN order_id bigint REFERENCES bps.om_orders (order_id) ON DELETE SET NULL;
CREATE INDEX idx_ar_transaction_lines_order ON bps.ar_transaction_lines (tenant_id, order_id);
