import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';

/** Shared plumbing for the admin API routes: staff check, tenant_id parsing, RPC call, error mapping. Row security decides what the caller may do. */
export async function adminRpc(
  tenantIdRaw: unknown,
  fn: string,
  args: Record<string, unknown>,
): Promise<NextResponse> {
  const tenantId = toInt(tenantIdRaw);
  if (tenantId === null) return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const { data, error } = await createClient().rpc(fn, { p_tenant_id: tenantId, ...args });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function readBody(request: Request): Promise<Record<string, unknown> | null> {
  try {
    return (await request.json()) as Record<string, unknown>;
  } catch {
    return null;
  }
}
