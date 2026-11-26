'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import { Plus, Search } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { adminCall } from '@/components/features/admin/adminShared';
import { Panel } from '@/components/features/inventory/recipes/RecipeFigures';
import { selectCls } from '@/components/features/inventory/recipes/recipes-ui';
import { useNav } from '@/components/layout/nav-context';
import { cn } from '@/lib/utils';
import { ItemsTable, KINDS, VendorItemDialog, type ItemKind, type Options, type VendorItem } from './purchasing-ui';

/**
 * Purchasing › Vendor Items (proof of concept): everything we buy, from every vendor, with pack price and cost per unit.
 * Filters sit in the sidebar; pick an ingredient to compare its vendors.
 */
export function VendorItemsList({ tenantId, canEdit, canDelete }: { tenantId: number; canEdit: boolean; canDelete: boolean }) {
  const [rows, setRows] = useState<VendorItem[] | null>(null);
  const [options, setOptions] = useState<Options | null>(null);
  const [vendor, setVendor] = useState('');
  const [ingredient, setIngredient] = useState('');
  const [kind, setKind] = useState<'' | ItemKind>('');
  const [inactive, setInactive] = useState(false);
  const [search, setSearch] = useState('');
  const [dialog, setDialog] = useState<{ open: boolean; item: VendorItem | null }>({ open: false, item: null });
  const [error, setError] = useState<string | null>(null);
  const { sidebarSlot } = useNav();

  const load = useCallback(() => {
    adminCall<VendorItem[]>(`/api/purchasing/items?tenant_id=${tenantId}`).then(setRows).catch((e: Error) => setError(e.message));
    adminCall<Options>(`/api/purchasing/items?tenant_id=${tenantId}&options=1`).then(setOptions).catch((e: Error) => setError(e.message));
  }, [tenantId]);
  useEffect(() => { load(); }, [load]);

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    return (rows ?? []).filter((r) => (inactive || (r.is_active && r.vendor_active))
      && (!vendor || String(r.vendor_id) === vendor) && (!ingredient || String(r.ingredient_id) === ingredient) && (!kind || r.item_kind === kind)
      && (!q || `${r.description} ${r.vendor_sku ?? ''} ${r.vendor_name} ${r.ingredient_name ?? ''}`.toLowerCase().includes(q)));
  }, [rows, vendor, ingredient, kind, inactive, search]);

  const filters = (
    <section aria-label="Vendor item filters" className={cn('space-y-2', sidebarSlot ? 'border-t border-border px-2 pt-3' : 'rounded-lg border bg-card p-3 shadow-sm')}>
      {canEdit && <div className={cn(sidebarSlot && 'mb-4')}><Button size="sm" className="gap-1" onClick={() => setDialog({ open: true, item: null })}><Plus className="h-4 w-4" />New</Button></div>}
      <div><Label htmlFor="vf-vendor" className="text-xs">Vendor</Label>
        <select id="vf-vendor" className={selectCls} value={vendor} onChange={(e) => setVendor(e.target.value)}>
          <option value="">All vendors</option>
          {(options?.vendors ?? []).map((v) => <option key={v.vendor_id} value={v.vendor_id}>{v.vendor_name}</option>)}
        </select></div>
      <div><Label htmlFor="vf-ing" className="text-xs">Ingredient (compare vendors)</Label>
        <select id="vf-ing" className={selectCls} value={ingredient} onChange={(e) => setIngredient(e.target.value)}>
          <option value="">All</option>
          {(options?.ingredients ?? []).map((g) => <option key={g.ingredient_id} value={g.ingredient_id}>{g.ingredient_name}</option>)}
        </select></div>
      <div className="flex flex-wrap gap-1" role="group" aria-label="Kind">
        {[{ key: '' as const, label: 'All' }, ...KINDS].map((k) => (
          <button key={k.key || 'all'} type="button" onClick={() => setKind(k.key)} aria-pressed={kind === k.key}
            className={cn('rounded-full px-2.5 py-0.5 text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
              kind === k.key ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:text-foreground')}>
            {k.label}
          </button>
        ))}
      </div>
      <label className="flex items-center gap-2 text-sm"><Checkbox checked={inactive} onCheckedChange={(v) => setInactive(v === true)} />Include inactive</label>
      <div className="relative">
        <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
        <Input type="search" placeholder="Search item, SKU or vendor" aria-label="Search vendor items" value={search} onChange={(e) => setSearch(e.target.value)} className="pl-8" />
      </div>
    </section>
  );

  return (
    <div className="space-y-3 p-2 sm:p-3">
      {sidebarSlot ? createPortal(filters, sidebarSlot) : filters}
      {error && <p role="alert" className="rounded-md border border-destructive/40 px-3 py-2 text-sm text-destructive">{error}</p>}
      <Panel title="Vendor Items" sub={rows ? `${shown.length} of ${rows.length}` : undefined}>
        {rows === null ? <p className="px-3 py-2.5 text-sm text-muted-foreground">Loading…</p>
          : rows.length === 0 ? <p className="px-3 py-2.5 text-sm text-muted-foreground">Nothing yet. Add vendors first, then what you buy from each.</p>
            : <ItemsTable items={shown} showVendor onOpen={(i) => setDialog({ open: true, item: i })} />}
      </Panel>
      <VendorItemDialog tenantId={tenantId} open={dialog.open} item={dialog.item} vendorId={vendor ? Number(vendor) : null} options={options}
        canEdit={canEdit} canDelete={canDelete} onClose={() => setDialog({ open: false, item: null })} onSaved={load} />
    </div>
  );
}
