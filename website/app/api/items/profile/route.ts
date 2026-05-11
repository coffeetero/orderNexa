import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

const VALUESET_CODES = ['ITEMCATEGORY', 'ITEMDOUGH', 'ITEMSHAPE', 'ITEMPACKING', 'ITEMUNIT'] as const;
type ValuesetCode = typeof VALUESET_CODES[number];
type LookupOption = { value: string; label: string };

function parseInteger(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed)) return null;
  return parsed;
}

function parseNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function asString(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const text = String(value).trim();
  return text.length > 0 ? text : null;
}

function prepCodes(payload: Record<string, unknown>, prefix: 'allowed' | 'default') {
  const field = prefix === 'allowed' ? 'allowed_prep_options' : 'default_prep_options';
  const raw = payload[field];
  if (Array.isArray(raw)) {
    return raw
      .map((value) => String(value).trim().toUpperCase())
      .filter((value) => value.length > 0);
  }
  return [];
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const tenantId = parseInteger(url.searchParams.get('tenant_id'));
  if (tenantId === null) {
    return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const supabase = createClient();
  const itemId = parseInteger(url.searchParams.get('item_id'));

  // ── Detail mode: single item requested ──────────────────────────────────
  if (itemId !== null) {
    const { data, error } = await supabase.rpc('fnd_items_profile_get', {
      p_tenant_id: tenantId,
      p_item_id: itemId,
    });
    if (error) return NextResponse.json({ error: error.message }, { status: 400 });
    const row = Array.isArray(data) ? (data[0] ?? null) : (data ?? null);
    return NextResponse.json({ data: row });
  }

  // ── List mode: slim list + valueset lookups + prep options ───────────────
  const inactiveOnly = url.searchParams.get('inactive_only') === 'true';

  const [
    { data: items, error: itemError },
    { data: omItems, error: omError },
    { data: vsRows, error: vsError },
  ] = await Promise.all([
    supabase.rpc('fnd_items_profile_get', { p_tenant_id: tenantId, p_inactive_only: inactiveOnly }),
    supabase.rpc('om_items_get_v2', { p_tenant_id: tenantId }),
    supabase
      .from('fnd_valuesets')
      .select('valueset_id, valueset_code')
      .eq('tenant_id', tenantId)
      .in('valueset_code', VALUESET_CODES as unknown as string[]),
  ]);

  if (itemError) return NextResponse.json({ error: `itemError: ${itemError.message}` }, { status: 400 });
  if (omError) return NextResponse.json({ error: `omError: ${omError.message}` }, { status: 400 });
  if (vsError) return NextResponse.json({ error: `vsError: ${vsError.message}` }, { status: 400 });

  // Resolve valueset values for all 5 lookup dropdowns in one query
  const lookups: Record<ValuesetCode, LookupOption[]> = {
    ITEMCATEGORY: [], ITEMDOUGH: [], ITEMSHAPE: [], ITEMPACKING: [], ITEMUNIT: [],
  };
  const vsIdToCode = new Map<number, ValuesetCode>();
  for (const vs of (vsRows ?? [])) {
    if (VALUESET_CODES.includes(vs.valueset_code as ValuesetCode)) {
      vsIdToCode.set(vs.valueset_id as number, vs.valueset_code as ValuesetCode);
    }
  }
  if (vsIdToCode.size > 0) {
    const { data: vvRows, error: vvError } = await supabase
      .from('fnd_valueset_values')
      .select('valueset_id, value, label')
      .eq('tenant_id', tenantId)
      .in('valueset_id', Array.from(vsIdToCode.keys()))
      .eq('is_disabled', false)
      .order('display_order');
    if (vvError) return NextResponse.json({ error: `vvError: ${vvError.message}` }, { status: 400 });
    for (const row of (vvRows ?? [])) {
      const code = vsIdToCode.get(row.valueset_id as number);
      if (code) lookups[code].push({ value: row.value as string, label: row.label as string });
    }
  }

  // Aggregate unique prep options (labels resolved via om_items_get_v2)
  const seen = new Set<string>();
  const prepValues: LookupOption[] = [];
  for (const item of (Array.isArray(omItems) ? omItems : [])) {
    for (const opt of (Array.isArray(item.allowed_prep_options) ? item.allowed_prep_options : [])) {
      if (opt?.value && !seen.has(opt.value)) {
        seen.add(opt.value);
        prepValues.push({ value: opt.value, label: opt.label ?? opt.value });
      }
    }
  }

  return NextResponse.json({
    data: items ?? [],
    prepValues,
    categories: lookups.ITEMCATEGORY,
    doughTypes: lookups.ITEMDOUGH,
    shapes: lookups.ITEMSHAPE,
    packings: lookups.ITEMPACKING,
    units: lookups.ITEMUNIT,
  });
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }

  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return NextResponse.json({ error: 'Expected a JSON object' }, { status: 400 });
  }

  const payload = body as Record<string, unknown>;
  const tenantId = parseInteger(payload.tenant_id);
  if (tenantId === null) {
    return NextResponse.json({ error: 'Invalid tenant_id' }, { status: 400 });
  }

  const user = await getSessionUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const itemNumber = asString(payload.item_number);
  const itemName = asString(payload.item_name);
  if (!itemNumber || !itemName) {
    return NextResponse.json({ error: 'Item No. and Item Description are required.' }, { status: 400 });
  }

  const allowedPrepOptions = prepCodes(payload, 'allowed');
  const defaultPrepOptions = prepCodes(payload, 'default').filter((code) => allowedPrepOptions.includes(code));
  const itemId = parseInteger(payload.item_id);
  const supabase = createClient();

  const { data, error } = await supabase.rpc('fnd_items_profile_save', {
    p_tenant_id:            tenantId,
    p_item_id:              itemId,
    p_item_number:          itemNumber,
    p_item_name:            itemName,
    p_item_description:     asString(payload.item_description),
    p_category:             asString(payload.category),
    p_unit_of_sale:         asString(payload.unit_of_sale) ?? 'PCS',
    p_item_weight:          parseNumber(payload.item_weight),
    p_weight_uom:           asString(payload.weight_uom),
    p_box_qty_per_box:      parseNumber(payload.box_qty_per_box),
    p_box_capacity_weight:  parseNumber(payload.box_capacity_weight),
    p_box_capacity_optimal: parseNumber(payload.box_capacity_optimal),
    p_sales_terms_apply:    payload.sales_terms_apply !== false,
    p_is_active:            payload.is_active !== false,
    p_allowed_prep_options: allowedPrepOptions,
    p_default_prep_options: defaultPrepOptions,
    p_dough_type:           asString(payload.dough_type),
    p_shape:                asString(payload.shape),
    p_packing:              asString(payload.packing),
    p_machine_setting:      asString(payload.machine_setting),
    p_sheeter_setting:      asString(payload.sheeter_setting),
    p_weight_adjuster:      parseNumber(payload.weight_adjuster) ?? 0,
    p_scale_weight:         parseNumber(payload.scale_weight) ?? 0,
    p_scale_qty:            parseNumber(payload.scale_qty) ?? 0,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  const savedItemId = (data as { item_id?: number } | null)?.item_id;

  return NextResponse.json({
    data: {
      item_id: savedItemId,
      allowed_prep_options: allowedPrepOptions,
      default_prep_options: defaultPrepOptions,
    },
  });
}
