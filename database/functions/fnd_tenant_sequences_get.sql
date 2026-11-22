-- ============================================================
-- fnd_tenant_sequences_get  –  numbering settings for order, invoice, shipment and credit memo numbers
-- Returns one row per sequence; a sequence without a row yet comes back with is_configured = false and defaults.
-- ============================================================
CREATE OR REPLACE FUNCTION bps.fnd_tenant_sequences_get(p_tenant_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'bps', 'public'
AS $function$
    SELECT jsonb_agg(jsonb_build_object(
               'sequence_name',    n.sequence_name,
               'label',            n.label,
               'is_configured',    s.sequence_name IS NOT NULL,
               'mask',             COALESCE(s.mask, n.default_mask),
               'start_value',      COALESCE(s.start_value, 1000),
               'next_value',       COALESCE(s.next_value, 1000),
               'increment_by',     COALESCE(s.increment_by, 1),
               'reset_period',     COALESCE(s.reset_period, 'NEVER'),
               'requires_gapless', COALESCE(s.requires_gapless, FALSE)
           ) ORDER BY n.ord)
      FROM (VALUES (1, 'order_number',       'Order numbers',       '####-####'),
                   (2, 'invoice_number',     'Invoice numbers',     'INV-######'),
                   (3, 'shipment_number',    'Shipment numbers',    'SHP-######'),
                   (4, 'credit_memo_number', 'Credit memo numbers', 'CM-######')) AS n(ord, sequence_name, label, default_mask)
      LEFT JOIN fnd_tenant_sequences s ON s.tenant_id = p_tenant_id AND s.sequence_name = n.sequence_name;
$function$;
