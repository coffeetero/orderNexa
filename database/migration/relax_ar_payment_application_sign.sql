-- A payment can net a credit (a negative invoice) in the same remittance. The old system recorded that as a positive pd_pmt_amt row
-- against the credit. For the conversion that is stored as a negative applied_amount. Zero stays blocked.
-- Not textbook credit application (see docs/backlog.md section 4); it keeps balances equal to the old system.
SET search_path = bps, public;
ALTER TABLE bps.ar_payment_applications DROP CONSTRAINT ar_payment_applications_applied_amount_check;
ALTER TABLE bps.ar_payment_applications ADD CONSTRAINT ar_payment_applications_applied_amount_check CHECK (applied_amount <> 0);
