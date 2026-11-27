'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import { ArrowLeft, MoreHorizontal, Plus, Search, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { adminCall, adminDelete, adminPost } from '@/components/features/admin/adminShared';
import { CustomerContactsTab } from '@/components/features/account/CustomerContactsTab';
import { Panel } from '@/components/features/inventory/recipes/RecipeFigures';
import { fmtMoney, Pill } from '@/components/features/inventory/recipes/recipes-ui';
import { useNav, useNavGuard } from '@/components/layout/nav-context';
import { useDeepLinkId } from '@/lib/use-deep-link';
import { cn } from '@/lib/utils';
import { DAYS, ItemsTable, VendorItemDialog, type Options, type Vendor, type VendorItem } from './purchasing-ui';

type Filter = 'ACTIVE' | 'INACTIVE' | 'ALL';
const FILTERS: { key: Filter; label: string }[] = [{ key: 'ACTIVE', label: 'Active' }, { key: 'INACTIVE', label: 'Inactive' }, { key: 'ALL', label: 'All' }];
type Tab = 'profile' | 'contacts' | 'items';
const TABS: { key: Tab; label: string }[] = [{ key: 'profile', label: 'Profile' }, { key: 'contacts', label: 'Contacts' }, { key: 'items', label: 'Items' }];
const TAB_TRIGGER =
  '-mb-px rounded-none border-b-2 border-transparent bg-transparent px-4 py-2 text-sm font-medium text-muted-foreground hover:text-foreground ' +
  'data-[state=active]:border-primary data-[state=active]:bg-transparent data-[state=active]:text-foreground data-[state=active]:shadow-none';

interface Form {
  vendor_id: number | null; vendor_code: string; vendor_name: string; account_number: string; payment_terms: string; lead_time_days: string;
  delivery_days: string[]; min_order_amount: string; currency_code: string; website: string; notes: string; is_active: boolean;
}
const s = (v: number | string | null | undefined) => (v === null || v === undefined ? '' : String(v));
const blank: Form = { vendor_id: null, vendor_code: '', vendor_name: '', account_number: '', payment_terms: '', lead_time_days: '', delivery_days: [], min_order_amount: '', currency_code: 'USD', website: '', notes: '', is_active: true };
const formOf = (v: Vendor): Form => ({
  vendor_id: v.vendor_id, vendor_code: v.vendor_code, vendor_name: v.vendor_name, account_number: s(v.account_number), payment_terms: s(v.payment_terms),
  lead_time_days: s(v.lead_time_days), delivery_days: v.delivery_days, min_order_amount: s(v.min_order_amount), currency_code: v.currency_code,
  website: s(v.website), notes: s(v.notes), is_active: v.is_active,
});

/** Purchasing › Vendors (proof of concept): vendor list in the sidebar; Profile, Contacts and Items tabs. */
export function VendorsBook({ tenantId, canEdit, canDelete }: { tenantId: number; canEdit: boolean; canDelete: boolean }) {
  const [rows, setRows] = useState<Vendor[] | null>(null);
  const [filter, setFilter] = useState<Filter>('ACTIVE');
  const [search, setSearch] = useState('');
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [isNew, setIsNew] = useState(false);
  const [form, setForm] = useState<Form>(blank);
  const [saved, setSaved] = useState<Form>(blank);
  const [tab, setTab] = useState<Tab>('profile');
  const [items, setItems] = useState<VendorItem[] | null>(null);
  const [options, setOptions] = useState<Options | null>(null);
  const [dialog, setDialog] = useState<{ open: boolean; item: VendorItem | null }>({ open: false, item: null });
  const [contactsDirty, setContactsDirty] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const { sidebarSlot } = useNav(); // docked sidebar: the vendor list lives there (hidden while the sidebar is closed)

  const dirty = JSON.stringify(form) !== JSON.stringify(saved);
  useNavGuard(dirty || contactsDirty);

  const loadList = useCallback(() => {
    adminCall<Vendor[]>(`/api/purchasing/vendors?tenant_id=${tenantId}`).then(setRows).catch((e: Error) => setError(e.message));
  }, [tenantId]);
  const loadOptions = useCallback(() => {
    adminCall<Options>(`/api/purchasing/items?tenant_id=${tenantId}&options=1`).then(setOptions).catch((e: Error) => setError(e.message));
  }, [tenantId]);
  const loadItems = useCallback((id: number) => {
    setItems(null);
    adminCall<VendorItem[]>(`/api/purchasing/items?tenant_id=${tenantId}&vendor_id=${id}`).then(setItems).catch((e: Error) => setError(e.message));
  }, [tenantId]);
  useEffect(() => { loadList(); loadOptions(); }, [loadList, loadOptions]);

  const leave = () => !(dirty || contactsDirty) || window.confirm('Leave without saving your changes?');
  const open = useCallback((v: Vendor) => {
    const f = formOf(v);
    setSelectedId(v.vendor_id); setIsNew(false); setForm(f); setSaved(f); setNotice(null); setError(null); setContactsDirty(false);
    loadItems(v.vendor_id);
  }, [loadItems]);
  const select = (v: Vendor) => { if (!leave()) return; open(v); };
  useDeepLinkId('vendor', rows !== null, (id) => { const v = rows?.find((r) => r.vendor_id === id); if (v) open(v); });
  const startNew = () => {
    if (!leave()) return;
    setSelectedId(null); setIsNew(true); setForm(blank); setSaved(blank); setTab('profile'); setItems([]); setNotice(null); setError(null);
  };

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    return (rows ?? []).filter((r) => (filter === 'ALL' || (filter === 'ACTIVE') === r.is_active)
      && (!q || `${r.vendor_name} ${r.vendor_code} ${r.account_number ?? ''}`.toLowerCase().includes(q)));
  }, [rows, filter, search]);

  const set = <K extends keyof Form>(k: K, v: Form[K]) => setForm((f) => ({ ...f, [k]: v }));
  const save = async () => {
    setBusy(true); setError(null);
    try {
      const v = await adminPost<Vendor>('/api/purchasing/vendors', { tenant_id: tenantId, vendor: form });
      const f = formOf(v);
      setForm(f); setSaved(f); setSelectedId(v.vendor_id); setIsNew(false); setNotice('Saved.');
      loadList(); loadOptions();
      if (isNew) loadItems(v.vendor_id);
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  };
  const remove = async () => {
    if (!selectedId || !window.confirm(`Delete ${saved.vendor_name} and its contacts? This cannot be undone. A vendor with items can only be set inactive.`)) return;
    setError(null);
    try {
      await adminDelete(`/api/purchasing/vendors?tenant_id=${tenantId}&id=${selectedId}`);
      setSelectedId(null); setForm(blank); setSaved(blank); setNotice('Vendor deleted.'); loadList(); loadOptions();
    } catch (e) { setError((e as Error).message); }
  };

  const showDetail = isNew || selectedId !== null;
  const ro = !canEdit;

  const listPane = (
    <section aria-label="Vendor list" className={cn('flex min-h-0 flex-col',
      sidebarSlot ? 'flex-1 border-t border-border pt-3' : cn('w-full rounded-lg border bg-card shadow-sm lg:w-[17rem] lg:shrink-0 xl:w-[19rem]', showDetail && 'hidden lg:flex'))}>
      <div className={cn('space-y-2', sidebarSlot ? 'px-2 pb-2' : 'border-b p-3')}>
        <div className={cn('flex items-center gap-1', sidebarSlot && 'mb-4')}>
          <h1 className={cn('mr-auto text-lg font-semibold', sidebarSlot && 'sr-only')}>Vendors</h1>
          {canEdit && <Button size="sm" className={cn('gap-1', sidebarSlot && '-order-1')} onClick={startNew}><Plus className="h-4 w-4" />New</Button>}
        </div>
        <div className="flex flex-wrap gap-1" role="group" aria-label="Filter vendors">
          {FILTERS.map((x) => (
            <button key={x.key} type="button" onClick={() => setFilter(x.key)} aria-pressed={filter === x.key}
              className={cn('rounded-full px-2.5 py-0.5 text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                filter === x.key ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:text-foreground')}>
              {x.label}
            </button>
          ))}
        </div>
        <div className="relative">
          <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input type="search" placeholder="Search name, code or account" aria-label="Search vendors" value={search} onChange={(e) => setSearch(e.target.value)} className="pl-8" />
        </div>
      </div>
      <ul className="flex-1 overflow-y-auto">
        {rows === null ? <li className="p-3 text-sm text-muted-foreground">Loading…</li>
          : shown.length === 0 ? <li className="p-3 text-sm text-muted-foreground">{rows.length === 0 ? 'No vendors yet. Add the companies you buy from.' : 'No vendor matches.'}</li>
            : shown.map((r) => (
              <li key={r.vendor_id}>
                <button type="button" onClick={() => select(r)}
                  className={cn('flex w-full items-center gap-2 border-b px-3 py-[4.8px] text-left hover:bg-muted/40 focus-visible:bg-muted/60 focus-visible:outline-none',
                    selectedId === r.vendor_id && 'bg-primary/10 shadow-[inset_3px_0_0_hsl(var(--primary))]')}>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[12.5px] font-medium">{r.vendor_name}</span>
                    <span className="block truncate text-xs text-muted-foreground">{r.vendor_code} · {r.item_count} item{r.item_count === 1 ? '' : 's'}</span>
                  </span>
                  {!r.is_active && <Pill dot="bg-border">Inactive</Pill>}
                </button>
              </li>
            ))}
      </ul>
      <div className="border-t px-3 py-1.5 text-xs text-muted-foreground">{shown.length} of {rows?.length ?? 0} vendors</div>
    </section>
  );

  return (
    <div className="flex min-h-[32rem] gap-3 p-2 sm:p-3 lg:h-[calc(100dvh-7.5rem)]">
      {sidebarSlot ? createPortal(listPane, sidebarSlot) : listPane}

      <main className={cn('min-w-0 flex-1 overflow-y-auto', !showDetail && !sidebarSlot && 'hidden lg:block')}>
        <button type="button" className="mb-2 flex items-center gap-1 text-sm text-primary lg:hidden"
          onClick={() => { if (!leave()) return; setSelectedId(null); setIsNew(false); }}>
          <ArrowLeft className="h-4 w-4" /> Vendors
        </button>
        {error && <p role="alert" className="mb-2 rounded-md border border-destructive/40 px-3 py-2 text-sm text-destructive">{error}</p>}
        {notice && <p role="status" className="mb-2 text-sm text-muted-foreground">{notice}</p>}

        {!showDetail ? (
          <div className="flex h-full min-h-[20rem] items-center justify-center rounded-lg border bg-card text-sm text-muted-foreground">Pick a vendor, or add a new one.</div>
        ) : (
          <div className="space-y-3">
            <section className="flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg border bg-card px-3 py-2.5 shadow-sm">
              <div className="mr-auto min-w-0">
                <h2 className="truncate text-lg font-semibold">{isNew ? 'New vendor' : saved.vendor_name}</h2>
                {!isNew && <p className="text-xs text-muted-foreground">{saved.vendor_code}{saved.account_number ? ` · our account ${saved.account_number}` : ''}{saved.is_active ? '' : ' · Inactive'}</p>}
              </div>
              {!isNew && canDelete && (
                <DropdownMenu>
                  <DropdownMenuTrigger asChild><Button size="sm" variant="outline" aria-label="More actions"><MoreHorizontal className="h-4 w-4" /></Button></DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuItem className="text-destructive" onSelect={() => void remove()}><Trash2 className="mr-2 h-4 w-4" />Delete vendor…</DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              )}
              {tab === 'profile' && canEdit && (
                <>
                  <Button size="sm" variant="outline" disabled={!dirty || busy} onClick={() => setForm(saved)}>Cancel</Button>
                  <Button size="sm" disabled={!dirty || busy || !form.vendor_code.trim() || !form.vendor_name.trim()} onClick={() => void save()}>{busy ? 'Saving…' : 'Save'}</Button>
                </>
              )}
              {tab === 'items' && canEdit && !isNew && (
                <Button size="sm" className="gap-1" onClick={() => setDialog({ open: true, item: null })}><Plus className="h-4 w-4" />Item</Button>
              )}
            </section>

            <Tabs value={tab} onValueChange={(v) => setTab(v as Tab)}>
              <TabsList className="h-auto w-full justify-start gap-1 rounded-none border-b border-border bg-transparent p-0">
                {TABS.map((t) => <TabsTrigger key={t.key} value={t.key} disabled={isNew && t.key !== 'profile'} className={TAB_TRIGGER}>{t.label}</TabsTrigger>)}
              </TabsList>
            </Tabs>

            {tab === 'profile' && (
              <div className="grid items-start gap-3 lg:grid-cols-2">
                <Panel title="Vendor">
                  <div className="grid gap-3 p-3 sm:grid-cols-[9rem_minmax(0,1fr)]">
                    <div><Label htmlFor="v-code" className="text-xs">Code *</Label>
                      <Input id="v-code" value={form.vendor_code} disabled={ro} placeholder="GIUSTO" onChange={(e) => set('vendor_code', e.target.value.toUpperCase())} /></div>
                    <div><Label htmlFor="v-name" className="text-xs">Name *</Label>
                      <Input id="v-name" value={form.vendor_name} disabled={ro} onChange={(e) => set('vendor_name', e.target.value)} /></div>
                    <div className="sm:col-span-2"><Label htmlFor="v-acct" className="text-xs">Our account number with them</Label>
                      <Input id="v-acct" value={form.account_number} disabled={ro} onChange={(e) => set('account_number', e.target.value)} /></div>
                    <div className="sm:col-span-2"><Label htmlFor="v-web" className="text-xs">Website</Label>
                      <Input id="v-web" value={form.website} disabled={ro} placeholder="https://" onChange={(e) => set('website', e.target.value)} /></div>
                    <label className="flex items-center gap-2 text-sm sm:col-span-2"><Checkbox checked={form.is_active} disabled={ro} onCheckedChange={(v) => set('is_active', v === true)} />Active</label>
                  </div>
                </Panel>
                <Panel title="Ordering">
                  <div className="grid gap-3 p-3 sm:grid-cols-2">
                    <div><Label htmlFor="v-terms" className="text-xs">Payment terms</Label>
                      <Input id="v-terms" value={form.payment_terms} disabled={ro} placeholder="Net 30" onChange={(e) => set('payment_terms', e.target.value)} /></div>
                    <div><Label htmlFor="v-lead" className="text-xs">Lead time (days)</Label>
                      <Input id="v-lead" type="number" min={0} max={90} className="text-right" value={form.lead_time_days} disabled={ro} onChange={(e) => set('lead_time_days', e.target.value)} /></div>
                    <div><Label htmlFor="v-min" className="text-xs">Minimum order</Label>
                      <Input id="v-min" type="number" min={0} step="any" className="text-right" value={form.min_order_amount} disabled={ro} placeholder="None" onChange={(e) => set('min_order_amount', e.target.value)} /></div>
                    <div><Label htmlFor="v-cur" className="text-xs">Currency</Label>
                      <Input id="v-cur" value={form.currency_code} maxLength={3} disabled={ro} onChange={(e) => set('currency_code', e.target.value.toUpperCase())} /></div>
                    <div className="sm:col-span-2">
                      <span className="text-xs font-medium">Delivers on</span>
                      <div className="mt-1 flex flex-wrap gap-1" role="group" aria-label="Delivery days">
                        {DAYS.map((d) => {
                          const on = form.delivery_days.includes(d);
                          return (
                            <button key={d} type="button" disabled={ro} aria-pressed={on}
                              onClick={() => set('delivery_days', on ? form.delivery_days.filter((x) => x !== d) : DAYS.filter((x) => x === d || form.delivery_days.includes(x)))}
                              className={cn('h-8 w-11 rounded-md border text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-60',
                                on ? 'border-primary bg-primary text-primary-foreground' : 'border-input bg-background text-muted-foreground hover:text-foreground')}>
                              {d.charAt(0) + d.slice(1).toLowerCase()}
                            </button>
                          );
                        })}
                      </div>
                    </div>
                  </div>
                </Panel>
                <Panel title="Notes" className="lg:col-span-2">
                  <textarea aria-label="Notes" rows={3} value={form.notes} disabled={ro} onChange={(e) => set('notes', e.target.value)}
                    className="w-full resize-y rounded-b-lg bg-transparent px-3 py-2 text-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring" />
                </Panel>
              </div>
            )}

            {tab === 'contacts' && selectedId && (
              <CustomerContactsTab tenantId={tenantId} customerId={selectedId} onDirtyChange={setContactsDirty}
                apiPath="/api/purchasing/vendors/contacts" idParam="vendor_id" emptyText="Save the vendor to add contacts." />
            )}

            {tab === 'items' && (
              <Panel title="What we buy from this vendor" sub={items ? `${items.length} item${items.length === 1 ? '' : 's'}${saved.min_order_amount ? ` · minimum order ${fmtMoney(Number(saved.min_order_amount))}` : ''}` : undefined}>
                {items === null ? <p className="px-3 py-2.5 text-sm text-muted-foreground">Loading…</p>
                  : <ItemsTable items={items} onOpen={(i) => setDialog({ open: true, item: i })} />}
              </Panel>
            )}
          </div>
        )}
      </main>

      <VendorItemDialog tenantId={tenantId} open={dialog.open} item={dialog.item} vendorId={selectedId} options={options}
        canEdit={canEdit} canDelete={canDelete} onClose={() => setDialog({ open: false, item: null })}
        onSaved={() => { if (selectedId) loadItems(selectedId); loadList(); }} />
    </div>
  );
}
