'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { adminCall, adminPost, useBanner } from '@/components/features/admin/adminShared';
import { cn } from '@/lib/utils';

interface BookRow { pricebook_id: number; pricebook_name: string; description: string | null; is_active: boolean; owner_customer_id: number | null; owner_customer_name: string | null; item_count: number; assigned_count: number }
interface ItemLine { item_id: number; item_number: string; item_name: string; price: string; is_active: boolean; removed: boolean }
interface Assignment { customer_id: number; customer_name: string; assignment_type: string; status: string; is_active: boolean; effective_start_date: string; effective_end_date: string | null }
interface CatalogItem { item_id: number; item_number: string; item_name: string }
interface Account { customer_id: number; customer_name: string }

const blank = { pricebook_id: null as number | null, pricebook_name: '', description: '', is_active: true, owner_customer_id: '' };

export function PricingBooksAdmin({ tenantId }: { tenantId: number }) {
  const { notify, banner } = useBanner();
  const [books, setBooks] = useState<BookRow[]>([]);
  const [catalog, setCatalog] = useState<CatalogItem[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [selectedId, setSelectedId] = useState<number | 'new' | null>(null);
  const [form, setForm] = useState(blank);
  const [lines, setLines] = useState<ItemLine[]>([]);
  const [assignments, setAssignments] = useState<Assignment[]>([]);
  const [q, setQ] = useState('');
  const [filter, setFilter] = useState('');
  const [busy, setBusy] = useState(false);

  const loadBooks = useCallback(async () => {
    try { setBooks(await adminCall<BookRow[]>(`/api/pricebooks?tenant_id=${tenantId}`)); } catch (e) { notify((e as Error).message, 'error'); }
  }, [tenantId, notify]);

  useEffect(() => {
    void loadBooks();
    adminCall<CatalogItem[]>(`/api/items?tenant_id=${tenantId}`).then(setCatalog).catch(() => {});
    adminCall<Account[]>(`/api/pricebooks?tenant_id=${tenantId}&accounts=1`).then(setAccounts).catch(() => {});
  }, [tenantId, loadBooks]);

  const open = useCallback(async (id: number | 'new') => {
    setSelectedId(id); setQ(''); setFilter('');
    if (id === 'new') { setForm(blank); setLines([]); setAssignments([]); return; }
    const b = books.find((x) => x.pricebook_id === id);
    if (b) setForm({ pricebook_id: b.pricebook_id, pricebook_name: b.pricebook_name, description: b.description ?? '', is_active: b.is_active, owner_customer_id: b.owner_customer_id ? String(b.owner_customer_id) : '' });
    try {
      const d = await adminCall<{ items: { item_id: number; item_number: string; item_name: string; item_price: number | null; is_active: boolean }[]; assignments: Assignment[] }>(`/api/pricebooks?tenant_id=${tenantId}&pricebook_id=${id}`);
      setLines(d.items.map((i) => ({ item_id: i.item_id, item_number: i.item_number ?? '', item_name: i.item_name, price: i.item_price === null ? '' : String(i.item_price), is_active: i.is_active, removed: false })));
      setAssignments(d.assignments);
    } catch (e) { notify((e as Error).message, 'error'); }
  }, [books, tenantId, notify]);

  const inBook = useMemo(() => new Set(lines.filter((l) => !l.removed).map((l) => l.item_id)), [lines]);
  const matches = useMemo(() => {
    const t = q.trim().toLowerCase();
    if (!t) return [];
    return catalog.filter((c) => !inBook.has(c.item_id) && `${c.item_number} ${c.item_name}`.toLowerCase().includes(t)).slice(0, 8);
  }, [q, catalog, inBook]);
  const shown = lines.filter((l) => !filter.trim() || `${l.item_number} ${l.item_name}`.toLowerCase().includes(filter.trim().toLowerCase()));

  const setLine = (id: number, p: Partial<ItemLine>) => setLines((ls) => ls.map((l) => (l.item_id === id ? { ...l, ...p } : l)));
  const addItem = (c: CatalogItem) => {
    setLines((ls) => (ls.some((l) => l.item_id === c.item_id) ? ls.map((l) => (l.item_id === c.item_id ? { ...l, removed: false } : l)) : [...ls, { item_id: c.item_id, item_number: c.item_number, item_name: c.item_name, price: '', is_active: true, removed: false }]));
    setQ('');
  };

  const priceBad = (l: ItemLine) => !l.removed && (l.price.trim() === '' || !Number.isFinite(Number(l.price)) || Number(l.price) < 0);
  const invalid = !form.pricebook_name.trim() || lines.some(priceBad);

  async function save() {
    setBusy(true);
    try {
      const id = await adminPost<number>('/api/pricebooks', { tenant_id: tenantId, pricebook: { ...form, owner_customer_id: form.owner_customer_id || null } });
      const entries = lines.map((l) => (l.removed ? { item_id: l.item_id, remove: true } : { item_id: l.item_id, item_price: Number(l.price), is_active: l.is_active }));
      if (entries.length) await adminPost('/api/pricebooks/items', { tenant_id: tenantId, pricebook_id: id, entries });
      notify(`${form.pricebook_name} saved.`, 'success');
      const list = await adminCall<BookRow[]>(`/api/pricebooks?tenant_id=${tenantId}`);
      setBooks(list);
      const b = list.find((x) => x.pricebook_id === id);
      setSelectedId(id);
      const d = await adminCall<{ items: { item_id: number; item_number: string; item_name: string; item_price: number | null; is_active: boolean }[]; assignments: Assignment[] }>(`/api/pricebooks?tenant_id=${tenantId}&pricebook_id=${id}`);
      setForm({ pricebook_id: id, pricebook_name: b?.pricebook_name ?? form.pricebook_name, description: b?.description ?? form.description, is_active: b?.is_active ?? form.is_active, owner_customer_id: b?.owner_customer_id ? String(b.owner_customer_id) : '' });
      setLines(d.items.map((i) => ({ item_id: i.item_id, item_number: i.item_number ?? '', item_name: i.item_name, price: i.item_price === null ? '' : String(i.item_price), is_active: i.is_active, removed: false })));
      setAssignments(d.assignments);
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }

  return (
    <div className="mx-auto max-w-7xl space-y-4 p-4 sm:p-6">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Pricing Books</h1>
          <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
            A pricing book is a list of items and prices. Assign books to a customer account on its Pricing tab; they are used in the order shown there, item by item, while active, Approved and within their dates for the delivery date.
          </p>
        </div>
        <Button size="sm" className="gap-1.5" onClick={() => void open('new')}><Plus className="h-4 w-4" />New pricing book</Button>
      </div>
      {banner}

      <div className="grid gap-4 lg:grid-cols-[18rem_1fr]">
        <Card><CardContent className="p-0">
          <ul className="max-h-[70vh] divide-y overflow-y-auto">
            {books.map((b) => (
              <li key={b.pricebook_id}>
                <button type="button" onClick={() => void open(b.pricebook_id)}
                  className={cn('w-full px-3 py-2 text-left text-sm hover:bg-muted', selectedId === b.pricebook_id && 'bg-accent')}>
                  <div className="flex items-center gap-2"><span className="flex-1 truncate font-medium">{b.pricebook_name}</span>{!b.is_active && <span className="text-[10px] uppercase text-muted-foreground">Inactive</span>}</div>
                  <div className="text-xs text-muted-foreground">{b.item_count} items · {b.assigned_count} customer{b.assigned_count === 1 ? '' : 's'}{b.owner_customer_name ? ` · for ${b.owner_customer_name}` : ''}</div>
                </button>
              </li>
            ))}
            {books.length === 0 && <li className="px-3 py-4 text-sm text-muted-foreground">No pricing books yet.</li>}
          </ul>
        </CardContent></Card>

        {selectedId === null ? (
          <Card><CardContent className="p-6 text-sm text-muted-foreground">Select a pricing book, or create a new one.</CardContent></Card>
        ) : (
          <div className="space-y-4">
            <Card><CardContent className="space-y-3 pt-6">
              <div className="flex items-start justify-between gap-3">
                <h2 className="text-lg font-medium">{selectedId === 'new' ? 'New pricing book' : form.pricebook_name}</h2>
                <Button size="sm" onClick={save} disabled={busy || invalid}>Save</Button>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <div><Label htmlFor="pb-name" className="text-xs">Name</Label><Input id="pb-name" value={form.pricebook_name} onChange={(e) => setForm({ ...form, pricebook_name: e.target.value })} /></div>
                <div><Label htmlFor="pb-owner" className="text-xs">Made for customer (optional)</Label>
                  <select id="pb-owner" className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm" value={form.owner_customer_id} onChange={(e) => setForm({ ...form, owner_customer_id: e.target.value })}>
                    <option value="">Not specific to one customer</option>
                    {accounts.map((a) => <option key={a.customer_id} value={a.customer_id}>{a.customer_name}</option>)}
                  </select></div>
                <div className="sm:col-span-2"><Label htmlFor="pb-desc" className="text-xs">Description</Label><Input id="pb-desc" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} /></div>
                <label className="flex items-center gap-2 text-sm"><Checkbox checked={form.is_active} onCheckedChange={(v) => setForm({ ...form, is_active: v === true })} /> Active</label>
              </div>
            </CardContent></Card>

            <Card><CardContent className="space-y-3 pt-6">
              <div className="flex flex-wrap items-center gap-3">
                <h3 className="mr-auto text-base font-medium">Items ({lines.filter((l) => !l.removed).length})</h3>
                {lines.length > 10 && <Input value={filter} onChange={(e) => setFilter(e.target.value)} placeholder="Filter items" aria-label="Filter items" className="w-48" />}
              </div>
              <div className="relative">
                <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Add an item: type a number or name" aria-label="Add an item" />
                {matches.length > 0 && (
                  <ul className="absolute z-10 mt-1 max-h-64 w-full overflow-y-auto rounded-md border bg-popover shadow">
                    {matches.map((c) => (
                      <li key={c.item_id}><button type="button" className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm hover:bg-muted" onClick={() => addItem(c)}><Plus className="h-3.5 w-3.5" />{c.item_number} {c.item_name}</button></li>
                    ))}
                  </ul>
                )}
              </div>
              <div className="overflow-x-auto rounded-md border">
                <table className="w-full text-sm">
                  <thead className="bg-muted/50 text-left text-xs"><tr><th className="px-3 py-2">Item</th><th className="px-3 py-2 w-32 text-right">Price</th><th className="px-3 py-2 text-center">Active</th><th className="w-8" /></tr></thead>
                  <tbody>
                    {shown.map((l) => (
                      <tr key={l.item_id} className={cn('border-t', l.removed && 'opacity-40 line-through')}>
                        <td className="px-3 py-1.5">{l.item_number} {l.item_name}</td>
                        <td className="px-3 py-1.5"><Input type="number" min={0} step="0.01" value={l.price} disabled={l.removed} aria-label={`Price for ${l.item_name}`} onChange={(e) => setLine(l.item_id, { price: e.target.value })}
                          className={cn('h-8 text-right', priceBad(l) && 'border-destructive')} /></td>
                        <td className="px-3 py-1.5 text-center"><Checkbox checked={l.is_active} disabled={l.removed} onCheckedChange={(v) => setLine(l.item_id, { is_active: v === true })} aria-label={`${l.item_name} active`} /></td>
                        <td className="px-1"><button type="button" aria-label={l.removed ? `Keep ${l.item_name}` : `Remove ${l.item_name}`} onClick={() => setLine(l.item_id, { removed: !l.removed })} className="rounded p-1 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"><Trash2 className="h-3.5 w-3.5" /></button></td>
                      </tr>
                    ))}
                    {lines.length === 0 && <tr><td colSpan={4} className="px-3 py-4 text-muted-foreground">No items yet. Search above to add one.</td></tr>}
                  </tbody>
                </table>
              </div>
            </CardContent></Card>

            {selectedId !== 'new' && (
              <Card><CardContent className="space-y-3 pt-6">
                <h3 className="text-base font-medium">Assigned to</h3>
                <div className="overflow-x-auto rounded-md border">
                  <table className="w-full text-sm">
                    <thead className="bg-muted/50 text-left text-xs"><tr><th className="px-3 py-2">Customer</th><th className="px-3 py-2">Type</th><th className="px-3 py-2">Status</th><th className="px-3 py-2">From</th><th className="px-3 py-2">To</th><th className="px-3 py-2 text-center">Active</th></tr></thead>
                    <tbody>
                      {assignments.map((a, i) => (
                        <tr key={i} className="border-t"><td className="px-3 py-1.5">{a.customer_name}</td><td className="px-3 py-1.5">{a.assignment_type}</td><td className="px-3 py-1.5">{a.status}</td>
                          <td className="px-3 py-1.5">{a.effective_start_date}</td><td className="px-3 py-1.5">{a.effective_end_date ?? 'Open'}</td><td className="px-3 py-1.5 text-center">{a.is_active ? 'Yes' : 'No'}</td></tr>
                      ))}
                      {assignments.length === 0 && <tr><td colSpan={6} className="px-3 py-4 text-muted-foreground">Not assigned to any customer. Assign it on a customer&apos;s Pricing tab.</td></tr>}
                    </tbody>
                  </table>
                </div>
              </CardContent></Card>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
