-- Indexes for Enter Credits' lookup by invoice number or PO number (ar_credit_find). The existing unique index on
-- ar_transactions starts with customer_id, so an invoice number alone scanned every AR document; PO numbers had no index.
-- No new tables or columns.
CREATE INDEX IF NOT EXISTS idx_ar_transactions_document_number ON bps.ar_transactions (tenant_id, document_number);
CREATE INDEX IF NOT EXISTS idx_om_orders_po_number ON bps.om_orders (tenant_id, UPPER(TRIM(po_number))) WHERE po_number IS NOT NULL;
