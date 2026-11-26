'use client';

import { useEffect, useState } from 'react';
import { Star } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { adminCall, adminDelete, adminPost } from '@/components/features/admin/adminShared';
import { fmtMoney, Pill, selectCls, tdCls, thCls } from '@/components/features/inventory/recipes/recipes-ui';
import { cn } from '@/lib/utils';

/** Shared types and pieces of Purchasing › Vendors and Purchasing › Vendor Items (proof of concept). */

export type ItemKind = 'INGREDIENT' | 'PACKAGING' | 'SUPPLY';
export const KINDS: { key: ItemKind; label: string }[] = [
  { key: 'INGREDIENT', label: 'Ingredient' }, { key: 'PACKAGING', label: 'Packaging' }, { key: 'SUPPLY', label: 'Supply' },
];
export const PACK_UNITS = ['lb', 'kg', 'oz', 'g', 'gal', 'l', 'fl_oz', 'ml', 'ea'] as const;
export type PackUnit = (typeof PACK_UNITS)[number];
export const unitLabel = (u: string) => (u === 'fl_oz' ? 'fl oz' : u);
export const DAYS = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'] as const;

export interface Vendor {
  vendor_id: number; vendor_code: string; vendor_name: string; account_number: string | null; payment_terms: string | null;
  lead_time_days: number | null; delivery_days: string[]; min_order_amount: number | null; currency_code: string;
  website: string | null; notes: string | null; is_active: boolean; item_count: number;
}
export interface VendorItem {
  vendor_item_id: number; vendor_id: number; vendor_code: string; vendor_name: string; vendor_active: boolean;
  item_kind: ItemKind; ingredient_id: number | null; ingredient_name: string | null; vendor_sku: string | null; description: string;
  pack_qty: number; pack_unit: PackUnit; pack_label: string | null; pack_price: number | null; price_date: string | null;
  price_date_iso: string | null; min_order_qty: number | null; is_preferred: boolean; notes: string | null; is_active: boolean;
  currency_code: string; cost_per_lb: number | null; cost_per_kg: number | null; cost_per_l: number | null; cost_per_gal: number | null;
  cost_per_ea: number | null; price_changes: number;
}
export interface Options {
  vendors: { vendor_id: number; vendor_code: string; vendor_name: string; is_active: boolean }[];
  ingredients: { ingredient_id: number; ingredient_name: string; is_active: boolean }[];
}
interface PriceRow { effective_date: string; pack_price: number; price_source: string; change: number | null; change_pct: number | null; saved_by_name: string | null }

/** $0.045, $1.1023: money with 2 to 4 decimals, for costs per unit. */
export function fmtUnitCost(v: number | null | undefined): string {
  if (v === null || v === undefined) return '–';
  return `$${Number(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 4 })}`;
}
export function packText(i: Pick<VendorItem, 'pack_qty' | 'pack_unit' | 'pack_label'>): string {
  const q = Number(i.pack_qty).toLocaleString('en-US', { maximumFractionDigits: 4 });
  return `${q} ${unitLabel(i.pack_unit)}${i.pack_label ? ` ${i.pack_label}` : ''}`;
}
/** The cost per unit line the database worked out: per lb and kg, per gal and l, or each. */
export function costText(i: VendorItem): string {
  if (i.cost_per_lb !== null) return `${fmtUnitCost(i.cost_per_lb)}/lb · ${fmtUnitCost(i.cost_per_kg)}/kg`;
  if (i.cost_per_gal !== null) return `${fmtUnitCost(i.cost_per_gal)}/gal · ${fmtUnitCost(i.cost_per_l)}/l`;
  if (i.cost_per_ea !== null) return `${fmtUnitCost(i.cost_per_ea)} each`;
  return '–';
}
export const kindLabel = (k: ItemKind) => KINDS.find((x) => x.key === k)?.label ?? k;

/** Vendor items as a table; showVendor adds the vendor column (Vendor Items screen). Rows open the item. */
export function ItemsTable({ items, showVendor, onOpen }: { items: VendorItem[]; showVendor?: boolean; onOpen: (i: VendorItem) => void }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr>
            {showVendor && <th className={thCls}>Vendor</th>}
            <th className={thCls}>Item</th>
            <th className={thCls}>Vendor SKU</th>
            <th className={thCls}>Kind</th>
            <th className={thCls}>Ingredient</th>
            <th className={thCls}>Pack</th>
            <th className={cn(thCls, 'text-right')}>Pack price</th>
            <th className={cn(thCls, 'text-right')}>Cost per unit</th>
            <th className={thCls}>Price date</th>
          </tr>
        </thead>
        <tbody>
          {items.map((i) => (
            <tr key={i.vendor_item_id} className={cn('cursor-pointer hover:bg-muted/40', !i.is_active && 'text-muted-foreground')} onClick={() => onOpen(i)}>
              {showVendor && <td className={tdCls}>{i.vendor_name}</td>}
              <td className={cn(tdCls, 'whitespace-normal')}>
                <button type="button" className="text-left font-medium">{i.description}</button>
                {i.is_preferred && <Star className="ml-1.5 inline h-3.5 w-3.5 fill-warning text-warning" aria-label="Preferred source" />}
                {!i.is_active && <Pill dot="bg-border" className="ml-2">Inactive</Pill>}
              </td>
              <td className={tdCls}>{i.vendor_sku ?? ''}</td>
              <td className={tdCls}>{kindLabel(i.item_kind)}</td>
              <td className={tdCls}>{i.ingredient_name ?? ''}</td>
              <td className={tdCls}>{packText(i)}</td>
              <td className={cn(tdCls, 'text-right')}>{i.pack_price === null ? <span className="text-warning">No price</span> : fmtMoney(i.pack_price)}</td>
              <td className={cn(tdCls, 'text-right')}>{costText(i)}</td>
              <td className={tdCls}>{i.price_date ?? ''}</td>
            </tr>
          ))}
          {items.length === 0 && <tr><td colSpan={showVendor ? 9 : 8} className={cn(tdCls, 'text-muted-foreground')}>No items.</td></tr>}
        </tbody>
      </table>
    </div>
  );
}

interface Form {
  vendor_item_id: number | null; vendor_id: string; item_kind: ItemKind; ingredient_id: string; vendor_sku: string; description: string;
  pack_qty: string; pack_unit: PackUnit; pack_label: string; pack_price: string; price_date: string; min_order_qty: string;
  is_preferred: boolean; notes: string; is_active: boolean;
}
const s = (v: number | string | null | undefined) => (v === null || v === undefined ? '' : String(v));
const formOf = (i: VendorItem | null, vendorId: number | null): Form => i ? {
  vendor_item_id: i.vendor_item_id, vendor_id: s(i.vendor_id), item_kind: i.item_kind, ingredient_id: s(i.ingredient_id), vendor_sku: s(i.vendor_sku),
  description: i.description, pack_qty: s(i.pack_qty), pack_unit: i.pack_unit, pack_label: s(i.pack_label), pack_price: s(i.pack_price),
  price_date: s(i.price_date_iso), min_order_qty: s(i.min_order_qty), is_preferred: i.is_preferred, notes: s(i.notes), is_active: i.is_active,
} : {
  vendor_item_id: null, vendor_id: s(vendorId), item_kind: 'INGREDIENT', ingredient_id: '', vendor_sku: '', description: '', pack_qty: '',
  pack_unit: 'lb', pack_label: '', pack_price: '', price_date: '', min_order_qty: '', is_preferred: false, notes: '', is_active: true,
};

/**
 * Add or edit a vendor item. A changed price gets today's date unless one is entered; the database keeps every price in
 * the history shown below the form. `item` null = new (for `vendorId` when given).
 */
export function VendorItemDialog({ tenantId, open, item, vendorId, options, canEdit, canDelete, onClose, onSaved }: {
  tenantId: number; open: boolean; item: VendorItem | null; vendorId: number | null; options: Options | null;
  canEdit: boolean; canDelete: boolean; onClose: () => void; onSaved: () => void;
}) {
  const [form, setForm] = useState<Form>(() => formOf(item, vendorId));
  const [prices, setPrices] = useState<PriceRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!open) return;
    setForm(formOf(item, vendorId)); setError(null); setPrices(null);
    if (item) adminCall<PriceRow[]>(`/api/purchasing/items?tenant_id=${tenantId}&prices=${item.vendor_item_id}`).then(setPrices).catch(() => setPrices([]));
  }, [open, item, vendorId, tenantId]);

  const set = <K extends keyof Form>(k: K, v: Form[K]) => setForm((f) => ({ ...f, [k]: v }));
  const save = async () => {
    setBusy(true); setError(null);
    try {
      const body = { ...form, ingredient_id: form.item_kind === 'INGREDIENT' ? form.ingredient_id : '', is_preferred: form.item_kind === 'INGREDIENT' && !!form.ingredient_id && form.is_preferred };
      await adminPost('/api/purchasing/items', { tenant_id: tenantId, item: body });
      onSaved(); onClose();
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  };
  const remove = async () => {
    if (!item || !window.confirm(`Delete ${item.description} and its price history? This cannot be undone. To keep it, untick Active instead.`)) return;
    setBusy(true); setError(null);
    try { await adminDelete(`/api/purchasing/items?tenant_id=${tenantId}&id=${item.vendor_item_id}`); onSaved(); onClose(); }
    catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  };
  const ro = !canEdit;

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent className="max-h-[90dvh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{item ? item.description : 'New vendor item'}</DialogTitle>
          <DialogDescription>What you buy from the vendor: the pack, its price, and the recipe ingredient it supplies.</DialogDescription>
        </DialogHeader>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <div className="grid gap-3 sm:grid-cols-2">
          <div><Label htmlFor="vi-vendor" className="text-xs">Vendor *</Label>
            <select id="vi-vendor" className={selectCls} value={form.vendor_id} disabled={ro} onChange={(e) => set('vendor_id', e.target.value)}>
              <option value="">Pick a vendor</option>
              {(options?.vendors ?? []).filter((v) => v.is_active || String(v.vendor_id) === form.vendor_id).map((v) => <option key={v.vendor_id} value={v.vendor_id}>{v.vendor_name}</option>)}
            </select></div>
          <div><Label htmlFor="vi-sku" className="text-xs">Vendor SKU</Label>
            <Input id="vi-sku" value={form.vendor_sku} disabled={ro} onChange={(e) => set('vendor_sku', e.target.value)} /></div>
          <div className="sm:col-span-2"><Label htmlFor="vi-desc" className="text-xs">Item *</Label>
            <Input id="vi-desc" value={form.description} disabled={ro} placeholder="High Performer bread flour" onChange={(e) => set('description', e.target.value)} /></div>
          <div><Label htmlFor="vi-kind" className="text-xs">Kind</Label>
            <select id="vi-kind" className={selectCls} value={form.item_kind} disabled={ro} onChange={(e) => set('item_kind', e.target.value as ItemKind)}>
              {KINDS.map((k) => <option key={k.key} value={k.key}>{k.label}</option>)}
            </select></div>
          <div><Label htmlFor="vi-ing" className="text-xs">Recipe ingredient</Label>
            <select id="vi-ing" className={selectCls} value={form.ingredient_id} disabled={ro || form.item_kind !== 'INGREDIENT'} onChange={(e) => set('ingredient_id', e.target.value)}>
              <option value="">{form.item_kind === 'INGREDIENT' ? 'None' : 'Ingredients only'}</option>
              {(options?.ingredients ?? []).filter((g) => g.is_active || String(g.ingredient_id) === form.ingredient_id).map((g) => <option key={g.ingredient_id} value={g.ingredient_id}>{g.ingredient_name}</option>)}
            </select></div>
          <div className="grid grid-cols-[minmax(0,1fr)_5.5rem_minmax(0,1fr)] gap-2 sm:col-span-2">
            <div><Label htmlFor="vi-qty" className="text-xs">Pack holds *</Label>
              <Input id="vi-qty" type="number" min={0} step="any" className="text-right" value={form.pack_qty} disabled={ro} placeholder="50" onChange={(e) => set('pack_qty', e.target.value)} /></div>
            <div><Label htmlFor="vi-unit" className="text-xs">Unit</Label>
              <select id="vi-unit" className={selectCls} value={form.pack_unit} disabled={ro} onChange={(e) => set('pack_unit', e.target.value as PackUnit)}>
                {PACK_UNITS.map((u) => <option key={u} value={u}>{unitLabel(u)}</option>)}
              </select></div>
            <div><Label htmlFor="vi-label" className="text-xs">Pack is a</Label>
              <Input id="vi-label" value={form.pack_label} disabled={ro} placeholder="bag, case, pail" onChange={(e) => set('pack_label', e.target.value)} /></div>
          </div>
          <div><Label htmlFor="vi-price" className="text-xs">Pack price</Label>
            <Input id="vi-price" type="number" min={0} step="any" className="text-right" value={form.pack_price} disabled={ro} placeholder="No price" onChange={(e) => set('pack_price', e.target.value)} /></div>
          <div><Label htmlFor="vi-pdate" className="text-xs">Price from</Label>
            <Input id="vi-pdate" type="date" value={form.price_date} disabled={ro} onChange={(e) => set('price_date', e.target.value)} />
            <p className="mt-0.5 text-[11px] text-muted-foreground">Blank: today when the price changes.</p></div>
          <div><Label htmlFor="vi-min" className="text-xs">Minimum order (packs)</Label>
            <Input id="vi-min" type="number" min={0} step="any" className="text-right" value={form.min_order_qty} disabled={ro} onChange={(e) => set('min_order_qty', e.target.value)} /></div>
          <div className="flex flex-col justify-end gap-2 pb-1 text-sm">
            <label className="flex items-center gap-2"><Checkbox checked={form.is_preferred} disabled={ro || form.item_kind !== 'INGREDIENT' || !form.ingredient_id}
              onCheckedChange={(v) => set('is_preferred', v === true)} />Preferred source of this ingredient</label>
            <label className="flex items-center gap-2"><Checkbox checked={form.is_active} disabled={ro} onCheckedChange={(v) => set('is_active', v === true)} />Active</label>
          </div>
          <div className="sm:col-span-2"><Label htmlFor="vi-notes" className="text-xs">Notes</Label>
            <Input id="vi-notes" value={form.notes} disabled={ro} onChange={(e) => set('notes', e.target.value)} /></div>
        </div>

        {item && (
          <section className="rounded-md border">
            <h3 className="border-b px-3 py-1.5 text-sm font-semibold">Price history</h3>
            {prices === null ? <p className="px-3 py-2 text-sm text-muted-foreground">Loading…</p>
              : prices.length === 0 ? <p className="px-3 py-2 text-sm text-muted-foreground">No prices yet.</p> : (
                <table className="w-full text-sm">
                  <thead><tr><th className={thCls}>From</th><th className={cn(thCls, 'text-right')}>Pack price</th><th className={cn(thCls, 'text-right')}>Change</th><th className={thCls}>Source</th><th className={thCls}>By</th></tr></thead>
                  <tbody>
                    {prices.map((p, idx) => (
                      <tr key={idx}>
                        <td className={tdCls}>{p.effective_date}</td>
                        <td className={cn(tdCls, 'text-right')}>{fmtMoney(p.pack_price)}</td>
                        <td className={cn(tdCls, 'text-right', p.change !== null && p.change > 0 && 'text-destructive')}>
                          {p.change === null ? '' : `${p.change > 0 ? '+' : ''}${fmtMoney(p.change)}${p.change_pct !== null ? ` (${p.change_pct > 0 ? '+' : ''}${p.change_pct}%)` : ''}`}
                        </td>
                        <td className={tdCls}>{p.price_source === 'RECEIPT' ? 'Receiving' : 'Entered'}</td>
                        <td className={tdCls}>{p.saved_by_name ?? ''}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
          </section>
        )}

        <DialogFooter className="flex-row items-center sm:justify-between">
          {item && canDelete ? <Button variant="ghost" className="text-destructive" disabled={busy} onClick={() => void remove()}>Delete item</Button> : <span />}
          <div className="flex gap-2">
            <Button variant="outline" onClick={onClose}>{canEdit ? 'Cancel' : 'Close'}</Button>
            {canEdit && <Button disabled={busy || !form.vendor_id || !form.description.trim() || !form.pack_qty} onClick={() => void save()}>Save item</Button>}
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
