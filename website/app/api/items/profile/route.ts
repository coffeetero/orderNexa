import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

const PREP_LABELS: Record<string, string> = {
  SLICED: 'Sliced',
  WRAPPED: 'Wrapped',
  COVERED: 'Covered',
};

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

function asBoolean(value: unknown): boolean {
  return value === true;
}

function hasOption(raw: unknown, code: string): boolean {
  return Array.isArray(raw) && raw.includes(code);
}

function prepSnapshot(codes: string[]) {
  return codes.map((code) => ({
    value: code,
    label: PREP_LABELS[code] ?? code,
  }));
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

  const inactiveOnly = url.searchParams.get('inactive_only') === 'true';
  const user = await getSessionUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const supabase = createClient();

  const [{ data: items, error: itemError }, { data: bpsRows, error: bpsError }, { data: valuesetRows, error: valuesetError }] =
    await Promise.all([
      supabase.rpc('om_items_get', { p_tenant_id: tenantId, p_customer_id: null }),
      supabase.from('bps_items').select('*').eq('tenant_id', tenantId),
      supabase
        .from('fnd_valuesets')
        .select('valueset_id, fnd_valueset_values(value, label, display_order, is_disabled)')
        .eq('tenant_id', tenantId)
        .eq('valueset_code', 'ITEMPREP')
        .maybeSingle(),
    ]);

  if (itemError) return NextResponse.json({ error: `itemError: ${itemError.message}` }, { status: 400 });
  if (bpsError) return NextResponse.json({ error: `bpsError: ${bpsError.message}` }, { status: 400 });
  if (valuesetError) return NextResponse.json({ error: `valuesetError: ${valuesetError.message}` }, { status: 400 });

  let filteredItems = items ?? [];
  if (inactiveOnly && Array.isArray(filteredItems)) {
    filteredItems = filteredItems.filter((item) => !item.is_active);
  }

  const bpsByItem = new Map((bpsRows ?? []).map((row) => [row.item_id, row]));
  const rawPrepValues = valuesetRows?.fnd_valueset_values;
  const prepValues = Array.isArray(rawPrepValues)
    ? rawPrepValues
        .filter((row) => !row.is_disabled)
        .sort((a, b) => Number(a.display_order ?? 0) - Number(b.display_order ?? 0))
    : [];

  const data = filteredItems.map((item) => {
    const bps = bpsByItem.get(item.item_id) ?? {};
    const allowedCodes = Array.isArray(item.allowed_prep_options) ? item.allowed_prep_options : [];
    const defaultCodes = Array.isArray(item.default_prep_options) ? item.default_prep_options : [];
    return {
      ...item,
      dough_type: bps.dough_type ?? null,
      shape: bps.shape ?? null,
      packing: bps.packing ?? null,
      machine_setting: bps.machine_setting ?? null,
      sheeter_setting: bps.sheeter_setting ?? null,
      weight_adjuster: bps.weight_adjuster ?? 0,
      scale_weight: bps.scale_weight ?? 0,
      scale_qty: bps.scale_qty ?? 0,
      is_sliceable: hasOption(allowedCodes, 'SLICED'),
      is_wrappable: hasOption(allowedCodes, 'WRAPPED'),
      is_coverable: hasOption(allowedCodes, 'COVERED'),
      default_sliced: hasOption(defaultCodes, 'SLICED'),
      default_wrapped: hasOption(defaultCodes, 'WRAPPED'),
      default_covered: hasOption(defaultCodes, 'COVERED'),
    };
  });

  return NextResponse.json({ data, prepValues });
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

  const itemPayload = {
    tenant_id: tenantId,
    item_number: itemNumber,
    item_name: itemName,
    item_description: asString(payload.item_description),
    category: asString(payload.category),
    unit_of_sale: asString(payload.unit_of_sale) ?? 'PCS',
    item_weight: parseNumber(payload.item_weight),
    weight_uom: asString(payload.weight_uom),
    box_qty_per_box: parseNumber(payload.box_qty_per_box),
    box_capacity_weight: parseNumber(payload.box_capacity_weight),
    box_capacity_optimal: parseNumber(payload.box_capacity_optimal),
    sales_terms_apply: payload.sales_terms_apply !== false,
    is_active: payload.is_active !== false,
    allowed_prep_options: allowedPrepOptions,
    default_prep_options: defaultPrepOptions,
  };

  const itemResult = itemId === null
    ? await supabase.from('fnd_items').insert(itemPayload).select('item_id').single()
    : await supabase
        .from('fnd_items')
        .update(itemPayload)
        .eq('tenant_id', tenantId)
        .eq('item_id', itemId)
        .select('item_id')
        .single();

  if (itemResult.error) {
    return NextResponse.json({ error: itemResult.error.message }, { status: 400 });
  }

  const savedItemId = itemResult.data.item_id;
  const bpsPayload = {
    tenant_id: tenantId,
    item_id: savedItemId,
    dough_type: asString(payload.dough_type),
    shape: asString(payload.shape),
    packing: asString(payload.packing),
    machine_setting: asString(payload.machine_setting),
    sheeter_setting: asString(payload.sheeter_setting),
    weight_adjuster: parseNumber(payload.weight_adjuster) ?? 0,
    scale_weight: parseNumber(payload.scale_weight) ?? 0,
    scale_qty: parseNumber(payload.scale_qty) ?? 0,
    is_sliceable: allowedPrepOptions.includes('SLICED'),
    is_wrappable: allowedPrepOptions.includes('WRAPPED'),
    is_coverable: allowedPrepOptions.includes('COVERED'),
    default_sliced: defaultPrepOptions.includes('SLICED'),
    default_wrapped: defaultPrepOptions.includes('WRAPPED'),
    default_covered: defaultPrepOptions.includes('COVERED'),
  };

  const { error: bpsError } = await supabase
    .from('bps_items')
    .upsert(bpsPayload, { onConflict: 'item_id' });

  if (bpsError) {
    return NextResponse.json({ error: bpsError.message }, { status: 400 });
  }

  return NextResponse.json({
    data: {
      item_id: savedItemId,
      allowed_prep_options: prepSnapshot(allowedPrepOptions),
      default_prep_options: prepSnapshot(defaultPrepOptions),
    },
  });
}
