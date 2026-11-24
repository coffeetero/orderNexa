import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

const isDate = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);

/**
 * GET  /api/orders/import?tenant_id=n&from=YYYY-MM-DD&to=YYYY-MM-DD → imports in that production date range (om_order_imports_get)
 * GET  /api/orders/import?tenant_id=n&id=n                          → one import with its rows and orders (om_order_import_get)
 * POST /api/orders/import { tenant_id, customer_id, production_date, production_code, file_name, rows: [{cus_no, item_number, item_desc, qty}] }
 *      → imports the file (om_order_import_upload); replaces a not-yet-approved import for the same customer, date and code
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = q.get('id');
  if (id) return adminRpc(q.get('tenant_id'), 'om_order_import_get', { p_order_import_id: Number(id) });
  const from = q.get('from');
  const to = q.get('to');
  if ((from && !isDate(from)) || (to && !isDate(to))) return NextResponse.json({ error: 'from and to must be YYYY-MM-DD' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'om_order_imports_get', { p_from: from || null, p_to: to || null });
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if (!isDate(body.production_date)) return NextResponse.json({ error: 'production_date is required' }, { status: 400 });
  if (!Array.isArray(body.rows) || body.rows.length === 0) return NextResponse.json({ error: 'The file has no rows' }, { status: 400 });
  if (body.rows.length > 10000) return NextResponse.json({ error: 'The file has more than 10,000 rows' }, { status: 400 });
  const rows = (body.rows as unknown[]).map((r) => {
    const o = (r ?? {}) as Record<string, unknown>;
    const s = (v: unknown) => (v === null || v === undefined ? '' : String(v).slice(0, 200));
    return { cus_no: s(o.cus_no), item_number: s(o.item_number), item_desc: s(o.item_desc), qty: s(o.qty) };
  });
  return adminRpc(body.tenant_id, 'om_order_import_upload', {
    p_payload: {
      customer_id: body.customer_id, production_date: body.production_date, production_code: body.production_code,
      file_name: typeof body.file_name === 'string' ? body.file_name.slice(0, 200) : null, rows,
    },
  });
}
