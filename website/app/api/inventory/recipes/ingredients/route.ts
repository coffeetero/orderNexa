import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/**
 * GET    /api/inventory/recipes/ingredients?tenant_id=n          → the ingredient catalog (inv_ingredients_get)
 * POST   /api/inventory/recipes/ingredients { tenant_id, ingredient } → creates or saves an ingredient (inv_ingredient_save)
 * DELETE /api/inventory/recipes/ingredients?tenant_id=n&id=n     → deletes an unused ingredient (inv_ingredient_delete)
 */
export async function GET(request: Request) {
  return adminRpc(new URL(request.url).searchParams.get('tenant_id'), 'inv_ingredients_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body || typeof body.ingredient !== 'object' || body.ingredient === null) {
    return NextResponse.json({ error: 'The ingredient is missing' }, { status: 400 });
  }
  return adminRpc(body.tenant_id, 'inv_ingredient_save', { p_ingredient: body.ingredient });
}

export async function DELETE(request: Request) {
  const q = new URL(request.url).searchParams;
  const id = toInt(q.get('id'));
  if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
  return adminRpc(q.get('tenant_id'), 'inv_ingredient_delete', { p_ingredient_id: id });
}
