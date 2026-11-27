import { NextResponse } from 'next/server';
import { adminRpc } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** DELETE /api/inventory/recipes/:id?tenant_id=n → deletes the recipe (inv_recipe_delete); refused while another recipe uses it. */
export async function DELETE(request: Request, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  const id = toInt(params.id);
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'inv_recipe_delete', { p_recipe_id: id });
}
