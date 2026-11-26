'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { adminCall, adminDelete, adminPost } from '@/components/features/admin/adminShared';
import { cn } from '@/lib/utils';
import { ALLERGENS, fmtMoney, Pill, ROLES, selectCls, tdCls, thCls, type Ingredient, type Role } from './recipes-ui';

interface Form { ingredient_id: number | null; ingredient_name: string; ingredient_role: Role; cost_amount: string; cost_unit: 'kg' | 'lb'; allergens: string[]; notes: string; is_active: boolean }
const blank = (name = ''): Form => ({ ingredient_id: null, ingredient_name: name, ingredient_role: 'OTHER', cost_amount: '', cost_unit: 'lb', allergens: [], notes: '', is_active: true });
const formOf = (i: Ingredient): Form => ({
  ingredient_id: i.ingredient_id, ingredient_name: i.ingredient_name, ingredient_role: i.ingredient_role,
  cost_amount: i.cost_amount === null ? '' : String(i.cost_amount), cost_unit: i.cost_unit, allergens: i.allergens, notes: i.notes ?? '', is_active: i.is_active,
});
const allergenLabel = (c: string) => ALLERGENS.find(([k]) => k === c)?.[1] ?? c;

/**
 * The ingredient catalog: list, add, edit, delete (unused only). With `startNew` it opens straight on a new ingredient
 * (from the recipe editor) and reports the saved one through onSaved.
 */
export function IngredientsDialog({ tenantId, open, onOpenChange, canEdit, canDelete, startNew, onSaved }: {
  tenantId: number; open: boolean; onOpenChange: (o: boolean) => void; canEdit: boolean; canDelete: boolean;
  startNew?: string | null; onSaved?: (i: Ingredient) => void;
}) {
  const [rows, setRows] = useState<Ingredient[] | null>(null);
  const [form, setForm] = useState<Form | null>(null);
  const [q, setQ] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    adminCall<Ingredient[]>(`/api/inventory/recipes/ingredients?tenant_id=${tenantId}`).then(setRows).catch((e: Error) => setError(e.message));
  }, [tenantId]);
  useEffect(() => {
    if (!open) return;
    setError(null);
    setForm(startNew !== undefined && startNew !== null ? blank(startNew) : null);
    load();
  }, [open, startNew, load]);

  const shown = useMemo(() => {
    const t = q.trim().toLowerCase();
    return (rows ?? []).filter((r) => !t || r.ingredient_name.toLowerCase().includes(t));
  }, [rows, q]);

  const save = async () => {
    if (!form) return;
    setBusy(true); setError(null);
    try {
      const saved = await adminPost<Ingredient>('/api/inventory/recipes/ingredients', { tenant_id: tenantId, ingredient: form });
      load();
      if (onSaved && startNew !== undefined && startNew !== null) { onSaved(saved); onOpenChange(false); return; }
      setForm(null);
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  };
  const remove = async () => {
    if (!form?.ingredient_id || !window.confirm(`Delete ${form.ingredient_name}? This cannot be undone.`)) return;
    setBusy(true); setError(null);
    try { await adminDelete(`/api/inventory/recipes/ingredients?tenant_id=${tenantId}&id=${form.ingredient_id}`); setForm(null); load(); }
    catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  };
  const used = form?.ingredient_id ? rows?.find((r) => r.ingredient_id === form.ingredient_id)?.recipe_count ?? 0 : 0;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90dvh] max-w-3xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{startNew !== undefined && startNew !== null ? 'New ingredient' : 'Ingredients'}</DialogTitle>
          <DialogDescription>Mark flours and liquids for baker&apos;s percentages and hydration. Prices give recipe costs; allergens roll up into recipes.</DialogDescription>
        </DialogHeader>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}

        {form ? (
          <div className="space-y-3">
            <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_9rem]">
              <div><Label htmlFor="ing-name" className="text-xs">Name *</Label>
                <Input id="ing-name" autoFocus value={form.ingredient_name} disabled={!canEdit} onChange={(e) => setForm({ ...form, ingredient_name: e.target.value })} /></div>
              <div><Label htmlFor="ing-role" className="text-xs">Counts as</Label>
                <select id="ing-role" className={selectCls} value={form.ingredient_role} disabled={!canEdit} onChange={(e) => setForm({ ...form, ingredient_role: e.target.value as Role })}>
                  {ROLES.map((r) => <option key={r.key} value={r.key}>{r.label}</option>)}
                </select></div>
              <div className="grid grid-cols-[minmax(0,1fr)_6rem] gap-2">
                <div><Label htmlFor="ing-cost" className="text-xs">Price</Label>
                  <Input id="ing-cost" type="number" min={0} step="any" className="text-right" placeholder="No price" value={form.cost_amount} disabled={!canEdit}
                    onChange={(e) => setForm({ ...form, cost_amount: e.target.value })} /></div>
                <div><Label htmlFor="ing-per" className="text-xs">Per</Label>
                  <select id="ing-per" className={selectCls} value={form.cost_unit} disabled={!canEdit} onChange={(e) => setForm({ ...form, cost_unit: e.target.value as 'kg' | 'lb' })}>
                    <option value="lb">lb</option><option value="kg">kg</option>
                  </select></div>
              </div>
              <label className="flex items-end gap-2 pb-2 text-sm"><Checkbox checked={form.is_active} disabled={!canEdit} onCheckedChange={(v) => setForm({ ...form, is_active: v === true })} />Active</label>
            </div>
            <div>
              <span className="text-xs font-medium">Contains</span>
              <div className="mt-1 grid grid-cols-2 gap-2 sm:grid-cols-3">
                {ALLERGENS.map(([k, label]) => (
                  <label key={k} className="flex items-center gap-2 text-sm">
                    <Checkbox checked={form.allergens.includes(k)} disabled={!canEdit}
                      onCheckedChange={(v) => setForm({ ...form, allergens: v === true ? [...form.allergens, k] : form.allergens.filter((a) => a !== k) })} />{label}
                  </label>
                ))}
              </div>
            </div>
            <div><Label htmlFor="ing-notes" className="text-xs">Notes (supplier, brand)</Label>
              <Input id="ing-notes" value={form.notes} disabled={!canEdit} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></div>
            <div className="flex flex-wrap items-center gap-2 pt-1">
              {canDelete && form.ingredient_id && (
                <Button variant="ghost" className="text-destructive" disabled={busy || used > 0} title={used > 0 ? `Used in ${used} recipe(s); set it inactive instead` : undefined} onClick={() => void remove()}>
                  Delete ingredient
                </Button>
              )}
              <span className="flex-1" />
              <Button variant="outline" onClick={() => (startNew !== undefined && startNew !== null ? onOpenChange(false) : setForm(null))}>Cancel</Button>
              {canEdit && <Button disabled={busy || !form.ingredient_name.trim()} onClick={() => void save()}>Save ingredient</Button>}
            </div>
          </div>
        ) : (
          <div className="space-y-2">
            <div className="flex gap-2">
              <Input type="search" placeholder="Search ingredients" aria-label="Search ingredients" value={q} onChange={(e) => setQ(e.target.value)} />
              {canEdit && <Button className="shrink-0 gap-1" onClick={() => setForm(blank(q.trim()))}><Plus className="h-4 w-4" />New</Button>}
            </div>
            <div className="max-h-[55dvh] overflow-auto rounded-md border">
              <table className="w-full text-sm">
                <thead className="sticky top-0"><tr>
                  <th className={thCls}>Ingredient</th><th className={thCls}>Counts as</th><th className={cn(thCls, 'text-right')}>Price</th>
                  <th className={thCls}>Allergens</th><th className={cn(thCls, 'text-right')}>Recipes</th>
                </tr></thead>
                <tbody>
                  {shown.map((r) => (
                    <tr key={r.ingredient_id} className={cn('cursor-pointer hover:bg-muted/40', !r.is_active && 'text-muted-foreground')} onClick={() => setForm(formOf(r))}>
                      <td className={tdCls}><button type="button" className="text-left font-medium">{r.ingredient_name}</button>{!r.is_active && <Pill dot="bg-border" className="ml-2">Inactive</Pill>}</td>
                      <td className={tdCls}>{ROLES.find((x) => x.key === r.ingredient_role)?.label}</td>
                      <td className={cn(tdCls, 'text-right')}>{r.cost_amount === null ? <span className="text-warning">No price</span> : `${fmtMoney(r.cost_amount)} / ${r.cost_unit}`}</td>
                      <td className={cn(tdCls, 'whitespace-normal text-xs')}>{r.allergens.map(allergenLabel).join(', ')}</td>
                      <td className={cn(tdCls, 'text-right')}>{r.recipe_count}</td>
                    </tr>
                  ))}
                  {rows !== null && shown.length === 0 && <tr><td colSpan={5} className={cn(tdCls, 'text-muted-foreground')}>{rows.length === 0 ? 'No ingredients yet. Add flour, water, salt and yeast to start.' : 'No ingredient matches.'}</td></tr>}
                  {rows === null && <tr><td colSpan={5} className={cn(tdCls, 'text-muted-foreground')}>Loading…</td></tr>}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
