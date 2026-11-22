-- ============================================================
-- ar_invoice_recognized_amount
-- The part of an invoice that counts toward the customer's balance: each ITEM line at shipped_quantity x unit_price once
-- its shipment is SHIPPED or DELIVERED, plus a DELIVERY line when any item of the same order has shipped. Invoices that are
-- DRAFT or CANCELLED recognise nothing.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_invoice_recognized_amount(p_ar_transaction_id bigint)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT COALESCE(SUM(CASE
               WHEN l.source_type = 'ITEM' THEN COALESCE(sl.shipped_quantity, 0) * COALESCE(l.unit_price, 0)
               WHEN l.source_type = 'DELIVERY' THEN CASE WHEN EXISTS (
                       SELECT 1 FROM ar_transaction_lines il
                         JOIN om_shipment_lines isl ON isl.shipment_line_id = il.shipment_line_id
                         JOIN om_shipments ish ON ish.shipment_id = isl.shipment_id AND ish.shipment_status IN ('SHIPPED', 'DELIVERED')
                        WHERE il.ar_transaction_id = l.ar_transaction_id AND il.source_type = 'ITEM'
                          AND il.snapshot_data ->> 'order_id' = l.snapshot_data ->> 'order_id' AND COALESCE(isl.shipped_quantity, 0) > 0
                   ) THEN l.amount ELSE 0 END
               ELSE 0 END), 0)
      FROM ar_transactions t
      JOIN ar_transaction_lines l ON l.ar_transaction_id = t.ar_transaction_id
      LEFT JOIN om_shipment_lines sl ON sl.shipment_line_id = l.shipment_line_id
      LEFT JOIN om_shipments s ON s.shipment_id = sl.shipment_id AND s.shipment_status IN ('SHIPPED', 'DELIVERED')
     WHERE t.ar_transaction_id = p_ar_transaction_id AND t.transaction_type = 'INV' AND t.status NOT IN ('DRAFT', 'CANCELLED')
       AND (l.source_type <> 'ITEM' OR s.shipment_id IS NOT NULL);
$function$;
