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
  initialCustomers: Customer[];
}

// ── Helpers ───────────────────────────────────────────────────────────────────

let _tempCounter = 0;
function nextTempId() { return `tmp-${++_tempCounter}`; }

function linesToSaved(lines: SOLine[]): SOLine[] {
  return lines.map(l => ({ ...l }));
}

// ── Component ─────────────────────────────────────────────────────────────────

export function StandingOrderMgtPage({ tenants, initialTenantId, initialCustomers }: StandingOrderMgtPageProps) {
  const tenantId = initialTenantId ?? tenants[0]?.tenant_id ?? null;

  const [customers]           = useState<Customer[]>(initialCustomers);
  const [items, setItems]     = useState<SlimItem[]>([]);
  const [selectedCustomer, setSelectedCustomer] = useState<Customer | null>(null);
  const [selectedDow,  setSelectedDow]  = useState<string>('MON');
  const [selectedCode, setSelectedCode] = useState<string>('MORNING');

  const [lines, setLines]       = useState<SOLine[]>([]);
  const [savedLines, setSavedLines] = useState<SOLine[]>([]);
  const [isLoading, setIsLoading]   = useState(false);
  const [isSaving,  setIsSaving]    = useState(false);

  // Refs for keyboard focus
  const dowRef      = useRef<HTMLButtonElement>(null);
  const codeRef     = useRef<HTMLButtonElement>(null);
  const itemSearchRef = useRef<HTMLDivElement>(null);
  const focusItemSearch = useCallback(() => {
    setTimeout(() => itemSearchRef.current?.querySelector<HTMLElement>('input,button')?.focus(), 50);
  }, []);
  const qtyRefs     = useRef<Map<string, HTMLInputElement>>(new Map());

  const isDirty = JSON.stringify(lines) !== JSON.stringify(savedLines);

  // Load items on mount
  useEffect(() => {
    if (!tenantId) return;
    fetch(`/api/items/profile?tenant_id=${tenantId}`)
      .then(r => r.json())
      .then((j: { data?: SlimItem[] }) => setItems((j.data ?? []).filter(i => i.is_active)))
      .catch(() => {});
  }, [tenantId]);

  // Load standing order when selectors change
  const load = useCallback(async (customerId: number, dow: string, code: string) => {
    if (!tenantId) return;
    setIsLoading(true);
    try {
      const res  = await fetch(`/api/standing-orders?tenant_id=${tenantId}&customer_id=${customerId}&production_dow=${dow}&production_code=${code}`);
      const json = await res.json() as { data?: { standing_order_id: number; item_id: number; item_number: string; item_name: string; quantity: number }[]; error?: string };
      if (!res.ok || json.error) { toast.error(json.error ?? 'Could not load standing order.'); return; }
      const loaded: SOLine[] = (json.data ?? []).map(r => ({
        tempId:            nextTempId(),
        standing_order_id: r.standing_order_id,
        item_id:           r.item_id,
        item_number:       r.item_number,
        item_name:         r.item_name,
        quantity:          r.quantity,
      }));
      setLines(loaded);
      setSavedLines(linesToSaved(loaded));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    if (selectedCustomer && selectedDow && selectedCode) {
      void load(selectedCustomer.customer_id, selectedDow, selectedCode);
    } else {
      setLines([]);
      setSavedLines([]);
    }
  }, [selectedCustomer, selectedDow, selectedCode, load]);

  // Save
  const save = async () => {
    if (!selectedCustomer || !tenantId) return;
    setIsSaving(true);
    try {
      const res  = await fetch('/api/standing-orders', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({
          tenant_id:       tenantId,
          customer_id:     selectedCustomer.customer_id,
          production_dow:  selectedDow,
          production_code: selectedCode,
          lines: lines.map(l => ({ item_id: l.item_id, quantity: l.quantity, prep_options: [] })),
        }),
      });
      const json = await res.json() as { error?: string };
      if (!res.ok || json.error) { toast.error(json.error ?? 'Could not save.'); return; }
      toast.success('Standing order saved.');
      await load(selectedCustomer.customer_id, selectedDow, selectedCode);
    } finally {
      setIsSaving(false);
    }
  };

  const cancel = () => {
    setLines(linesToSaved(savedLines));
  };

  // Add item
  const addItem = (item: SlimItem) => {
    if (lines.some(l => l.item_id === item.item_id)) {
      toast.error(`${item.item_number} is already on this standing order.`);
      return;
    }
    const tempId = nextTempId();
    const newLine: SOLine = {
      tempId, standing_order_id: null,
      item_id: item.item_id, item_number: item.item_number,
      item_name: item.item_name, quantity: 0,
    };
    setLines(prev => [...prev, newLine]);
    // Focus the qty input of the new line after render
    setTimeout(() => qtyRefs.current.get(tempId)?.focus(), 30);
  };

  const updateQty = (tempId: string, qty: number) => {
    setLines(prev => prev.map(l => l.tempId === tempId ? { ...l, quantity: qty } : l));
  };

  const removeLine = (tempId: string) => {
    setLines(prev => prev.filter(l => l.tempId !== tempId));
  };

  // ── Render ──────────────────────────────────────────────────────────────────

  return (
    <div className="space-y-4 p-4">

      {/* Header selectors */}
      <div className="flex flex-wrap items-end gap-3">
        <div className="min-w-[260px] flex-1 space-y-1">
          <label className="text-xs font-medium text-muted-foreground">Customer</label>
          <EntityComboBox<Customer>
            items={customers}
            value={selectedCustomer?.customer_id ?? null}
            onChange={(c) => {
              setSelectedCustomer(c);
              if (c) setTimeout(() => dowRef.current?.click(), 50);
            }}
            getId={c => c.customer_id}
            getLabel={c => `${c.customer_number ?? ''} — ${c.customer_name}`.trim()}
            getSearchText={c => `${c.customer_number ?? ''} ${c.customer_name}`}
            getParentId={c => c.customer_parent_id}
            getSortKey={c => c.sort_path}
            placeholder="Search customer"
            emptyText="No customers found."
          />
        </div>

        <div className="w-36 space-y-1">
          <label className="text-xs font-medium text-muted-foreground">Production Day</label>
          <Select value={selectedDow} onValueChange={(v) => { setSelectedDow(v); setTimeout(() => codeRef.current?.click(), 50); }}>
            <SelectTrigger ref={dowRef}>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {DOW_OPTIONS.map(o => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>

        <div className="w-36 space-y-1">
          <label className="text-xs font-medium text-muted-foreground">Production Time</label>
          <Select value={selectedCode} onValueChange={(v) => { setSelectedCode(v); }}>
            <SelectTrigger ref={codeRef}>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {CODE_OPTIONS.map(o => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>

        <div className="flex gap-2 pb-0.5">
          <Button variant="outline" size="sm" onClick={cancel} disabled={!isDirty}>Cancel</Button>
          <Button size="sm" onClick={save} disabled={isSaving || !isDirty || !selectedCustomer}>
            {isSaving ? 'Saving…' : 'Save'}
          </Button>
        </div>
      </div>

      {/* Grid */}
      {selectedCustomer ? (
        <div className="rounded-lg border border-border/60 overflow-hidden">
          {/* Column headers */}
          <div className="grid border-b border-border/60 bg-muted/40 px-3 py-2 text-xs font-semibold text-muted-foreground"
            style={{ gridTemplateColumns: '100px 1fr 80px 36px' }}>
            <span>Item No</span>
            <span>Item Description</span>
            <span className="text-right">Qty</span>
            <span />
          </div>

          {/* Lines */}
          {isLoading ? (
            <p className="px-3 py-4 text-sm text-muted-foreground">Loading…</p>
          ) : lines.length === 0 && (
            <p className="px-3 py-4 text-sm text-muted-foreground">No standing order yet. Add items below.</p>
          )}

          {lines.map((line) => (
            <div
              key={line.tempId}
              className="grid items-center border-b border-border/40 px-3 py-1.5 hover:bg-muted/20 transition-colors"
              style={{ gridTemplateColumns: '100px 1fr 80px 36px' }}
            >
              <span className="font-mono text-xs text-muted-foreground">{line.item_number}</span>
              <span className="text-sm truncate pr-2">{line.item_name}</span>
              <input
                ref={el => { if (el) qtyRefs.current.set(line.tempId, el); else qtyRefs.current.delete(line.tempId); }}
                type="number"
                min={0}
                value={line.quantity === 0 ? '' : line.quantity}
                placeholder="0"
                onChange={e => updateQty(line.tempId, e.target.value === '' ? 0 : Number(e.target.value))}
                onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); focusItemSearch(); } }}
                className={cn(
                  'w-full rounded border border-transparent bg-transparent px-1 py-0.5 text-right text-sm tabular-nums',
                  'focus:border-primary focus:bg-background focus:outline-none',
                  'hover:border-border',
                  '[appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none',
                )}
              />
              <button
                type="button"
                onClick={() => removeLine(line.tempId)}
                className="flex items-center justify-center rounded p-1 text-muted-foreground/40 hover:text-destructive transition-colors"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </button>
            </div>
          ))}

          {/* Add item row */}
          <div ref={itemSearchRef} className="px-3 py-2 border-t border-border/40 bg-muted/10">
            <EntityComboBox<SlimItem>
              alwaysOpen={false}
              collapseOnSelect
              items={items}
              value={null}
              onChange={(item) => { if (item) addItem(item); }}
              getId={i => i.item_id}
              getLabel={i => `${i.item_number} — ${i.item_name}`}
              getSearchText={i => `${i.item_number} ${i.item_name}`}
              getParentId={() => null}
              getSortKey={i => i.item_number}
              placeholder="Search item to add…"
              emptyText="No items found."
              className="max-w-md"
            />
          </div>
        </div>
      ) : (
        <div className="rounded-lg border border-dashed border-border/60 py-12 text-center text-sm text-muted-foreground">
          Select a customer to manage their standing order.
        </div>
      )}
    </div>
  );
}
