-- ============================================================
-- ar_quantity_credited_refresh
-- Recalculates ar_transaction_lines.quantity_credited for the given invoice lines: the sum of the quantities on credit memo
-- lines (snapshot_data.credits_line_id) whose credit memo is not cancelled. Called by the triggers in
-- migration/add_quantity_credited.sql; safe to call by hand to repair a line. Only updates lines whose value changes.
-- plpgsql so it can be loaded before the column exists.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_quantity_credited_refresh(p_line_ids bigint[])
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'bps', 'public'
AS $function$
BEGIN
    UPDATE bps.ar_transaction_lines il
       SET quantity_credited = x.credited
      FROM (SELECT il2.ar_transaction_line_id AS id,
                   COALESCE((SELECT SUM(cl.quantity) FROM bps.ar_transaction_lines cl
                               JOIN bps.ar_transactions ct ON ct.ar_transaction_id = cl.ar_transaction_id
                              WHERE cl.snapshot_data ? 'credits_line_id'
                                AND (cl.snapshot_data ->> 'credits_line_id')::bigint = il2.ar_transaction_line_id
                                AND ct.status <> 'CANCELLED'), 0) AS credited
              FROM bps.ar_transaction_lines il2
             WHERE il2.ar_transaction_line_id = ANY (p_line_ids)) x
     WHERE il.ar_transaction_line_id = x.id AND il.quantity_credited IS DISTINCT FROM x.credited;
END
$function$;
REVOKE EXECUTE ON FUNCTION bps.ar_quantity_credited_refresh(bigint[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bps.ar_quantity_credited_refresh(bigint[]) TO authenticated, service_role;
