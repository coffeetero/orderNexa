import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

/**
 * GET  /api/admin/format-settings?tenant_id=n → { customer_number_mask, item_number_mask, invoice_footer_note, invoice_tagline }
 * POST /api/admin/format-settings { tenant_id, customer_number_mask, item_number_mask, invoice_footer_note, invoice_tagline }
 *      → saved settings (empty mask = print numbers as stored; empty note or tagline = not printed)
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'fnd_format_settings_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  const t = (v: unknown, max: number) => (typeof v === 'string' ? v.slice(0, max) : null);
  return adminRpc(body.tenant_id, 'fnd_format_settings_save', {
    p_payload: {
      customer_number_mask: t(body.customer_number_mask, 30), item_number_mask: t(body.item_number_mask, 30),
      invoice_footer_note: t(body.invoice_footer_note, 300), invoice_tagline: t(body.invoice_tagline, 100),
    },
  });
}
