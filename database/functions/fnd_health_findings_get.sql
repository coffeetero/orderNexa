-- ============================================================
-- fnd_health_findings_get(tenant, include_fixed) → open findings (and those fixed in the last 30 days when include_fixed), errors first.
-- Replaces the version in migration/add_health_checks.sql. Adds record_name: the customer's number and current name ("15100 · MRS BAKING";
-- several old accounts share a name such as ORDER) for customer findings
-- (the check's heading already says what is wrong, so lists show just the name), NULL otherwise.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_health_findings_get(p_tenant_id bigint, p_include_fixed boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = bps, public AS $$
BEGIN
  PERFORM bps.fnd_assert_active_tenant(p_tenant_id);
  IF NOT bps.fnd_has_access('admin.health', 'R') THEN RAISE EXCEPTION 'Not authorised to view health checks'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('log_id', l.log_id, 'check_code', l.check_code, 'check_name', h.name, 'category', h.category, 'type', l.type,
      'found_at', l.found_at, 'findings', l.findings, 'remediation', l.remediation, 'record_type', l.record_type, 'record_id', l.record_id,
      'customer_id', l.customer_id, 'record_name', CASE WHEN l.record_type = 'CUSTOMER' THEN concat_ws(' · ', c.customer_number, c.customer_name) END,
      'link_path', l.link_path, 'fixed_at', l.fixed_at, 'fixed_by_name', u.user_name)
      ORDER BY (l.fixed_at IS NOT NULL), CASE l.type WHEN 'Error' THEN 1 WHEN 'Warning' THEN 2 ELSE 3 END, l.found_at DESC)
    FROM bps.fnd_health_log l
    JOIN bps.fnd_health_checks h ON h.tenant_id = l.tenant_id AND h.check_code = l.check_code
    LEFT JOIN bps.fnd_customers c ON c.tenant_id = l.tenant_id AND c.customer_id = l.customer_id
    LEFT JOIN bps.fnd_users u ON u.user_id = l.fixed_by
   WHERE l.tenant_id = p_tenant_id AND (l.fixed_at IS NULL OR (p_include_fixed AND l.fixed_at > now() - interval '30 days'))), '[]'::jsonb);
END $$;
