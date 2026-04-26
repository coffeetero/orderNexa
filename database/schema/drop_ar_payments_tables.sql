-- Drop AR payment tables (applications first — references ar_payments).
-- Use before re-applying ar_payments.sql + ar_payment_applications.sql.
SET statement_timeout = '120s';
DROP TABLE IF EXISTS ar_payment_applications CASCADE;
DROP TABLE IF EXISTS ar_payments CASCADE;
