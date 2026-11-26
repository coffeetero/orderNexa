'use client';

import { Fragment, useCallback, useEffect, useRef, useState, useMemo } from 'react';
import { createPortal } from 'react-dom';
import { Plus, ChevronDown, PanelLeftClose, PanelLeftOpen } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from '@/components/ui/alert-dialog';
import { cn } from '@/lib/utils';
import { ItemPricebooksTab, type ItemPricebooksTabHandle } from './ItemPricebooksTab';
import { ItemNotesTab } from './ItemNotesTab';
import { ItemComponentsTab, type ItemComponentsTabHandle } from './ItemComponentsTab';
import type { PrepOption } from '@/lib/types';
import { useCurrentRecord, useNav, useNavGuard } from '@/components/layout/nav-context';
import { useDeepLinkId } from '@/lib/use-deep-link';

interface ItemProfile {
  tenant_id: number;
  item_id: number | null;
  item_number: string;
  item_name: string;
  item_description: string | null;
  category: string | null;
  unit_of_sale: string;
  item_weight: number | null;
  weight_uom: string | null;
  box_qty_per_box: number | null;
  box_capacity_weight: number | null;
  box_capacity_optimal: number | null;
  sales_terms_apply: boolean;
  is_active: boolean;
  is_compound: boolean;
  allowed_prep_options: string[];
  default_prep_options: string[];
  dough_type: string | null;
  shape: string | null;
  packing: string | null;
  machine_setting: string | null;
  sheeter_setting: string | null;
  weight_adjuster: number;
  scale_weight: number;
  scale_qty: number;
}

interface SlimItem {
  item_id: number;
  item_number: string;
  item_name: string;
  is_active: boolean;
  is_compound?: boolean;
  category?: string | null;
  is_priced?: boolean;
  is_stale?: boolean;
}

interface ItemProfilePageProps {
  tenantId?: number;
}

const EMPTY_ITEM: Omit<ItemProfile, 'tenant_id'> = {
  item_id: null,
  item_number: '',
  item_name: '',
  item_description: '',
  category: '',
  unit_of_sale: 'PCS',
  item_weight: null,
  weight_uom: 'LB',
  box_qty_per_box: null,
  box_capacity_weight: null,
  box_capacity_optimal: null,
  sales_terms_apply: true,
  is_active: true,
  is_compound: false,
  allowed_prep_options: [],
  default_prep_options: [],
  dough_type: '',
  shape: '',
  packing: '',
  machine_setting: '',
  sheeter_setting: '',
  weight_adjuster: 0,
  scale_weight: 0,
  scale_qty: 0,
};

function emptyDraft(tenantId: number): ItemProfile {
  return { ...EMPTY_ITEM, tenant_id: tenantId };
}

function normalizePrepCodes(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((v) => String(v).trim().toUpperCase())
    .filter((v) => v.length > 0);
}

function normalizeItem(raw: Record<string, unknown>, tenantId: number): ItemProfile {
  return {
    ...EMPTY_ITEM,
    tenant_id: tenantId,
    item_id: typeof raw.item_id === 'number' ? raw.item_id : Number(raw.item_id),
    item_number: String(raw.item_number ?? ''),
    item_name: String(raw.item_name ?? ''),
    item_description: raw.item_description == null ? '' : String(raw.item_description),
    category: raw.category == null ? '' : String(raw.category),
    unit_of_sale: String(raw.unit_of_sale ?? 'PCS'),
    item_weight: raw.item_weight == null ? null : Number(raw.item_weight),
    weight_uom: raw.weight_uom == null ? 'LB' : String(raw.weight_uom),
    box_qty_per_box: raw.box_qty_per_box == null ? null : Number(raw.box_qty_per_box),
    box_capacity_weight: raw.box_capacity_weight == null ? null : Number(raw.box_capacity_weight),
    box_capacity_optimal: raw.box_capacity_optimal == null ? null : Number(raw.box_capacity_optimal),
    sales_terms_apply: raw.sales_terms_apply !== false,
    is_active: raw.is_active !== false,
    is_compound: raw.is_compound === true,
    allowed_prep_options: normalizePrepCodes(raw.allowed_prep_options),
    default_prep_options: normalizePrepCodes(raw.default_prep_options),
    dough_type: raw.dough_type == null ? '' : String(raw.dough_type),
    shape: raw.shape == null ? '' : String(raw.shape),
    packing: raw.packing == null ? '' : String(raw.packing),
    machine_setting: raw.machine_setting == null ? '' : String(raw.machine_setting),
    sheeter_setting: raw.sheeter_setting == null ? '' : String(raw.sheeter_setting),
    weight_adjuster: raw.weight_adjuster == null ? 0 : Number(raw.weight_adjuster),
    scale_weight: raw.scale_weight == null ? 0 : Number(raw.scale_weight),
    scale_qty: raw.scale_qty == null ? 0 : Number(raw.scale_qty),
  };
}


const TAB_TRIGGER =
  'relative z-0 -mb-px rounded-b-none rounded-t-lg border border-muted bg-muted/70 px-4 py-1.5 data-[state=active]:z-10 data-[state=active]:translate-y-[1px] data-[state=active]:border-border/60 data-[state=active]:border-b-transparent data-[state=active]:bg-card';

function PrepOptionsDropdown({
  idBase,
  allowedOptions,
  selectedOptions,
  onChange,
  disabled = false,
}: {
  idBase: string;
  allowedOptions: PrepOption[];
  selectedOptions: string[];
  onChange: (next: string[]) => void;
  disabled?: boolean;
}) {
  const selectedValues = new Set(selectedOptions);
  const summary = selectedOptions.length > 0
    ? allowedOptions
        .filter((opt) => selectedValues.has(opt.value))
        .map((opt) => opt.label)
        .join(', ')
    : 'None';

  const toggleOption = (optionValue: string, checked: boolean) => {
    if (checked) {
      onChange([...selectedOptions, optionValue]);
    } else {
      onChange(selectedOptions.filter((v) => v !== optionValue));
    }
  };

  return (
    <Popover>
      <PopoverTrigger asChild>
        <button
          type="button"
          disabled={disabled}
          className={cn(
            'flex w-full items-center justify-between gap-2 rounded border border-input bg-background px-3 py-2',
            'text-left text-sm text-foreground shadow-sm transition-colors hover:bg-muted/40',
            'focus:outline-none focus:ring-1 focus:ring-primary',
            disabled && 'cursor-not-allowed opacity-50',
          )}
          title={summary}
        >
          <span className="min-w-0 truncate">{summary}</span>
          <ChevronDown className="h-4 w-4 shrink-0 text-muted-foreground" />
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-64 p-2">
        <div className="space-y-1">
          {allowedOptions.length === 0 ? (
            <div className="px-2 py-1.5 text-sm text-muted-foreground">
              No prep options available
            </div>
          ) : (
            allowedOptions.map((option) => (
              <div
                key={option.value}
                className="flex items-center gap-2 rounded px-2 py-1.5 text-sm hover:bg-muted/50"
              >
                <Checkbox
                  id={`${idBase}-${option.value}`}
                  checked={selectedValues.has(option.value)}
                  onCheckedChange={(checked) => toggleOption(option.value, Boolean(checked))}
                  className="h-4 w-4"
                  aria-label={option.label}
                />
                <label htmlFor={`${idBase}-${option.value}`} className="min-w-0 truncate cursor-pointer">
                  {option.label}
                </label>
              </div>
            ))
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}

export function ItemProfilePage({ tenantId }: ItemProfilePageProps) {
  const [items, setItems] = useState<SlimItem[]>([]);
  const [prepValues, setPrepValues] = useState<PrepOption[]>([]);
  const [categories, setCategories] = useState<PrepOption[]>([]);
  const [doughTypes, setDoughTypes] = useState<PrepOption[]>([]);
  const [shapes, setShapes] = useState<PrepOption[]>([]);
  const [packings, setPackings] = useState<PrepOption[]>([]);
  const [units, setUnits] = useState<PrepOption[]>([]);
  const [selectedItemId, setSelectedItemId] = useState<number | null>(null);
  const [draft, setDraft] = useState<ItemProfile>(() => emptyDraft(tenantId ?? 0));
  const [originalDraft, setOriginalDraft] = useState<ItemProfile>(() => emptyDraft(tenantId ?? 0));
  const [isPricebooksDirty, setIsPricebooksDirty] = useState(false);
  const [isComponentsDirty, setIsComponentsDirty] = useState(false);
  const [tab, setTab] = useState('profile');
  const [confirmUncompound, setConfirmUncompound] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [isDetailLoading, setIsDetailLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [listOpen, setListOpen] = useState(true);
  const [statusFilters, setStatusFilters] = useState<string[]>(['Active']);
  const [onlyCompound, setOnlyCompound] = useState(false);
  const [onlyUnpriced, setOnlyUnpriced] = useState(false);
  const [onlyStale, setOnlyStale] = useState(false);
  const [staleYears, setStaleYears] = useState(2);
  const [categoryFilter, setCategoryFilter] = useState('');
  const [isCreatingNew, setIsCreatingNew] = useState(false);
  const loadedRef = useRef(false);
  const detailAbortRef = useRef<AbortController | null>(null);
  const pricebooksRef = useRef<ItemPricebooksTabHandle>(null);
  const componentsRef = useRef<ItemComponentsTabHandle>(null);

  // Fetches slim list + valueset lookups once on mount (and after save to refresh names).
  const loadItems = useCallback(async () => {
    if (!tenantId) return;
    setIsLoading(true);
    try {
      const response = await fetch(`/api/items/profile?tenant_id=${tenantId}&inactive_only=false`);
      const json = (await response.json()) as {
        data?: SlimItem[];
        prepValues?: PrepOption[];
        categories?: PrepOption[];
        doughTypes?: PrepOption[];
        shapes?: PrepOption[];
        packings?: PrepOption[];
        units?: PrepOption[];
        error?: string;
      };
      if (!response.ok || json.error) {
        toast.error(json.error ?? 'Could not load items.', { duration: Infinity });
        return;
      }
      setItems(Array.isArray(json.data) ? json.data : []);
      setPrepValues(Array.isArray(json.prepValues) ? json.prepValues : []);
      setCategories(Array.isArray(json.categories) ? json.categories : []);
      setDoughTypes(Array.isArray(json.doughTypes) ? json.doughTypes : []);
      setShapes(Array.isArray(json.shapes) ? json.shapes : []);
      setPackings(Array.isArray(json.packings) ? json.packings : []);
      setUnits(Array.isArray(json.units) ? json.units : []);
    } catch {
      toast.error('Could not load items. Reload the page to try again.', { duration: Infinity });
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  // Fetches full detail for a single item. Cancels any in-flight request.
  const loadItemDetail = useCallback(async (itemId: number) => {
    if (!tenantId) return;
    detailAbortRef.current?.abort();
    const controller = new AbortController();
    detailAbortRef.current = controller;
    setIsDetailLoading(true);
    try {
      const response = await fetch(
        `/api/items/profile?tenant_id=${tenantId}&item_id=${itemId}`,
        { signal: controller.signal },
      );
      const json = (await response.json()) as { data?: Record<string, unknown> | null; error?: string };
      if (!response.ok || json.error) {
        toast.error(json.error ?? 'Could not load item detail.', { duration: Infinity });
        return;
      }
      if (json.data && typeof json.data === 'object') {
        const normalized = normalizeItem(json.data, tenantId);
        setDraft(normalized);
        setOriginalDraft(normalized);
        setSelectedItemId(itemId);
      }
    } catch (err) {
      if ((err as Error).name !== 'AbortError') toast.error('Could not load item detail.', { duration: Infinity });
    } finally {
      if (!controller.signal.aborted) setIsDetailLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    if (loadedRef.current) return;
    loadedRef.current = true;
    void loadItems();
    if (tenantId) {
      fetch(`/api/admin/pricing-settings?tenant_id=${tenantId}`)
        .then((r) => r.json() as Promise<{ data?: { pricebook_unused_years: number } }>)
        .then((j) => { if (j.data?.pricebook_unused_years) setStaleYears(j.data.pricebook_unused_years); })
        .catch(() => {});
    }
  }, [loadItems, tenantId]);

  const isFormDisabled = !isCreatingNew && selectedItemId === null && draft.item_id === null;

  // Profile is dirty when creating new, or when the draft differs from what was last loaded/saved.
  const isProfileDirty = useMemo(
    () => isCreatingNew || JSON.stringify(draft) !== JSON.stringify(originalDraft),
    [draft, originalDraft, isCreatingNew],
  );
  const isAnythingDirty = isProfileDirty || isPricebooksDirty || isComponentsDirty;

  // The Components tab only exists for compound items; leave it if the flag is turned off.
  useEffect(() => { if (tab === 'components' && !draft.is_compound) setTab('profile'); }, [tab, draft.is_compound]);

  // Sidebar / breadcrumb integration: the open item, unsaved-changes guard, and ?item=ID deep links.
  const navLabel = [originalDraft.item_number, originalDraft.item_name].filter(Boolean).join(' · ');
  useCurrentRecord(
    selectedItemId !== null && originalDraft.item_id === selectedItemId && navLabel
      ? { type: 'item', key: String(selectedItemId), label: navLabel }
      : null,
  );
  useNavGuard(isAnythingDirty);
  const { sidebarSlot } = useNav(); // docked sidebar: the item list lives there (hidden while the sidebar is closed)
  useDeepLinkId('item', items.length > 0, (id) => {
    setIsCreatingNew(false);
    void loadItemDetail(id);
  });

  const set = <K extends keyof ItemProfile>(field: K, value: ItemProfile[K]) =>
    setDraft((prev) => ({ ...prev, [field]: value }));

  const resetAll = useCallback(() => {
    setDraft(originalDraft);
    setIsCreatingNew(false);
    pricebooksRef.current?.reset();
    componentsRef.current?.reset();
  }, [originalDraft]);

  const selectItem = (item: SlimItem | null) => {
    if (!item) {
      const empty = emptyDraft(tenantId ?? 0);
      setSelectedItemId(null);
      setDraft(empty);
      setOriginalDraft(empty);
      setIsCreatingNew(false);
      return;
    }
    void loadItemDetail(item.item_id);
    setIsCreatingNew(false);
  };

  const startNewItem = () => {
    detailAbortRef.current?.abort();
    const empty = emptyDraft(tenantId ?? 0);
    setSelectedItemId(null);
    setDraft(empty);
    setOriginalDraft(empty);
    setIsCreatingNew(true);
  };

  // Every filter except Category, so the Category list only offers categories that still have items.
  const matchesFilters = useCallback((it: SlimItem) => {
    const t = searchQuery.trim().toLowerCase();
    return statusFilters.includes(it.is_active ? 'Active' : 'Inactive') &&
      (!onlyCompound || it.is_compound) && (!onlyUnpriced || it.is_priced === false) && (!onlyStale || it.is_stale) &&
      (!t || `${it.item_number} ${it.item_name}`.toLowerCase().includes(t));
  }, [statusFilters, onlyCompound, onlyUnpriced, onlyStale, searchQuery]);

  const visibleItems = useMemo(() => {
    return items.filter((it) => it.item_id === selectedItemId || (matchesFilters(it) && (!categoryFilter || it.category === categoryFilter)))
      .map((it) => ({ it, group: categories.find((c) => c.value === it.category)?.label ?? it.category ?? 'No category' }))
      .sort((a, b) => (a.group === b.group ? a.it.item_number.localeCompare(b.it.item_number, undefined, { numeric: true })
        : a.group === 'No category' ? 1 : b.group === 'No category' ? -1 : a.group.localeCompare(b.group)));
  }, [categories, items, selectedItemId, matchesFilters, categoryFilter]);

  const usedCategories = useMemo(() => new Set(items.filter(matchesFilters).map((it) => it.category)), [items, matchesFilters]);
  useEffect(() => { if (categoryFilter && !usedCategories.has(categoryFilter)) setCategoryFilter(''); }, [categoryFilter, usedCategories]);

  // Changing a filter closes the open item, unless it has unsaved changes.
  const filterChanged = () => { if (!isAnythingDirty) selectItem(null); };

  const saveAll = async () => {
    if (!tenantId) return;
    setIsSaving(true);
    try {
      // A saved compound item must keep at least one component (a brand-new one gets its components after its first save).
      if (draft.is_compound && selectedItemId !== null && (componentsRef.current?.count() ?? 0) === 0) {
        toast.error('A compound item needs at least one component. Add components on the Components tab, or turn Compound item off.');
        setTab('components');
        return;
      }

      // ── 0. Turning Compound off: the components must go first ─────────
      if (!draft.is_compound && isComponentsDirty) {
        const ok = await componentsRef.current?.save();
        if (!ok) return;
      }

      // ── 1. Save profile (if dirty or creating) ────────────────────────
      let savedId: number | null | undefined = draft.item_id;
      if (isProfileDirty) {
        const response = await fetch('/api/items/profile', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ...draft, tenant_id: tenantId }),
        });
        const json = (await response.json()) as { data?: { item_id?: number }; error?: string };
        if (!response.ok || json.error) {
          toast.error(json.error ?? 'Could not save item.', { duration: Infinity });
          return;
        }
        savedId = json.data?.item_id ?? draft.item_id;
        setIsCreatingNew(false);
        await loadItems();
        if (savedId) await loadItemDetail(savedId);
      }

      // ── 2. Save pricebooks (if dirty) ─────────────────────────────────
      if (isPricebooksDirty) {
        const ok = await pricebooksRef.current?.save();
        if (!ok) {
          // Error already toasted by the tab; profile may have saved — inform user.
          if (isProfileDirty) toast.error('Profile saved, but prices could not be saved.', { duration: Infinity });
          return;
        }
      }

      // ── 3. Save components (if dirty) ─────────────────────────────────
      if (isComponentsDirty && draft.is_compound) {
        const ok = await componentsRef.current?.save();
        if (!ok) {
          if (isProfileDirty) toast.error('Profile saved, but components could not be saved.', { duration: Infinity });
          return;
        }
      }

      if (draft.is_compound && selectedItemId === null) {
        setTab('components');
        toast.success('Saved. Add its components on this tab.');
      } else {
        toast.success('Saved.');
      }
    } finally {
      setIsSaving(false);
    }
  };

  if (!tenantId) {
    return <div className="p-4 text-sm text-muted-foreground">Company context is unavailable.</div>;
  }

  const formTitle = draft.item_number || draft.item_name
    ? `${draft.item_number || 'New'} — ${draft.item_name || 'Item'}`
    : 'Item Form';

  const selectedLabel = selectedItemId ? formTitle : 'No item selected';

  return (
    <div className="space-y-6">
      <div className="flex min-h-0 flex-1 flex-col gap-4">

        <div className={cn('grid items-start gap-4', listOpen && !sidebarSlot && 'lg:grid-cols-[18rem_1fr]')}>

        {/* ── Item list (in the docked sidebar when there is one) ───────── */}
        {sidebarSlot
          ? createPortal(<section aria-label="Item list" className="flex min-h-0 flex-1 flex-col border-t border-border pt-3">
            <div className={cn('space-y-2', sidebarSlot ? 'px-2 pb-2' : 'border-b p-3')}>
              {/* In the sidebar the breadcrumb already names the page, so only New sits on top. */}
              <div className={cn('flex items-center justify-between gap-2', sidebarSlot ? 'mb-4' : '-mx-3 border-b px-3 pb-3')}>
                <h1 className={cn('text-xl font-semibold', sidebarSlot && 'sr-only')}>Items</h1>
                <Button type="button" size="sm" className={cn('gap-1', sidebarSlot && '-order-1')} onClick={startNewItem} disabled={isLoading || isDetailLoading}><Plus className="h-4 w-4" />New</Button>
              </div>
              <div className="grid grid-cols-2 gap-x-4 gap-y-1">
                {(['Active', 'Inactive'] as const).map((f) => (
                  <label key={f} className="flex items-center gap-1.5 text-sm">
                    <Checkbox checked={statusFilters.includes(f)} onCheckedChange={(v) => { setStatusFilters((cur) => (v === true ? [...cur, f] : cur.filter((x) => x !== f))); filterChanged(); }} />
                    {f}
                  </label>
                ))}
                <label className="flex items-center gap-1.5 text-sm"><Checkbox checked={onlyCompound} onCheckedChange={(v) => { setOnlyCompound(v === true); filterChanged(); }} />Compound</label>
                <label className="flex items-center gap-1.5 text-sm"><Checkbox checked={onlyUnpriced} onCheckedChange={(v) => { setOnlyUnpriced(v === true); filterChanged(); }} />Unpriced</label>
                <label className="col-span-2 flex items-center gap-1.5 text-sm"><Checkbox checked={onlyStale} onCheckedChange={(v) => { setOnlyStale(v === true); filterChanged(); }} />Stale ({staleYears} {staleYears === 1 ? 'Year' : 'Years'})</label>
              </div>
              <select aria-label="Category" className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm" value={categoryFilter} onChange={(e) => { setCategoryFilter(e.target.value); filterChanged(); }}>
                <option value="">Include All</option>
                {categories.filter((c) => usedCategories.has(c.value)).map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
              </select>
              <div className={sidebarSlot ? undefined : 'pt-[30px]'}><Input value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} placeholder="Search number or name" aria-label="Search items" /></div>
            </div>
            <ul className={cn('divide-y overflow-y-auto', sidebarSlot ? 'min-h-0 flex-1 border-t' : 'max-h-[70vh]')}>
              {visibleItems.map(({ it, group }, idx) => (
                <Fragment key={it.item_id}>
                  {(idx === 0 || visibleItems[idx - 1].group !== group) && (
                    <li className="sticky top-0 z-[1] border-l-4 border-primary bg-muted px-3 py-1.5 text-xs font-bold uppercase tracking-wide text-primary">{group}</li>
                  )}
                  <li>
                    <button type="button" onClick={() => selectItem(it)}
                      className={cn('w-full px-3 py-1.5 text-left text-sm hover:bg-muted', !it.is_active && 'bg-muted/60 text-muted-foreground', selectedItemId === it.item_id && 'bg-accent')}>
                      <div className="truncate font-medium">{it.item_number} {it.item_name}</div>
                      {(it.is_compound || !it.is_active) && (
                        <div className="truncate text-xs text-muted-foreground">{[it.is_compound && 'Compound', !it.is_active && 'Inactive'].filter(Boolean).join(' · ')}</div>
                      )}
                    </button>
                  </li>
                </Fragment>
              ))}
              {visibleItems.length === 0 && <li className="px-3 py-4 text-sm text-muted-foreground">{isLoading ? 'Loading…' : 'No items.'}</li>}
            </ul>
            <div className="border-t px-3 py-1 text-xs text-muted-foreground">{visibleItems.length} of {items.length}</div>
            </section>, sidebarSlot)
          : listOpen && (
          <Card><CardContent className="space-y-2 p-0">
            <div className={cn('space-y-2', sidebarSlot ? 'px-2 pb-2' : 'border-b p-3')}>
              {/* In the sidebar the breadcrumb already names the page, so only New sits on top. */}
              <div className={cn('flex items-center justify-between gap-2', sidebarSlot ? 'mb-4' : '-mx-3 border-b px-3 pb-3')}>
                <h1 className={cn('text-xl font-semibold', sidebarSlot && 'sr-only')}>Items</h1>
                <Button type="button" size="sm" className={cn('gap-1', sidebarSlot && '-order-1')} onClick={startNewItem} disabled={isLoading || isDetailLoading}><Plus className="h-4 w-4" />New</Button>
              </div>
              <div className="grid grid-cols-2 gap-x-4 gap-y-1">
                {(['Active', 'Inactive'] as const).map((f) => (
                  <label key={f} className="flex items-center gap-1.5 text-sm">
                    <Checkbox checked={statusFilters.includes(f)} onCheckedChange={(v) => { setStatusFilters((cur) => (v === true ? [...cur, f] : cur.filter((x) => x !== f))); filterChanged(); }} />
                    {f}
                  </label>
                ))}
                <label className="flex items-center gap-1.5 text-sm"><Checkbox checked={onlyCompound} onCheckedChange={(v) => { setOnlyCompound(v === true); filterChanged(); }} />Compound</label>
                <label className="flex items-center gap-1.5 text-sm"><Checkbox checked={onlyUnpriced} onCheckedChange={(v) => { setOnlyUnpriced(v === true); filterChanged(); }} />Unpriced</label>
                <label className="col-span-2 flex items-center gap-1.5 text-sm"><Checkbox checked={onlyStale} onCheckedChange={(v) => { setOnlyStale(v === true); filterChanged(); }} />Stale ({staleYears} {staleYears === 1 ? 'Year' : 'Years'})</label>
              </div>
              <select aria-label="Category" className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm" value={categoryFilter} onChange={(e) => { setCategoryFilter(e.target.value); filterChanged(); }}>
                <option value="">Include All</option>
                {categories.filter((c) => usedCategories.has(c.value)).map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
              </select>
              <div className={sidebarSlot ? undefined : 'pt-[30px]'}><Input value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} placeholder="Search number or name" aria-label="Search items" /></div>
            </div>
            <ul className={cn('divide-y overflow-y-auto', sidebarSlot ? 'min-h-0 flex-1 border-t' : 'max-h-[70vh]')}>
              {visibleItems.map(({ it, group }, idx) => (
                <Fragment key={it.item_id}>
                  {(idx === 0 || visibleItems[idx - 1].group !== group) && (
                    <li className="sticky top-0 z-[1] border-l-4 border-primary bg-muted px-3 py-1.5 text-xs font-bold uppercase tracking-wide text-primary">{group}</li>
                  )}
                  <li>
                    <button type="button" onClick={() => selectItem(it)}
                      className={cn('w-full px-3 py-1.5 text-left text-sm hover:bg-muted', !it.is_active && 'bg-muted/60 text-muted-foreground', selectedItemId === it.item_id && 'bg-accent')}>
                      <div className="truncate font-medium">{it.item_number} {it.item_name}</div>
                      {(it.is_compound || !it.is_active) && (
                        <div className="truncate text-xs text-muted-foreground">{[it.is_compound && 'Compound', !it.is_active && 'Inactive'].filter(Boolean).join(' · ')}</div>
                      )}
                    </button>
                  </li>
                </Fragment>
              ))}
              {visibleItems.length === 0 && <li className="px-3 py-4 text-sm text-muted-foreground">{isLoading ? 'Loading…' : 'No items.'}</li>}
            </ul>
            <div className="border-t px-3 py-1 text-xs text-muted-foreground">{visibleItems.length} of {items.length}</div>
          </CardContent></Card>
        )}

        <div className="flex min-w-0 flex-col gap-4">
        {/* ── Actions ─────────────────────────────────────────────────── */}
        <div className="sticky top-0 z-10 flex items-center justify-between gap-2 bg-background pb-2 pt-1">
          {/* The sidebar toggle shows and hides the list when it is in the sidebar. */}
          {!sidebarSlot && (
            <Button type="button" variant="outline" size="sm" onClick={() => setListOpen((o) => !o)} aria-label={listOpen ? 'Hide item list' : 'Show item list'}>
              {listOpen ? <PanelLeftClose className="h-4 w-4" /> : <PanelLeftOpen className="h-4 w-4" />}
            </Button>
          )}
          <div className="ml-auto flex items-center gap-2">
            {!listOpen && !sidebarSlot && (
              <Button type="button" variant="outline" size="sm" onClick={startNewItem} disabled={isLoading || isDetailLoading}>
                <Plus className="mr-1 h-3.5 w-3.5" />
                Item
              </Button>
            )}
            <Button type="button" variant="outline" size="sm" onClick={resetAll} disabled={isSaving || isDetailLoading || !isAnythingDirty}>
              Cancel
            </Button>
            <Button type="button" size="sm" onClick={saveAll} disabled={isSaving || isDetailLoading || isFormDisabled || !isAnythingDirty}>
              {isSaving ? 'Saving…' : isDetailLoading ? 'Loading…' : 'Save'}
            </Button>
          </div>
        </div>

        {/* ── Tabs ────────────────────────────────────────────────────── */}
        {isFormDisabled ? (
          <Card><CardContent className="flex min-h-[40vh] items-center justify-center p-6 text-center text-sm text-muted-foreground">
            Select an item or create a new one.
          </CardContent></Card>
        ) : (
        <Tabs value={tab} onValueChange={setTab} className="space-y-0">
          <TabsList className="relative z-0 h-auto w-fit justify-start gap-0.5 rounded-none bg-transparent p-0">
            <TabsTrigger value="profile" className={TAB_TRIGGER}>Profile</TabsTrigger>
            <TabsTrigger value="details" className={TAB_TRIGGER}>Details</TabsTrigger>
            <TabsTrigger value="components" disabled={!draft.is_compound} className={TAB_TRIGGER}>Components</TabsTrigger>
            <TabsTrigger value="pricebooks" className={TAB_TRIGGER}>Pricebooks</TabsTrigger>
            <TabsTrigger value="notes" className={TAB_TRIGGER}>Notes</TabsTrigger>
          </TabsList>

          <Card className="rounded-b-lg border border-border/60 border-t-0">
            <CardContent className="pt-4">

              {/* ── Profile Tab ─────────────────────────────────────── */}
              <TabsContent value="profile" className="space-y-9">

                {/* Item Description */}
                <fieldset className="rounded-lg border border-border/60 bg-muted/20 p-4">
                  <legend className="m-0 px-1 text-xs font-semibold text-muted-foreground">Item Description</legend>
                  <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 -mt-2">
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Item Number</Label>
                      <Input disabled={isFormDisabled} value={draft.item_number} onChange={(e) => set('item_number', e.target.value)} placeholder="SKU or item code" />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Item Name</Label>
                      <Input disabled={isFormDisabled} value={draft.item_name} onChange={(e) => set('item_name', e.target.value)} placeholder="Item name" />
                    </div>
                    <div className="flex items-end gap-6 pb-1">
                      <label className="flex items-center gap-2 text-sm cursor-pointer select-none">
                        <Checkbox
                          disabled={isFormDisabled}
                          checked={draft.is_active}
                          onCheckedChange={(v) => set('is_active', v === true)}
                        />
                        Active
                      </label>
                      <label className="flex items-center gap-2 text-sm cursor-pointer select-none">
                        <Checkbox
                          disabled={isFormDisabled}
                          checked={draft.is_compound}
                          onCheckedChange={(v) => {
                            if (v !== true && (componentsRef.current?.count() ?? 0) > 0) { setConfirmUncompound(true); return; }
                            set('is_compound', v === true);
                          }}
                        />
                        Compound item
                      </label>
                    </div>
                  </div>
                </fieldset>

                {/* Classification */}
                <fieldset className="rounded-lg border border-border/60 bg-muted/20 p-4">
                  <legend className="m-0 px-1 text-xs font-semibold text-muted-foreground">Classification</legend>
                  <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 -mt-2">
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Category</Label>
                      <Select disabled={isFormDisabled} value={draft.category || ''} onValueChange={(v) => set('category', v)}>
                        <SelectTrigger><SelectValue placeholder="Select…" /></SelectTrigger>
                        <SelectContent>{categories.map((c) => <SelectItem key={c.value} value={c.value}>{c.label}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Dough Type</Label>
                      <Select disabled={isFormDisabled} value={draft.dough_type || ''} onValueChange={(v) => set('dough_type', v)}>
                        <SelectTrigger><SelectValue placeholder="Select…" /></SelectTrigger>
                        <SelectContent>{doughTypes.map((d) => <SelectItem key={d.value} value={d.value}>{d.label}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Shape</Label>
                      <Select disabled={isFormDisabled} value={draft.shape || ''} onValueChange={(v) => set('shape', v)}>
                        <SelectTrigger><SelectValue placeholder="Select…" /></SelectTrigger>
                        <SelectContent>{shapes.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Unit of Sale</Label>
                      <Select disabled={isFormDisabled} value={draft.unit_of_sale || 'PCS'} onValueChange={(v) => set('unit_of_sale', v)}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>{(units.length ? units : [{ value: 'PCS', label: 'Pcs' }]).map((u) => <SelectItem key={u.value} value={u.value}>{u.label}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                  </div>
                </fieldset>

              </TabsContent>

              {/* ── Details Tab ─────────────────────────────────────── */}
              <TabsContent value="details" className="space-y-9">

                {/* Preparation */}
                <fieldset className="rounded-lg border border-border/60 bg-muted/20 p-4">
                  <legend className="m-0 px-1 text-xs font-semibold text-muted-foreground">Preparation</legend>
                  <div className="grid gap-4 sm:grid-cols-3 -mt-2">
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Allowed Prep Options</Label>
                      <PrepOptionsDropdown
                        idBase="prep-allowed"
                        allowedOptions={prepValues}
                        selectedOptions={draft.allowed_prep_options}
                        onChange={(codes) => {
                          set('allowed_prep_options', codes);
                          const filtered = draft.default_prep_options.filter((code) => codes.includes(code));
                          set('default_prep_options', filtered);
                        }}
                        disabled={isFormDisabled}
                      />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Default Prep Options</Label>
                      <PrepOptionsDropdown
                        idBase="prep-default"
                        allowedOptions={prepValues.filter((opt) => draft.allowed_prep_options.includes(opt.value))}
                        selectedOptions={draft.default_prep_options}
                        onChange={(codes) => set('default_prep_options', codes)}
                        disabled={isFormDisabled}
                      />
                    </div>
                    <div className="flex items-center gap-2 pt-6">
                      <Checkbox id="sales-terms" disabled={isFormDisabled} checked={draft.sales_terms_apply} onCheckedChange={(v) => set('sales_terms_apply', Boolean(v))} />
                      <label htmlFor="sales-terms" className="text-sm cursor-pointer">Eligible for discount</label>
                    </div>
                  </div>
                </fieldset>

                {/* Dimensions */}
                <fieldset className="rounded-lg border border-border/60 bg-muted/20 p-4">
                  <legend className="m-0 px-1 text-xs font-semibold text-muted-foreground">Dimensions</legend>
                  <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5 -mt-2">
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Weight</Label>
                      <Input disabled={isFormDisabled} type="number" value={draft.item_weight ?? ''} onChange={(e) => set('item_weight', e.target.value === '' ? null : Number(e.target.value))} placeholder="0" />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Weight Unit</Label>
                      <Input disabled={isFormDisabled} value={draft.weight_uom ?? ''} onChange={(e) => set('weight_uom', e.target.value)} placeholder="LB" />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Qty / Box</Label>
                      <Input disabled={isFormDisabled} type="number" value={draft.box_qty_per_box ?? ''} onChange={(e) => set('box_qty_per_box', e.target.value === '' ? null : Number(e.target.value))} placeholder="0" />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Box Wt. Cap.</Label>
                      <Input disabled={isFormDisabled} type="number" value={draft.box_capacity_weight ?? ''} onChange={(e) => set('box_capacity_weight', e.target.value === '' ? null : Number(e.target.value))} placeholder="0" />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Box Opt. Cap.</Label>
                      <Input disabled={isFormDisabled} type="number" value={draft.box_capacity_optimal ?? ''} onChange={(e) => set('box_capacity_optimal', e.target.value === '' ? null : Number(e.target.value))} placeholder="0" />
                    </div>
                  </div>
                </fieldset>

                {/* Production */}
                <fieldset className="rounded-lg border border-border/60 bg-muted/20 p-4">
                  <legend className="m-0 px-1 text-xs font-semibold text-muted-foreground">Production</legend>
                  <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 -mt-2">
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Packing</Label>
                      <Select disabled={isFormDisabled} value={draft.packing || ''} onValueChange={(v) => set('packing', v)}>
                        <SelectTrigger><SelectValue placeholder="Select…" /></SelectTrigger>
                        <SelectContent>{packings.map((p) => <SelectItem key={p.value} value={p.value}>{p.label}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Machine Setting</Label>
                      <Input disabled={isFormDisabled} value={draft.machine_setting ?? ''} onChange={(e) => set('machine_setting', e.target.value)} placeholder="Code" />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Sheeter Setting</Label>
                      <Input disabled={isFormDisabled} value={draft.sheeter_setting ?? ''} onChange={(e) => set('sheeter_setting', e.target.value)} placeholder="Code" />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Weight Adjuster</Label>
                      <Input disabled={isFormDisabled} type="number" value={draft.weight_adjuster ?? 0} onChange={(e) => set('weight_adjuster', Number(e.target.value || 0))} placeholder="0" />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Scale Weight</Label>
                      <Input disabled={isFormDisabled} type="number" value={draft.scale_weight ?? 0} onChange={(e) => set('scale_weight', Number(e.target.value || 0))} placeholder="0" />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs font-semibold text-muted-foreground">Scale Quantity</Label>
                      <Input disabled={isFormDisabled} type="number" value={draft.scale_qty ?? 0} onChange={(e) => set('scale_qty', Number(e.target.value || 0))} placeholder="0" />
                    </div>
                  </div>
                </fieldset>

              </TabsContent>

              {/* ── Components Tab ──────────────────────────────────── */}
              <TabsContent value="components" forceMount className="data-[state=inactive]:hidden">
                <ItemComponentsTab
                  ref={componentsRef}
                  tenantId={tenantId}
                  itemId={selectedItemId}
                  candidates={items}
                  disabled={isFormDisabled}
                  onDirtyChange={setIsComponentsDirty}
                />
              </TabsContent>

              {/* ── Pricebooks Tab ──────────────────────────────────── */}
              <TabsContent value="pricebooks" forceMount className="data-[state=inactive]:hidden">
                <ItemPricebooksTab
                  ref={pricebooksRef}
                  tenantId={tenantId}
                  itemId={selectedItemId}
                  onDirtyChange={setIsPricebooksDirty}
                />
              </TabsContent>

              {/* ── Notes Tab ───────────────────────────────────────── */}
              <TabsContent value="notes" forceMount className="data-[state=inactive]:hidden">
                <ItemNotesTab tenantId={tenantId} itemId={selectedItemId} />
              </TabsContent>

            </CardContent>
          </Card>
        </Tabs>
        )}
        </div>

        <AlertDialog open={confirmUncompound} onOpenChange={setConfirmUncompound}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Remove the components first</AlertDialogTitle>
              <AlertDialogDescription>
                This item has {componentsRef.current?.count() ?? 0} component(s). A compound item can&apos;t be turned off while it has components.
                Remove them and turn Compound item off? Nothing is deleted until you Save.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Keep compound</AlertDialogCancel>
              <AlertDialogAction onClick={() => { componentsRef.current?.clear(); set('is_compound', false); }}>Remove components</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
        </div>
      </div>
    </div>
  );
}
