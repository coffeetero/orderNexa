-- ============================================================
-- fnd_contacts_get
-- Returns all active contacts (with nested contact_points)
-- for a given entity. Used by the Contacts tab.
--
-- Order: ADDRESSES first, OTHER_CONTACTS second, PERSON after
-- (sorted by is_primary DESC, card_name within PERSON).
--
-- SECURITY DEFINER — bypasses RLS; tenant validated via JWT.
-- ============================================================

CREATE OR REPLACE FUNCTION bps.fnd_contacts_get(
  p_tenant_id    BIGINT,
  p_entity_id    BIGINT,
  p_source_table TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = bps, public
AS $$
BEGIN
  IF NOT (
    p_tenant_id::text = ANY (ARRAY(
      SELECT jsonb_array_elements_text(
        (NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb
          -> 'app_metadata' -> 'allowed_tenant_ids'
      )
    ))
  ) THEN
    RAISE EXCEPTION 'Access denied for tenant %', p_tenant_id;
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'contact_id',   c.contact_id,
        'contact_type', c.contact_type,
        'card_name',    c.card_name,
        'display_name', COALESCE(c.display_name, ''),
        'first_name',   COALESCE(c.first_name, ''),
        'last_name',    COALESCE(c.last_name, ''),
        'job_title',    COALESCE(c.job_title, ''),
        'department',   COALESCE(c.department, ''),
        'is_primary',   c.is_primary,
        'is_active',    c.is_active,
        'contact_points', COALESCE((
          SELECT jsonb_agg(
            jsonb_build_object(
              'contact_point_id',  cp.contact_point_id,
              'type',              cp.type,
              'value',             cp.value,
              'label',             COALESCE(cp.label, ''),
              'sequence',          cp.sequence,
              'is_primary',        cp.is_primary,
              'is_active',         cp.is_active,
              'do_not_contact',    cp.do_not_contact,
              'use_as_shipping',   cp.use_as_shipping,
              'country_dial_code', COALESCE(cp.country_dial_code, ''),
              'geocode_status',    cp.geocode_status,
              'formatted_address', cp.formatted_address,
              'latitude',          cp.latitude,
              'longitude',         cp.longitude
            )
            ORDER BY cp.sequence, cp.contact_point_id
          )
          FROM fnd_contact_points cp
          WHERE cp.contact_id = c.contact_id
            AND cp.tenant_id  = p_tenant_id
            AND cp.is_active  = TRUE
        ), '[]'::jsonb)
      )
      ORDER BY
        CASE c.contact_type
          WHEN 'ADDRESSES'       THEN 0
          WHEN 'OTHER_CONTACTS'  THEN 1
          ELSE 2
        END,
        c.is_primary DESC,
        c.card_name
    )
    FROM fnd_contacts c
    WHERE c.tenant_id    = p_tenant_id
      AND c.entity_id    = p_entity_id
      AND c.source_table = p_source_table
      AND c.is_active    = TRUE
  ), '[]'::jsonb);
END;
$$;
