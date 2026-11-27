-- ============================================================
-- add_ar_settlements
-- A settled amount on AR documents: part of an invoice / credit memo / debit memo, or of a payment's unapplied cash, that is
-- treated as closed without a payment or credit behind it. It counts like an allowance: from settled_at (the tenant's day)
-- an invoice's settled amount counts as paid and a payment's settled amount counts as applied.
--
-- First use: the data migration settles documents the old system shows as closed (its stored balance is 0) but whose rebuilt
-- applications leave something open (the old payment detail applies some payments twice). Later: write-offs.
--
--   ar_transactions.settled_amount  same sign as the open amount it closes (an overpaid invoice is settled with a negative amount)
--   ar_payments.settled_amount      positive: unapplied cash treated as used
--   settled_at, settled_reason      when and why
-- Functions that compute open or unapplied amounts take it into account (see the functions listed in docs).
-- ============================================================
ALTER TABLE bps.ar_transactions
  ADD COLUMN IF NOT EXISTS settled_amount numeric(14,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS settled_at timestamptz,
  ADD COLUMN IF NOT EXISTS settled_reason text;

ALTER TABLE bps.ar_payments
  ADD COLUMN IF NOT EXISTS settled_amount numeric(14,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS settled_at timestamptz,
  ADD COLUMN IF NOT EXISTS settled_reason text;

COMMENT ON COLUMN bps.ar_transactions.settled_amount IS 'Part of the open amount treated as closed (same sign as the open amount); counts as paid from settled_at.';
COMMENT ON COLUMN bps.ar_payments.settled_amount IS 'Unapplied cash treated as used (positive); counts as applied from settled_at.';
