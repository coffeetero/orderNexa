-- An invoice counts in AR at its amount once it is issued (not DRAFT or CANCELLED), so the shipment-based rule is gone.
-- Load first (they no longer call it): functions/ar_customer_balance_get.sql, ar_document_lookup.sql, ar_invoice_document_get.sql,
-- ar_report_open_items.sql, ar_sales_report_get.sql, ar_revenue_forecast_get.sql. Then run this file.
SET search_path = bps, public;
DROP FUNCTION IF EXISTS bps.ar_invoice_recognized_amount(bigint);
