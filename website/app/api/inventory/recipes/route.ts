import { NextResponse } from 'next/server';
import { adminRpc, readBody } from '@/lib/api/admin-rpc';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

/**
 * GET  /api/inventory/recipes?tenant_id=n                    → the recipe list (inv_recipes_get)
 * GET  /api/inventory/recipes?tenant_id=n&id=n               → one recipe with its figures (inv_recipe_get)
 * GET  /api/inventory/recipes?tenant_id=n&options=1          → ingredients, recipes and items to pick from (inv_recipe_options)
 * POST /api/inventory/recipes { tenant_id, recipe, change_note? } → creates or saves a recipe (inv_recipe_save)
 * POST /api/inventory/recipes { tenant_id, preview: recipe, scale? } → figures for a saved or unsaved recipe (inv_recipe_preview)
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  if (q.has('options')) return adminRpc(q.get('tenant_id'), 'inv_recipe_options', {});
  if (q.has('id')) {
    const id = toInt(q.get('id'));
    if (id === null) return NextResponse.json({ error: 'Invalid id' }, { status: 400 });
    return adminRpc(q.get('tenant_id'), 'inv_recipe_get', { p_recipe_id: id });
  }
  return adminRpc(q.get('tenant_id'), 'inv_recipes_get', {});
}

export async function POST(request: Request) {
  const body = await readBody(request);
  if (!body) return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  if ('preview' in body) {
    if (!isObject(body.preview)) return NextResponse.json({ error: 'The recipe is missing' }, { status: 400 });
    return adminRpc(body.tenant_id, 'inv_recipe_preview', { p_recipe: body.preview, p_scale: isObject(body.scale) ? body.scale : {} });
  }
  if (!isObject(body.recipe)) return NextResponse.json({ error: 'The recipe is missing' }, { status: 400 });
  return adminRpc(body.tenant_id, 'inv_recipe_save', {
    p_recipe: body.recipe,
    p_change_note: typeof body.change_note === 'string' ? body.change_note : null,
  });
}
