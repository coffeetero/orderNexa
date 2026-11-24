import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

/**
 * POST /api/organizer/sheets/bps { tenant_id, calls: [{ fn, args: [...] }] }
 *      → [{ v } | { e, message }] in the same order (org_sheet_bps_eval). Runs as the user; access is checked per function.
 */
export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body || !Array.isArray(body.calls)) return NextResponse.json({ error: 'calls must be an array' }, { status: 400 });
  if (body.calls.length > 500) return NextResponse.json({ error: 'Too many BPS functions in one sheet (over 500)' }, { status: 400 });
  const calls = (body.calls as unknown[]).map((c) => {
    const o = (c ?? {}) as Record<string, unknown>;
    const args = Array.isArray(o.args) ? o.args.slice(0, 5).map((a) => (a === null || a === undefined ? null : String(a).slice(0, 100))) : [];
    return { fn: String(o.fn ?? '').slice(0, 40), args };
  });
  return adminRpc(body.tenant_id, 'org_sheet_bps_eval', { p_calls: calls });
}
