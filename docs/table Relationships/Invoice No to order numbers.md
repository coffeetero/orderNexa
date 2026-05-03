 -- customer invoice No to order numbers
 select
   cus.customer_id, cus.customer_number, cus.customer_name,
   arInv.document_number as invoice_number,
   ordr.order_number 
 from
   ar_transactions arInv,
   ar_transaction_lines arTrxLn,
   om_order_shipments ordrShpmt,
   om_order_lines ordrLn,
   om_orders ordr,
   fnd_customers cus 
 where
  arTrxLn.ar_transaction_id = arInv.ar_transaction_id 
  and ordrShpmt.order_shipment_id = arTrxLn.order_shipment_id 
  and ordrLn.order_line_id = ordrShpmt.order_line_id 
  and ordr.order_id = ordrLn.order_id 
  and cus.customer_id = ordr.customer_id 
 
  