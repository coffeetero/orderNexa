-- ============================================================
-- ar_dashboard_get
-- Dashboard AR panels: the company's aging totals as of the tenant's today and the accounts with the largest open balances
-- (p_limit), each with its total, over 90 days and over 60 days (61-90 plus over 90).
-- Moved out of add_dashboard_cards.sql when d60_plus was added (Customer Accounts shows Over 60 days).
-- ============================================================
CREATE OR REPLACE FUNCTION bps.ar_dashboard_get(p_tenant_id bigint, p_limit integer DEFAULT 8) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
DECLARE v_today date := (now() AT TIME ZONE bps.fnd_tenant_time_zone(p_tenant_id))::date; v_ids bigint[]; v_aging jsonb;
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  SELECT COALESCE(array_agg((e ->> 'customer_id')::bigint), '{}'::bigint[]) INTO v_ids
    FROM jsonb_array_elements(bps.fnd_report_accounts_get(p_tenant_id, true, NULL, v_today)) e;
  v_aging := bps.ar_aging_get(p_tenant_id, v_ids, v_today);
  RETURN jsonb_build_object('as_of', v_today, 'totals', v_aging -> 'totals',
    'accounts', COALESCE((SELECT jsonb_agg(jsonb_build_object('customer_id', a ->> 'customer_id', 'customer_name', a ->> 'customer_name',
                  'total', a -> 'total', 'd90_plus', a -> 'd90_plus',
                  'd60_plus', COALESCE((a ->> 'd61_90')::numeric, 0) + COALESCE((a ->> 'd90_plus')::numeric, 0)) ORDER BY (a ->> 'total')::numeric DESC, a ->> 'customer_name')
            FROM (SELECT a FROM jsonb_array_elements(v_aging -> 'accounts') a WHERE (a ->> 'total')::numeric <> 0
                   ORDER BY (a ->> 'total')::numeric DESC, a ->> 'customer_name' LIMIT GREATEST(p_limit, 1)) s), '[]'::jsonb));
END $$;

REVOKE EXECUTE ON FUNCTION bps.ar_dashboard_get(bigint, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION bps.ar_dashboard_get(bigint, integer) TO authenticated, service_role, bps_dev;
