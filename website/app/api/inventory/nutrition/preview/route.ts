import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';

export const dynamic = 'force-dynamic';

/** POST /api/inventory/nutrition/preview { tenant_id, profile } → the label for unsaved values, rounded by the database (inv_nutrition_label_build) */
export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body || typeof body.profile !== 'object' || body.profile === null) return NextResponse.json({ error: 'profile is required' }, { status: 400 });
  return adminRpc(body.tenant_id, 'inv_nutrition_label_build', { p_payload: body.profile });
}
