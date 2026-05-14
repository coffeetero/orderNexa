'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
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

// ── Types ─────────────────────────────────────────────────────────────────────

interface Customer {
  customer_id: number;
  customer_name: string;
  customer_number: string | null;
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
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [items, setItems]         = useState<SlimItem[]>([]);

  // Selectors
  const [selectedCustomer, setSelectedCustomer] = useState<Customer | null>(null);
  const [selectedDow,  setSelectedDow]  = useState<string>('MON');
  const [selectedCode, setSelectedCode] = useState<string>('MORNING');

  // Grid
  const [lines, setLines]           = useState<SOLine[]>([]);
  const [savedLines, setSavedLines] = useState<SOLine[]>([]);
  const [isLoading, setIsLoading]   = useState(false);
  const [isSaving,  setIsSaving]    = useState(false);

  // Entry row state
  const [pendingItem, setPendingItem] = useState<SlimItem | null>(null);
  const [pendingQty,  setPendingQty]  = useState<string>('');
  const [itemSearchKey, setItemSearchKey] = useState(0); // increment to reset combobox

  // Refs
  const customerWrapRef = useRef<HTMLDivElement>(null);
  const itemWrapRef     = useRef<HTMLDivElement>(null);
  const qtyInputRef     = useRef<HTMLInputElement>(null);
  const qtyGridRefs     = useRef<Map<string, HTMLInputElement>>(new Map());

  const isDirty = JSON.stringify(lines) !== JSON.stringify(savedLines);

  // Focus helpers
  const focusInput = (wrapRef: React.RefObject<HTMLDivElement>) =>
    setTimeout(() => wrapRef.current?.querySelector<HTMLElement>('input')?.focus(), 30);

  const focusCustomerSearch = useCallback(() => focusInput(customerWrapRef), []);
  const focusItemSearch     = useCallback(() => focusInput(itemWrapRef), []);
  const focusQty            = useCallback(() => setTimeout(() => qtyInputRef.current?.focus(), 30), []);

  // Load customers + items on mount
  useEffect(() => {
    if (!tenantId) return;
    fetch(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`)
      .then(r => r.json())
      .then((j: { data?: Record<string, unknown>[] }) => {
        setCustomers((j.data ?? []).flatMap(r => {
          const id = Number(r.customer_id);
          return Number.isFinite(id) ? [{
            customer_id:        id,
            customer_name:      String(r.customer_name ?? ''),
            customer_number:    r.customer_number != null ? String(r.customer_number) : null,
            customer_parent_id: r.customer_parent_id != null ? Number(r.customer_parent_id) : null,
            sort_path:          String(r.sort_path ?? ''),
          }] : [];
        }));
      })
      .catch(() => {});

    fetch(`/api/items/profile?tenant_id=${tenantId}`)
      .then(r => r.json())
      .then((j: { data?: SlimItem[] }) => setItems((j.data ?? []).filter(i => i.is_active)))
      .catch(() => {});
  }, [tenantId]);

  // Focus customer search on page load
  useEffect(() => { focusCustomerSearch(); }, [focusCustomerSearch]);

  // Load standing order lines
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

  // Save
  const save = async () => {
    if (!selectedCustomer || !tenantId) return;
    setIsSaving(true);
    try {
      const res  = await fetch('/api/standing-orders', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tenant_id: tenantId, customer_id: selectedCustomer.customer_id,
          production_dow: selectedDow, production_code: selectedCode,
          lines: lines.map(l => ({ item_id: l.item_id, quantity: l.quantity, prep_options: [] })),
        }),
      });
      const json = await res.json() as { error?: string };
      if (!res.ok || json.error) { toast.error(json.error ?? 'Could not save.'); return; }
      toast.success('Standing order saved.');
      await load(selectedCustomer.customer_id, selectedDow, selectedCode);
    } finally { setIsSaving(false); }
  };

  // Entry row: commit item + qty into the grid
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
    setItemSearchKey(k => k + 1);
    focusItemSearch();
  }, [pendingItem, pendingQty, lines, focusItemSearch]);

  const updateGridQty = (tempId: string, qty: number) =>
    setLines(prev => prev.map(l => l.tempId === tempId ? { ...l, quantity: qty } : l));

  const removeLine = (tempId: string) =>
    setLines(prev => prev.filter(l => l.tempId !== tempId));

  // ── Render ──────────────────────────────────────────────────────────────────

  return (
    <div className="space-y-3 p-4">

      {/* Row 1: Customer | DOW | Code | Buttons */}
      <div className="flex flex-wrap items-end gap-3">
        <div ref={customerWrapRef} className="min-w-[260px] flex-1 space-y-1">
          <label className="text-xs font-medium text-muted-foreground">Customer</label>
          <EntityComboBox<Customer>
            items={customers}
            value={selectedCustomer?.customer_id ?? null}
            onChange={setSelectedCustomer}
            onAfterSelect={() => focusItemSearch()}
            getId={c => c.customer_id}
            getLabel={c => [c.customer_number, c.customer_name].filter(Boolean).join(' — ')}
            getSearchText={c => `${c.customer_number ?? ''} ${c.customer_name}`}
            getParentId={c => c.customer_parent_id}
            getSortKey={c => c.sort_path}
            placeholder="Search customer…"
            emptyText="No customers found."
          />
        </div>

        <div className="w-36 space-y-1">
          <label className="text-xs font-medium text-muted-foreground">Production Day</label>
          <Select value={selectedDow} onValueChange={setSelectedDow}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              {DOW_OPTIONS.map(o => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>

        <div className="w-36 space-y-1">
          <label className="text-xs font-medium text-muted-foreground">Production Time</label>
          <Select value={selectedCode} onValueChange={setSelectedCode}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              {CODE_OPTIONS.map(o => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>

        <div className="flex gap-2 pb-0.5">
          <Button variant="outline" size="sm" onClick={() => { setLines(savedLines.map(l => ({ ...l }))); }} disabled={!isDirty}>Cancel</Button>
          <Button size="sm" onClick={save} disabled={isSaving || !isDirty || !selectedCustomer}>
            {isSaving ? 'Saving…' : 'Save'}
          </Button>
        </div>
      </div>

      {/* Row 2: Item search + Qty entry */}
      <div className="flex items-end gap-2">
        <div ref={itemWrapRef} className="min-w-[260px] flex-1 space-y-1">
          <label className="text-xs font-medium text-muted-foreground">Item</label>
          <EntityComboBox<SlimItem>
            key={itemSearchKey}
            items={items}
            value={pendingItem?.item_id ?? null}
            onChange={(item) => { if (item) { setPendingItem(item); setPendingQty(''); focusQty(); } }}
            getId={i => i.item_id}
            getLabel={i => `${i.item_number} — ${i.item_name}`}
            getSearchText={i => `${i.item_number} ${i.item_name}`}
            getParentId={() => null}
            getSortKey={i => i.item_number}
            placeholder={selectedCustomer ? 'Search item…' : 'Select a customer first'}
            emptyText="No items found."
            disabled={!selectedCustomer}
          />
        </div>

        <div className="w-28 space-y-1">
          <label className="text-xs font-medium text-muted-foreground">Quantity</label>
          <input
            ref={qtyInputRef}
            type="number"
            min={0}
            value={pendingQty}
            placeholder="0"
            onChange={e => setPendingQty(e.target.value)}
            onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); commitEntry(); } }}
            disabled={!pendingItem}
            className={cn(
              'h-9 w-full rounded-md border border-input bg-background px-3 py-2 text-sm',
              'focus:outline-none focus:ring-2 focus:ring-ring',
              'disabled:opacity-50 disabled:cursor-not-allowed',
              '[appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none',
            )}
          />
        </div>
      </div>

      {/* Grid */}
      {selectedCustomer ? (
        <div className="rounded-lg border border-border/60 overflow-hidden">
          <div className="grid border-b border-border/60 bg-muted/40 px-3 py-2 text-xs font-semibold text-muted-foreground"
            style={{ gridTemplateColumns: '100px 1fr 80px 36px' }}>
            <span>Item No</span>
            <span>Item Description</span>
            <span className="text-right">Qty</span>
            <span />
          </div>

          {isLoading ? (
            <p className="px-3 py-4 text-sm text-muted-foreground">Loading…</p>
          ) : lines.length === 0 ? (
            <p className="px-3 py-4 text-sm text-muted-foreground">No standing order yet — search an item above to add lines.</p>
          ) : null}

          {lines.map(line => (
            <div key={line.tempId}
              className="grid items-center border-b border-border/40 px-3 py-1.5 hover:bg-muted/20 transition-colors"
              style={{ gridTemplateColumns: '100px 1fr 80px 36px' }}>
              <span className="font-mono text-xs text-muted-foreground">{line.item_number}</span>
              <span className="text-sm truncate pr-2">{line.item_name}</span>
              <input
                ref={el => { if (el) qtyGridRefs.current.set(line.tempId, el); else qtyGridRefs.current.delete(line.tempId); }}
                type="number" min={0}
                value={line.quantity === 0 ? '' : line.quantity}
                placeholder="0"
                onChange={e => updateGridQty(line.tempId, e.target.value === '' ? 0 : Number(e.target.value))}
                onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); focusItemSearch(); } }}
                className={cn(
                  'w-full rounded border border-transparent bg-transparent px-1 py-0.5 text-right text-sm tabular-nums',
                  'focus:border-primary focus:bg-background focus:outline-none hover:border-border',
                  '[appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none',
                )}
              />
              <button type="button" onClick={() => removeLine(line.tempId)}
                className="flex items-center justify-center rounded p-1 text-muted-foreground/40 hover:text-destructive transition-colors">
                <Trash2 className="h-3.5 w-3.5" />
              </button>
            </div>
          ))}
        </div>
      ) : (
        <div className="rounded-lg border border-dashed border-border/60 py-12 text-center text-sm text-muted-foreground">
          Select a customer to manage their standing order.
        </div>
      )}
    </div>
  );
}
