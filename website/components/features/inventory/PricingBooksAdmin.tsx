'use client';

import { Fragment, useCallback, useEffect, useMemo, useState } from 'react';
import { ChevronDown, ChevronRight, Plus, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { adminCall, adminPost, useBanner } from '@/components/features/admin/adminShared';
import { cn } from '@/lib/utils';

interface BookRow {
  pricebook_id: number; pricebook_name: string; description: string | null; is_active: boolean; status: string;
  effective_start_date: string | null; effective_end_date: string | null; created_by_name: string | null; approved_by_name: string | null;
  disabled_at: string | null; disabled_by_name: string | null; is_stale: boolean; last_used_months: number | null; item_count: number; assigned_count: number;
}
interface ItemLine { item_id: number; item_number: string; item_name: string; category: string; price: string; is_active: boolean; removed: boolean }
interface Assignment { customer_id: number; customer_name: string; assignment_type: string; status: string; is_active: boolean; effective_start_date: string; effective_end_date: string | null }
interface CatalogItem { item_id: number; item_number: string; item_name: string; category: string | null }
type ApiItem = { item_id: number; item_number: string; item_name: string; category: string | null; item_price: number | null; is_active: boolean };

const FILTERS = ['Active', 'Unassigned', 'Disabled', 'Stale'] as const;
type BookFilter = (typeof FILTERS)[number];
const matchesFilter = (b: BookRow, f: BookFilter) => (f === 'Active' ? b.is_active : f === 'Disabled' ? !b.is_active : f === 'Unassigned' ? b.assigned_count === 0 : b.is_stale);
const STATUSES = ['Draft', 'Scheduled', 'Approved'];
const NO_CATEGORY = 'No category';
const toLine = (i: ApiItem): ItemLine => ({ item_id: i.item_id, item_number: i.item_number ?? '', item_name: i.item_name, category: i.category ?? NO_CATEGORY, price: i.item_price === null ? '' : String(i.item_price), is_active: i.is_active, removed: false });

const blank = { pricebook_id: null as number | null, pricebook_name: '', description: '', is_active: true, status: 'Draft', effective_start_date: '', effective_end_date: '' };
const snapOf = (f: typeof blank, ls: ItemLine[]) => JSON.stringify({ f, l: ls.map((l) => [l.item_id, l.price, l.is_active, l.removed]) });
const fmtDate = (v: string | null) => (v ? v.slice(0, 10) : '');
const formFrom = (b: BookRow) => ({ pricebook_id: b.pricebook_id, pricebook_name: b.pricebook_name, description: b.description ?? '', is_active: b.is_active, status: b.status, effective_start_date: fmtDate(b.effective_start_date), effective_end_date: fmtDate(b.effective_end_date) });

export function PricingBooksAdmin({ tenantId }: { tenantId: number }) {
  const { notify, banner } = useBanner();
  const [books, setBooks] = useState<BookRow[]>([]);
  const [catalog, setCatalog] = useState<CatalogItem[]>([]);
  const [selectedId, setSelectedId] = useState<number | 'new' | null>(null);
  const [form, setForm] = useState(blank);
  const [lines, setLines] = useState<ItemLine[]>([]);
  const [assignments, setAssignments] = useState<Assignment[]>([]);
  const [q, setQ] = useState('');
  const [filter, setFilter] = useState('');
  const [category, setCategory] = useState('');
  const [busy, setBusy] = useState(false);
  const [filters, setFilters] = useState<BookFilter[]>(['Active']);
  const [staleYears, setStaleYears] = useState(1);
  const [baseline, setBaseline] = useState('');
  const [detailsOpen, setDetailsOpen] = useState(true);
  const [assignedOpen, setAssignedOpen] = useState(true);

  const loadBooks = useCallback(async () => {
    try { setBooks(await adminCall<BookRow[]>(`/api/pricebooks?tenant_id=${tenantId}`)); } catch (e) { notify((e as Error).message, 'error'); }
  }, [tenantId, notify]);

  useEffect(() => {
    void loadBooks();
    adminCall<{ pricebook_unused_years: number }>(`/api/admin/pricing-settings?tenant_id=${tenantId}`).then((d) => setStaleYears(d.pricebook_unused_years)).catch(() => {});
    adminCall<CatalogItem[]>(`/api/items?tenant_id=${tenantId}`).then(setCatalog).catch(() => {});
  }, [tenantId, loadBooks]);

  const open = useCallback(async (id: number | 'new') => {
    setSelectedId(id); setQ(''); setFilter(''); setCategory('');
    if (id === 'new') { setForm(blank); setLines([]); setAssignments([]); setBaseline(snapOf(blank, [])); return; }
    const b = books.find((x) => x.pricebook_id === id);
    if (b) setForm(formFrom(b));
    try {
      const d = await adminCall<{ items: ApiItem[]; assignments: Assignment[] }>(`/api/pricebooks?tenant_id=${tenantId}&pricebook_id=${id}`);
      const ls = d.items.map(toLine);
      setLines(ls);
      setAssignments(d.assignments);
      if (b) setBaseline(snapOf(formFrom(b), ls));
    } catch (e) { notify((e as Error).message, 'error'); }
  }, [books, tenantId, notify]);

  const copyAsNew = () => {
    if (typeof selectedId !== 'number') return;
    setSelectedId('new');
    setForm({ ...form, pricebook_id: null, pricebook_name: `Copy of ${form.pricebook_name}`, status: 'Draft', is_active: false });
    setLines((ls) => ls.filter((l) => !l.removed));
    setAssignments([]);
    setBaseline('');
    setQ(''); setFilter(''); setCategory('');
  };

  const inBook = useMemo(() => new Set(lines.filter((l) => !l.removed).map((l) => l.item_id)), [lines]);
  const matches = useMemo(() => {
    const t = q.trim().toLowerCase();
    if (!t) return [];
    return catalog.filter((c) => !inBook.has(c.item_id) && `${c.item_number} ${c.item_name}`.toLowerCase().includes(t)).slice(0, 8);
  }, [q, catalog, inBook]);
  const shown = useMemo(() => lines
    .filter((l) => !category || l.category === category)
    .filter((l) => !filter.trim() || `${l.item_number} ${l.item_name}`.toLowerCase().includes(filter.trim().toLowerCase()))
    .sort((a, b) => (a.category === b.category ? a.item_number.localeCompare(b.item_number, undefined, { numeric: true }) : a.category === NO_CATEGORY ? 1 : b.category === NO_CATEGORY ? -1 : a.category.localeCompare(b.category))),
  [lines, filter, category]);
  const categories = useMemo(() => Array.from(new Set(lines.map((l) => l.category))).sort((a, b) => (a === NO_CATEGORY ? 1 : b === NO_CATEGORY ? -1 : a.localeCompare(b))), [lines]);
  const visibleBooks = books.filter((b) => b.pricebook_id === selectedId || filters.some((f) => matchesFilter(b, f)));
  const selectedBook = books.find((b) => b.pricebook_id === selectedId);

  const setLine = (id: number, p: Partial<ItemLine>) => setLines((ls) => ls.map((l) => (l.item_id === id ? { ...l, ...p } : l)));
  const addItem = (c: CatalogItem) => {
    setLines((ls) => (ls.some((l) => l.item_id === c.item_id) ? ls.map((l) => (l.item_id === c.item_id ? { ...l, removed: false } : l)) : [...ls, { item_id: c.item_id, item_number: c.item_number, item_name: c.item_name, category: c.category ?? NO_CATEGORY, price: '', is_active: true, removed: false }]));
    setQ('');
  };

  const priceBad = (l: ItemLine) => !l.removed && (l.price.trim() === '' || !Number.isFinite(Number(l.price)) || Number(l.price) < 0);
  const datesBad = !!form.effective_start_date && !!form.effective_end_date && form.effective_end_date < form.effective_start_date;
  const dirty = snapOf(form, lines) !== baseline;
  const invalid = !dirty || !form.pricebook_name.trim() || datesBad || lines.some(priceBad);

  async function save() {
    setBusy(true);
    try {
      const id = await adminPost<number>('/api/pricebooks', { tenant_id: tenantId, pricebook: form });
      const entries = lines.map((l) => (l.removed ? { item_id: l.item_id, remove: true } : { item_id: l.item_id, item_price: Number(l.price), is_active: l.is_active }));
      if (entries.length) await adminPost('/api/pricebooks/items', { tenant_id: tenantId, pricebook_id: id, entries });
      notify(`${form.pricebook_name} saved.`, 'success');
      const list = await adminCall<BookRow[]>(`/api/pricebooks?tenant_id=${tenantId}`);
      setBooks(list);
      const b = list.find((x) => x.pricebook_id === id);
      setSelectedId(id);
      const d = await adminCall<{ items: ApiItem[]; assignments: Assignment[] }>(`/api/pricebooks?tenant_id=${tenantId}&pricebook_id=${id}`);
      const ls = d.items.map(toLine);
      if (b) { setForm(formFrom(b)); setBaseline(snapOf(formFrom(b), ls)); }
      setLines(ls);
      setAssignments(d.assignments);
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }

  return (
    <div className="mx-auto max-w-7xl space-y-4 p-2 sm:p-3">
      <div className="flex items-start justify-between gap-3">
        <p className="max-w-3xl text-sm text-muted-foreground">
          A pricing book is a list of items and prices. Assign books to a customer account on its Pricing tab; they are used in the order shown there, item by item, while active, Approved and within their dates for the delivery date.
        </p>
        <Button size="sm" variant="outline" className="shrink-0" disabled={selectedId === null}
          onClick={() => { const open = !(detailsOpen || assignedOpen); setDetailsOpen(open); setAssignedOpen(open); }}>
          {detailsOpen || assignedOpen ? 'Collapse All' : 'Expand All'}
        </Button>
      </div>
      {banner}

      <div className="grid gap-4 lg:grid-cols-[18rem_1fr]">
        <Card><CardContent className="space-y-2 p-0">
          <div className="space-y-2 border-b p-3">
            <h1 className="text-xl font-semibold">Pricing Books</h1>
            <div className="flex gap-2">
              <Button size="sm" className="gap-1" onClick={() => void open('new')}><Plus className="h-4 w-4" />New</Button>
              <Button size="sm" variant="outline" disabled={typeof selectedId !== 'number'} onClick={copyAsNew}>Copy As New</Button>
            </div>
            <div className="grid grid-cols-2 gap-x-4 gap-y-1">
              {FILTERS.map((f) => (
                <label key={f} className="flex items-center gap-1.5 text-sm">
                  <Checkbox checked={filters.includes(f)} onCheckedChange={(v) => { setFilters((cur) => (v === true ? [...cur, f] : cur.filter((x) => x !== f))); setSelectedId(null); }} />
                  {f === 'Stale' ? `Stale (${staleYears} ${staleYears === 1 ? 'Year' : 'Years'})` : f}
                </label>
              ))}
            </div>
          </div>
          <div className="max-h-[70vh] overflow-y-auto">
          <div className="sticky top-0 z-10 grid grid-cols-[1fr_2.25rem_2.5rem_2.75rem] items-end gap-1 border-b bg-muted px-3 py-1 text-[11px] font-semibold text-muted-foreground">
            <span>Name</span><span className="text-center">Items</span><span className="text-center">Agmts</span><span className="text-center leading-tight">Last<br />Used</span>
          </div>
          <ul className="divide-y">
            {visibleBooks.map((b) => (
              <li key={b.pricebook_id}>
                <button type="button" onClick={() => void open(b.pricebook_id)}
                  className={cn('w-full px-3 py-2 text-left text-sm hover:bg-muted', !b.is_active && 'bg-muted/60 text-muted-foreground', selectedId === b.pricebook_id && 'bg-accent')}>
                  <div className="grid grid-cols-[1fr_2.25rem_2.5rem_2.75rem] items-center gap-1">
                    <span className="truncate font-medium">{b.pricebook_name}</span>
                    <span className="text-center text-xs">{b.item_count}</span>
                    <span className="text-center text-xs">{b.assigned_count}</span>
                    <span className="text-center text-xs">{b.last_used_months === null ? '—' : `${b.last_used_months} mo`}</span>
                  </div>
                </button>
              </li>
            ))}
            {visibleBooks.length === 0 && <li className="px-3 py-4 text-sm text-muted-foreground">No pricing books.</li>}
          </ul>
          </div>
        </CardContent></Card>

        {selectedId === null ? (
          <Card><CardContent className="flex min-h-[40vh] items-center justify-center p-6 text-center text-sm text-muted-foreground">Select a pricing book, or create a new one.</CardContent></Card>
        ) : (
          <div className="space-y-4">
            <Card><CardContent className="space-y-3 pt-6">
              <div className="flex items-start justify-between gap-3">
                <button type="button" className="flex items-center gap-1 text-left" aria-expanded={detailsOpen} onClick={() => setDetailsOpen((o) => !o)}>
                  {detailsOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                  <h2 className="text-lg font-medium">Price Book Details</h2>
                </button>
                <Button size="sm" onClick={save} disabled={busy || invalid}>Save</Button>
              </div>
              {detailsOpen && <div className="grid gap-3 sm:grid-cols-2">
                <div><Label htmlFor="pb-name" className="text-xs">Name</Label><Input id="pb-name" value={form.pricebook_name} onChange={(e) => setForm({ ...form, pricebook_name: e.target.value })} /></div>
                <div><Label htmlFor="pb-status" className="text-xs">Status</Label>
                  <div className="flex items-center gap-4">
                    <select id="pb-status" className="h-9 min-w-0 flex-1 rounded-md border border-input bg-background px-2 text-sm" value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value })}>
                      {STATUSES.map((st) => <option key={st} value={st}>{st}</option>)}
                    </select>
                    <label className="flex items-center gap-2 text-sm"><Checkbox checked={form.is_active} onCheckedChange={(v) => setForm({ ...form, is_active: v === true })} /> Active</label>
                  </div></div>
                <div><Label htmlFor="pb-from" className="text-xs">From</Label><Input id="pb-from" type="date" value={form.effective_start_date} onChange={(e) => setForm({ ...form, effective_start_date: e.target.value })} /></div>
                <div><Label htmlFor="pb-to" className="text-xs">To</Label><Input id="pb-to" type="date" value={form.effective_end_date} onChange={(e) => setForm({ ...form, effective_end_date: e.target.value })} className={cn(datesBad && 'border-destructive')} /></div>
                <div className="sm:col-span-2"><Label htmlFor="pb-desc" className="text-xs">Notes</Label><Input id="pb-desc" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} /></div>
                <div><Label className="text-xs">Created By</Label><div className="flex h-9 items-center text-sm">{selectedBook?.created_by_name ?? '—'}</div></div>
                <div><Label className="text-xs">Approved by</Label><div className="flex h-9 items-center text-sm">{selectedBook?.approved_by_name ?? '—'}</div></div>
                {selectedBook && !selectedBook.is_active && selectedBook.disabled_at && (
                  <div className="text-sm text-muted-foreground">Disabled {fmtDate(selectedBook.disabled_at)}{selectedBook.disabled_by_name ? ` by ${selectedBook.disabled_by_name}` : ''}</div>
                )}
              </div>}
            </CardContent></Card>

            {selectedId !== 'new' && (
              <Card><CardContent className="space-y-3 pt-6">
                <button type="button" className="flex items-center gap-1" aria-expanded={assignedOpen} onClick={() => setAssignedOpen((o) => !o)}>
                  {assignedOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                  <h3 className="text-base font-medium">Assignments ({assignments.length})</h3>
                </button>
                {assignedOpen && <div className="overflow-x-auto rounded-md border">
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
                </div>}
              </CardContent></Card>
            )}

            <Card><CardContent className="space-y-3 pt-6">
              <div className="flex flex-wrap items-center gap-3">
                <h3 className="mr-auto text-base font-medium">Items ({lines.filter((l) => !l.removed).length})</h3>
                <select aria-label="Category" className="h-9 rounded-md border border-input bg-background px-2 text-sm" value={category} onChange={(e) => setCategory(e.target.value)}>
                  <option value="">Include All</option>
                  {categories.map((c) => <option key={c} value={c}>{c}</option>)}
                </select>
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
                    {shown.map((l, idx) => (
                      <Fragment key={l.item_id}>
                        {(idx === 0 || shown[idx - 1].category !== l.category) && (
                          <tr className="border-t bg-muted/30"><td colSpan={4} className="px-3 py-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">{l.category}</td></tr>
                        )}
                        <tr className={cn('border-t', l.removed && 'opacity-40 line-through')}>
                          <td className="px-3 py-1.5">{l.item_number} {l.item_name}</td>
                          <td className="px-3 py-1.5"><Input type="number" min={0} step="0.01" value={l.price} disabled={l.removed} aria-label={`Price for ${l.item_name}`} onChange={(e) => setLine(l.item_id, { price: e.target.value })}
                            className={cn('h-8 text-right', priceBad(l) && 'border-destructive')} /></td>
                          <td className="px-3 py-1.5 text-center"><Checkbox checked={l.is_active} disabled={l.removed} onCheckedChange={(v) => setLine(l.item_id, { is_active: v === true })} aria-label={`${l.item_name} active`} /></td>
                          <td className="px-1"><button type="button" aria-label={l.removed ? `Keep ${l.item_name}` : `Remove ${l.item_name}`} onClick={() => setLine(l.item_id, { removed: !l.removed })} className="rounded p-1 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"><Trash2 className="h-3.5 w-3.5" /></button></td>
                        </tr>
                      </Fragment>
                    ))}
                    {lines.length === 0 && <tr><td colSpan={4} className="px-3 py-4 text-muted-foreground">No items yet. Search above to add one.</td></tr>}
                  </tbody>
                </table>
              </div>
            </CardContent></Card>
          </div>
        )}
      </div>
    </div>
  );
}
