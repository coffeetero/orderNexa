#cursorSqlTablesAliases

Use this as the default alias reference when writing SQL in this repo.

| Table | Alias |
|---|---|
| `auth.users` | `authUsr` |
| `ar_payment_applications` | `pmtApp` |
| `ar_payments` | `pmt` |
| `ar_transaction_lines` | `arTrxLn` |
| `ar_transactions` | `arTrx` |
| `fnd_audit_log` | `aLog` |
| `fnd_contact_points` | `cntctPnt` |
| `fnd_currencies` | `curr` |
| `fnd_customer_pricebooks` | `cusPrcBk` |
| `fnd_customers` | `cus` |
| `fnd_item_bom` | `itmBom` |
| `fnd_items` | `itm` |
| `fnd_people` | `prsn` |
| `fnd_pricebooks` | `prcBk` |
| `fnd_pricebook_items` | `prcBkItm` |
| `fnd_tenants` | `tnt` |
| `fnd_user_customers` | `usrCus` |
| `fnd_user_tenants` | `usrTnt` |
| `fnd_users` | `usr` |
| `om_order_lines` | `ordrLn` |
| `om_order_shipments` | `ordrShpmnt` |
| `om_orders` | `ordr` |




Notes:
- Keep aliases consistent across all new SQL scripts and migrations.
- When adding new table aliases, append them here before using them.
