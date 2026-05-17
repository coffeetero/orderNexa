-- Add optional customer purchase order/reference number to order headers.
ALTER TABLE bps.om_orders
    ADD COLUMN IF NOT EXISTS po_number TEXT;
