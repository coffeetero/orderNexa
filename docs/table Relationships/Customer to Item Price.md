-- customer to item price
select 
  cus.customer_number,
  cus.customer_name,
  cus.customer_type,
  itm.item_number,
  itm.item_name,
  itmPrc.item_price 
from 
  fnd_customers cus,
  fnd_customer_pricebooks fcp,
  fnd_pricebooks prcBk,
  fnd_pricebook_items itmPrc,
  fnd_items itm
where 
  fcp.customer_id = cus.customer_id
  and prcBk.pricebook_id = fcp.pricebook_id 
  and itmPrc.pricebook_id = prcBk.pricebook_id 
  and itm.item_id = itmPrc.item_id
order by
 1,2