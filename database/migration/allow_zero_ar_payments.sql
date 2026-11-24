-- Allow $0 payments. The old BPS used $0 payments to move money between invoices (24 of 25 net to zero, e.g. payment 37004
-- moved $39.10 onto Tom Cat invoice 414034). Without them those applications are lost and old balances change.
-- Negative payment amounts stay refused.
ALTER TABLE bps.ar_payments DROP CONSTRAINT IF EXISTS ar_payments_amount_check;
ALTER TABLE bps.ar_payments ADD CONSTRAINT ar_payments_amount_check CHECK (amount >= 0);
