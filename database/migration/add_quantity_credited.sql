-- ar_transaction_lines.quantity_credited: on an invoice line, the quantity credited so far by credit memos that are not
-- cancelled. Kept by triggers (ar_quantity_credited_refresh) on the credit memo lines and on a credit memo's status, so no
-- screen or function has to remember it; Enter Credits shows it and ar_credit_memo_create limits new credits with it.
-- Only the quantity is stored (no amount), by owner decision 2026-11-25.
-- New column: quantity_credited numeric(14,4) NOT NULL DEFAULT 0. Load functions/ar_quantity_credited_refresh.sql first.
ALTER TABLE bps.ar_transaction_lines ADD COLUMN IF NOT EXISTS quantity_credited numeric(14,4) NOT NULL DEFAULT 0;
COMMENT ON COLUMN bps.ar_transaction_lines.quantity_credited IS
  'Invoice lines: quantity credited by credit memos that are not cancelled. Kept by triggers (ar_quantity_credited_refresh); never edited by hand.';

-- credit memo lines point at the invoice line they credit in snapshot_data.credits_line_id
CREATE INDEX IF NOT EXISTS idx_ar_transaction_lines_credits_line
  ON bps.ar_transaction_lines (((snapshot_data ->> 'credits_line_id')::bigint)) WHERE snapshot_data ? 'credits_line_id';

CREATE OR REPLACE FUNCTION bps.ar_quantity_credited_trg_lines()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'bps', 'public' AS $function$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.snapshot_data ? 'credits_line_id' THEN
    PERFORM bps.ar_quantity_credited_refresh(ARRAY[(OLD.snapshot_data ->> 'credits_line_id')::bigint]);
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.snapshot_data ? 'credits_line_id' THEN
    PERFORM bps.ar_quantity_credited_refresh(ARRAY[(NEW.snapshot_data ->> 'credits_line_id')::bigint]);
  END IF;
  RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION bps.ar_quantity_credited_trg_status()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'bps', 'public' AS $function$
BEGIN
  PERFORM bps.ar_quantity_credited_refresh(ARRAY(
    SELECT (l.snapshot_data ->> 'credits_line_id')::bigint FROM bps.ar_transaction_lines l
     WHERE l.ar_transaction_id = NEW.ar_transaction_id AND l.snapshot_data ? 'credits_line_id'));
  RETURN NULL;
END $function$;

DROP TRIGGER IF EXISTS trg_ar_transaction_lines_quantity_credited ON bps.ar_transaction_lines;
CREATE TRIGGER trg_ar_transaction_lines_quantity_credited
  AFTER INSERT OR UPDATE OF quantity, snapshot_data, ar_transaction_id OR DELETE ON bps.ar_transaction_lines
  FOR EACH ROW EXECUTE FUNCTION bps.ar_quantity_credited_trg_lines();

DROP TRIGGER IF EXISTS trg_ar_transactions_quantity_credited ON bps.ar_transactions;
CREATE TRIGGER trg_ar_transactions_quantity_credited
  AFTER UPDATE OF status ON bps.ar_transactions
  FOR EACH ROW WHEN (NEW.transaction_type = 'CM' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION bps.ar_quantity_credited_trg_status();

-- Fill from the credit memos already entered.
SELECT bps.ar_quantity_credited_refresh(ARRAY(
  SELECT DISTINCT (snapshot_data ->> 'credits_line_id')::bigint FROM bps.ar_transaction_lines WHERE snapshot_data ? 'credits_line_id'));
