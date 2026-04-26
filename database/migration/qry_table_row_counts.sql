-- Row counts for selected public tables (one row per table).
SELECT 'ar_payment_applications' AS table_name, COUNT(*)::bigint AS row_count FROM public.ar_payment_applications
UNION ALL SELECT 'ar_payments', COUNT(*)::bigint FROM public.ar_payments
UNION ALL SELECT 'ar_transaction_lines', COUNT(*)::bigint FROM public.ar_transaction_lines
UNION ALL SELECT 'ar_transactions', COUNT(*)::bigint FROM public.ar_transactions
UNION ALL SELECT 'fnd_audit_log', COUNT(*)::bigint FROM public.fnd_audit_log
UNION ALL SELECT 'fnd_contact_points', COUNT(*)::bigint FROM public.fnd_contact_points
UNION ALL SELECT 'fnd_currencies', COUNT(*)::bigint FROM public.fnd_currencies
UNION ALL SELECT 'fnd_customer_pricebooks', COUNT(*)::bigint FROM public.fnd_customer_pricebooks
UNION ALL SELECT 'fnd_customers', COUNT(*)::bigint FROM public.fnd_customers
UNION ALL SELECT 'fnd_item_bom', COUNT(*)::bigint FROM public.fnd_item_bom
UNION ALL SELECT 'fnd_items', COUNT(*)::bigint FROM public.fnd_items
UNION ALL SELECT 'fnd_people', COUNT(*)::bigint FROM public.fnd_people
UNION ALL SELECT 'fnd_pricebook_items', COUNT(*)::bigint FROM public.fnd_pricebook_items
UNION ALL SELECT 'fnd_pricebooks', COUNT(*)::bigint FROM public.fnd_pricebooks
UNION ALL SELECT 'fnd_tenants', COUNT(*)::bigint FROM public.fnd_tenants
UNION ALL SELECT 'fnd_user_customers', COUNT(*)::bigint FROM public.fnd_user_customers
UNION ALL SELECT 'fnd_user_tenants', COUNT(*)::bigint FROM public.fnd_user_tenants
UNION ALL SELECT 'fnd_users', COUNT(*)::bigint FROM public.fnd_users
UNION ALL SELECT 'om_order_lines', COUNT(*)::bigint FROM public.om_order_lines
UNION ALL SELECT 'om_order_shipments', COUNT(*)::bigint FROM public.om_order_shipments
UNION ALL SELECT 'om_orders', COUNT(*)::bigint FROM public.om_orders
ORDER BY table_name;
