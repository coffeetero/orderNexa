'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { RotateCcw, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { cn } from '@/lib/utils';

// ── Constants ─────────────────────────────────────────────────────────────────

const DOW_OPTIONS = [
  { value: 'MON', label: 'Monday' },
  { value: 'TUE', label: 'Tuesday' },
  { value: 'WED', label: 'Wednesday' },
  { value: 'THU', label: 'Thursday' },
  { value: 'FRI', label: 'Friday' },
  { value: 'SAT', label: 'Saturday' },
  { value: 'SUN', label: 'Sunday' },
];

const CODE_OPTIONS = [
  { value: 'MORNING', label: 'Morning' },
  { value: 'LUNCH',   label: 'Lunch' },
  { value: 'DINNER',  label: 'Dinner' },
];

const LABEL_CLASS = 'text-xs font-semibold text-muted-foreground tracking-wide';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Customer {
  customer_id: number;
  customer_name: string;
  customer_number: string | null;
  customer_type: string | null;
  customer_parent_id: number | null;
  sort_path: string;
}

interface SlimItem {
  item_id: number;
  item_number: string;
  item_name: string;
  is_active: boolean;
}

interface SOLine {
  tempId: string;
  standing_order_id: number | null;
  item_id: number;
  item_number: string;
  item_name: string;
  quantity: number;
}

interface StandingOrderMgtPageProps {
  tenants: { tenant_id: number; tenant_name: string }[];
  initialTenantId: number | null;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

let _tc = 0;
const nextTempId = () => `tmp-${++_tc}`;

// ── Component ─────────────────────────────────────────────────────────────────

export function StandingOrderMgtPage({ tenants, initialTenantId }: StandingOrderMgtPageProps) {
  const tenantId = initialTenantId ?? tenants[0]?.tenant_id ?? null;

  // Data
  const [customers,        setCustomers]        = useState<Customer[]>([]);
  const [items,            setItems]            = useState<SlimItem[]>([]);
  const [isLoadingCustomers, setIsLoadingCustomers] = useState(false);
  const [isLoadingItems,   setIsLoadingItems]   = useState(false);

  // Selectors
  const [selectedCustomer, setSelectedCustomer] = useState<Customer | null>(null);
  const [selectedDow,  setSelectedDow]  = useState<string>('MON');
  const [selectedCode, setSelectedCode] = useState<string>('MORNING');
  // Pills: days to save to — always includes selectedDow
  const [targetDows, setTargetDows] = useState<Set<string>>(new Set(['MON']));

  // Grid lines
  const [lines,      setLines]      = useState<SOLine[]>([]);
  const [savedLines, setSavedLines] = useState<SOLine[]>([]);
  const [isLoading,  setIsLoading]  = useState(false);
  const [isSaving,   setIsSaving]   = useState(false);

  // Entry row
  const [pendingItem, setPendingItem] = useState<SlimItem | null>(null);
  const [pendingQty,  setPendingQty]  = useState<string>('');

  // Refs — direct inputRef pattern (matching Enter Orders)
  const customerInputRef = useRef<HTMLInputElement>(null);
  const itemInputRef     = useRef<HTMLInputElement>(null);
  const qtyInputRef      = useRef<HTMLInputElement>(null);

  const isDirty = JSON.stringify(lines) !== JSON.stringify(savedLines);

  // Focus helpers using requestAnimationFrame (matching Enter Orders)
  const focusItemSearch = useCallback(() => {
    requestAnimationFrame(() => { itemInputRef.current?.focus(); });
  }, []);

  const focusQty = useCallback(() => {
    requestAnimationFrame(() => {
      if (qtyInputRef.current) { qtyInputRef.current.focus(); qtyInputRef.current.select(); }
    });
  }, []);

  // Load data
  useEffect(() => {
    if (!tenantId) return;

    setIsLoadingCustomers(true);
    fetch(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`)
      .then(r => r.json())
      .then((j: { data?: Record<string, unknown>[] }) => {
        setCustomers((j.data ?? []).flatMap(r => {
          const id = Number(r.customer_id);
          return Number.isFinite(id) ? [{
            customer_id:        id,
            customer_name:      String(r.customer_name ?? ''),
            customer_number:    r.customer_number != null ? String(r.customer_number) : null,
            customer_type:      r.customer_type != null ? String(r.customer_type) : null,
            customer_parent_id: r.customer_parent_id != null ? Number(r.customer_parent_id) : null,
            sort_path:          String(r.sort_path ?? ''),
          }] : [];
        }));
      })
      .catch(() => {})
      .finally(() => setIsLoadingCustomers(false));

    setIsLoadingItems(true);
    fetch(`/api/items/profile?tenant_id=${tenantId}`)
      .then(r => r.json())
      .then((j: { data?: SlimItem[] }) => setItems((j.data ?? []).filter(i => i.is_active)))
      .catch(() => {})
      .finally(() => setIsLoadingItems(false));
  }, [tenantId]);

  // Load standing order when selectors change
  const load = useCallback(async (customerId: number, dow: string, code: string) => {
    if (!tenantId) return;
    setIsLoading(true);
    try {
      const res  = await fetch(`/api/standing-orders?tenant_id=${tenantId}&customer_id=${customerId}&production_dow=${dow}&production_code=${code}`);
      const json = await res.json() as { data?: { standing_order_id: number; item_id: number; item_number: string; item_name: string; quantity: number }[]; error?: string };
      if (!res.ok || json.error) { toast.error(json.error ?? 'Could not load.'); return; }
      const loaded: SOLine[] = (json.data ?? []).map(r => ({
        tempId: nextTempId(), standing_order_id: r.standing_order_id,
        item_id: r.item_id, item_number: r.item_number,
        item_name: r.item_name, quantity: r.quantity,
      }));
      setLines(loaded);
      setSavedLines(loaded.map(l => ({ ...l })));
    } finally { setIsLoading(false); }
  }, [tenantId]);

  useEffect(() => {
    if (selectedCustomer && selectedDow && selectedCode) {
      void load(selectedCustomer.customer_id, selectedDow, selectedCode);
    } else {
      setLines([]); setSavedLines([]);
    }
  }, [selectedCustomer, selectedDow, selectedCode, load]);

  // Refresh: discard unsaved changes and reload from current Row 1 selections
  const refresh = useCallback(() => {
    if (!selectedCustomer) return;
    setTargetDows(new Set([selectedDow]));
    void load(selectedCustomer.customer_id, selectedDow, selectedCode);
  }, [selectedCustomer, selectedDow, selectedCode, load]);

  // Save
  const save = async () => {
    if (!selectedCustomer || !tenantId) return;
    setIsSaving(true);
    try {
      const res  = await fetch('/api/standing-orders', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tenant_id: tenantId, customer_id: selectedCustomer.customer_id,
          production_dows: Array.from(targetDows), production_code: selectedCode,
          lines: lines.map(l => ({ item_id: l.item_id, quantity: l.quantity, prep_options: [] })),
        }),
      });
      const json = await res.json() as { error?: string };
      if (!res.ok || json.error) { toast.error(json.error ?? 'Could not save.'); return; }
      toast.success('Standing order saved.');
      await load(selectedCustomer.customer_id, selectedDow, selectedCode);
    } finally { setIsSaving(false); }
  };

  // Commit entry row → update existing line or append
  const commitEntry = useCallback(() => {
    if (!pendingItem) return;
    const qty = parseFloat(pendingQty);
    const safeQty = Number.isFinite(qty) ? qty : 0;
    const existingIdx = lines.findIndex(l => l.item_id === pendingItem.item_id);
    if (existingIdx >= 0) {
      setLines(prev => prev.map((l, i) => i === existingIdx ? { ...l, quantity: safeQty } : l));
    } else {
      setLines(prev => [...prev, {
        tempId: nextTempId(), standing_order_id: null,
        item_id: pendingItem.item_id, item_number: pendingItem.item_number,
        item_name: pendingItem.item_name, quantity: safeQty,
      }]);
    }
    setPendingItem(null);
    setPendingQty('');
    focusItemSearch();
  }, [pendingItem, pendingQty, lines, focusItemSearch]);

  // ── Render ──────────────────────────────────────────────────────────────────

  return (
    <div className="flex flex-col gap-0">

      {/* Row 1: Customer | DOW | Code | Buttons */}
      <div className="flex flex-wrap items-end justify-center gap-2 border-b border-border/60 bg-card px-3 py-2">
        <div className="flex w-[346px] min-w-[346px] max-w-[346px] shrink-0 flex-col gap-1">
          <Label htmlFor="customer-search" className={LABEL_CLASS}>Customer</Label>
          <EntityComboBox<Customer>
            items={customers}
            value={selectedCustomer?.customer_id ?? null}
            onChange={setSelectedCustomer}
            onAfterSelect={() => focusItemSearch()}
            getId={c => c.customer_id}
            getLabel={c => c.customer_number ? `${c.customer_number} - ${c.customer_name}` : c.customer_name}
            getInputLabel={c => c.customer_name}
            getSearchText={c => `${c.customer_number ?? ''} ${c.customer_name}`}
            getParentId={c => c.customer_parent_id}
            getSortKey={c => c.sort_path}
            getItemWeight={(c) => {
              const t = (c.customer_type ?? '').trim().toUpperCase();
              if (t === 'ACCOUNT')    return 'bold';
              if (t === 'SITE')       return 'regular';
              if (t === 'DEPARTMENT') return 'muted';
              return undefined;
            }}
            placeholder="Search number or name…"
            disabled={isLoadingCustomers}
            loading={isLoadingCustomers}
            emptyText="No customers found."
            clearable
            alwaysOpen
            collapseOnSelect
            clearSearchOnFocus
            autoFocus
            inputRef={customerInputRef}
            triggerId="customer-search"
          />
        </div>

        <div className="flex w-36 shrink-0 flex-col gap-1">
          <Label className={LABEL_CLASS}>Production Day</Label>
          <Select value={selectedDow} onValueChange={(v) => { setSelectedDow(v); setTargetDows(new Set([v])); }}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              {DOW_OPTIONS.map(o => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>

        <div className="flex w-32 shrink-0 flex-col gap-1">
          <Label className={LABEL_CLASS}>Production Time</Label>
          <Select value={selectedCode} onValueChange={setSelectedCode}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              {CODE_OPTIONS.map(o => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>

        <div className="flex shrink-0 flex-col gap-1">
          <span className={cn(LABEL_CLASS, 'invisible')}>x</span>
          <Button
            variant="outline" size="icon"
            className="h-9 w-9"
            title="Discard changes and reload"
            disabled={!selectedCustomer}
            onClick={refresh}
          >
            <RotateCcw className="h-4 w-4" />
          </Button>
        </div>

      </div>

      {/* Row 2 + Grid — constrained to content width, centered */}
      <div className="mx-auto w-fit">

      {/* Row 2: Item search + Qty */}
      <div className="flex flex-wrap items-end gap-2 border-b border-border/60 bg-muted/20 px-3 py-2">
        <div className="flex w-[346px] min-w-[346px] max-w-[346px] shrink-0 flex-col gap-1">
          <Label htmlFor="item-search" className={LABEL_CLASS}>Item</Label>
          <EntityComboBox<SlimItem>
            items={items}
            value={pendingItem?.item_id ?? null}
            onChange={(item) => setPendingItem(item)}
            onAfterSelect={(item) => { setPendingItem(item); setPendingQty(''); focusQty(); }}
            getId={i => i.item_id}
            getLabel={i => `${i.item_number} ${i.item_name}`}
            getSearchText={i => `${i.item_number} ${i.item_name}`}
            getParentId={() => null}
            getSortKey={i => i.item_number}
            placeholder={selectedCustomer ? 'Search items…' : 'Select a customer first'}
            disabled={!selectedCustomer || isLoadingItems}
            loading={isLoadingItems}
            emptyText="No items found."
            clearable
            alwaysOpen
            collapseOnSelect
            clearSearchOnFocus
            inputRef={itemInputRef}
            triggerId="item-search"
          />
        </div>

        <div className="flex w-24 shrink-0 flex-col gap-1">
          <Label htmlFor="entry-qty" className={cn(LABEL_CLASS, 'text-center')}>Quantity</Label>
          <input
            id="entry-qty"
            ref={qtyInputRef}
            type="number"
            min={0}
            placeholder="0"
            value={pendingQty}
            disabled={!pendingItem}
            onChange={e => setPendingQty(e.target.value)}
            onFocus={e => e.target.select()}
            onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); commitEntry(); } }}
            className={cn(
              'h-9 w-full rounded-md border border-input bg-background px-2 text-right text-sm font-bold tabular-nums',
              'focus:outline-none focus:ring-2 focus:ring-primary focus:border-primary',
              'disabled:opacity-50 disabled:cursor-not-allowed',
              '[appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none',
            )}
          />
        </div>

        {/* Spacer — same width as Qty */}
        <div className="w-24 shrink-0" />

        {/* Save To fieldset: pills + Save */}
        <fieldset className="flex shrink-0 flex-col justify-between rounded border border-border/60 px-2 pb-1.5 pt-0.5">
          <legend className="px-1 text-center text-xs font-medium text-muted-foreground">Save To</legend>
          <div className="flex items-center gap-1">
            {DOW_OPTIONS.map(o => {
              const isSource   = o.value === selectedDow;
              const isSelected = targetDows.has(o.value);
              return (
                <button
                  key={o.value}
                  type="button"
                  title={isSource ? `${o.label} (production day — always saved)` : o.label}
                  onClick={() => {
                    if (isSource) return;
                    setTargetDows(prev => {
                      const next = new Set(prev);
                      if (next.has(o.value)) next.delete(o.value);
                      else next.add(o.value);
                      return next;
                    });
                  }}
                  className={cn(
                    'h-7 rounded px-1.5 text-xs font-medium transition-colors',
                    isSelected
                      ? isSource
                        ? 'bg-primary text-primary-foreground cursor-default'
                        : 'bg-primary text-primary-foreground'
                      : 'bg-muted text-muted-foreground hover:bg-muted/70',
                  )}
                >
                  {o.label.slice(0, 3)}
                </button>
              );
            })}
            <Button size="sm" onClick={save}
              className="ml-1"
              disabled={isSaving || !isDirty || !selectedCustomer}>
              {isSaving ? 'Saving…' : 'Save'}
            </Button>
          </div>
        </fieldset>
      </div>

      {/* Grid */}
      <div className="flex-1">
        {!selectedCustomer ? (
          <div className="py-16 text-center text-sm text-muted-foreground">
            Select a customer to manage their standing order.
          </div>
        ) : (
          <>
            <div className="grid border-b border-border/60 bg-muted/40 px-3 py-2 text-xs font-semibold text-muted-foreground"
              style={{ gridTemplateColumns: '110px 1fr 80px 36px' }}>
              <span>Item No</span>
              <span>Item Description</span>
              <span className="text-right">Qty</span>
              <span />
            </div>

            {isLoading && <p className="px-3 py-4 text-sm text-muted-foreground">Loading…</p>}
            {!isLoading && lines.length === 0 && (
              <p className="px-3 py-4 text-sm text-muted-foreground">
                No standing order yet — search an item above to add lines.
              </p>
            )}

            {lines.map(line => (
              <div key={line.tempId}
                className="grid items-center border-b border-border/40 px-3 py-1.5 hover:bg-muted/20 transition-colors"
                style={{ gridTemplateColumns: '110px 1fr 80px 36px' }}>
                <span className="font-mono text-xs text-muted-foreground">{line.item_number}</span>
                <span className="truncate pr-2 text-sm">{line.item_name}</span>
                <input
                  type="number" min={0}
                  value={line.quantity === 0 ? '' : line.quantity}
                  placeholder="0"
                  onChange={e => setLines(prev => prev.map(l => l.tempId === line.tempId ? { ...l, quantity: e.target.value === '' ? 0 : Number(e.target.value) } : l))}
                  onFocus={e => e.target.select()}
                  onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); focusItemSearch(); } }}
                  className={cn(
                    'w-full rounded border border-transparent bg-transparent px-1 py-0.5 text-right text-sm tabular-nums font-medium',
                    'focus:border-primary focus:bg-background focus:outline-none hover:border-border',
                    '[appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none',
                  )}
                />
                <button type="button"
                  onClick={() => setLines(prev => prev.filter(l => l.tempId !== line.tempId))}
                  className="flex items-center justify-center rounded p-1 text-muted-foreground/40 hover:text-destructive transition-colors">
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              </div>
            ))}
          </>
        )}
      </div>

      </div> {/* end w-fit wrapper */}
    </div>
  );
}
