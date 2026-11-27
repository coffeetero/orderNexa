'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Copy } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import type { OrderEntryItem, OrderEntryLine, OrderHeaderListRow } from '@/lib/types';
import { cn } from '@/lib/utils';

/** A line picked for copying, with the item as priced for the current order. */
export interface CopyPick {
  item: OrderEntryItem;
  line: OrderEntryLine;
}

type When = 'week' | 'yday' | 'date';

function addDays(iso: string, days: number): string {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(y, m - 1, d + days);
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
}

function weekday(iso: string, style: 'long' | 'short'): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { weekday: style });
}

const selectCls = 'h-9 w-full rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring';
const key = (row: OrderHeaderListRow, line: OrderEntryLine) => `${row.order_id}:${line.tempId}`;

interface CopyOrderSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  customerName: string;
  /** The current order's production date: Last <weekday> and Yesterday count back from it. */
  productionDate: string;
  productionCodes: { value: string; label: string }[];
  /** Items as priced for the current order; a line whose item is missing here (inactive) cannot be copied. */
  items: OrderEntryItem[];
  loadHeaders: (productionDate: string, productionCode: string) => Promise<OrderHeaderListRow[]>;
  loadLines: (orderId: number) => Promise<OrderEntryLine[]>;
  /** sources: the orders the checked lines came from, in list order. */
  onCopy: (picks: CopyPick[], sources: OrderHeaderListRow[]) => void;
}

/** Order Entry › Copy order: this customer's past orders for one date, grouped by Department/Event; checked lines are added to the current order. */
export function CopyOrderSheet({ open, onOpenChange, customerName, productionDate, productionCodes, items, loadHeaders, loadLines, onCopy }: CopyOrderSheetProps) {
  const [when, setWhen] = useState<When>('week');
  const [date, setDate] = useState('');
  const [code, setCode] = useState('');
  const [groups, setGroups] = useState<{ dept: string; orders: { row: OrderHeaderListRow; lines: OrderEntryLine[] }[] }[] | null>(null);
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);

  const itemById = useMemo(() => new Map(items.map((i) => [i.item_id, i])), [items]);
  const itemByIdRef = useRef(itemById);
  itemByIdRef.current = itemById;

  useEffect(() => {
    if (!open || !productionDate) return;
    setWhen('week');
    setDate(addDays(productionDate, -7));
    setCode('');
  }, [open, productionDate]);

  // The customer's orders for the date with all their lines, grouped by Department/Event; every copyable line starts checked.
  useEffect(() => {
    if (!open || !date) return;
    let live = true;
    setGroups(null);
    setError(null);
    loadHeaders(date, code)
      .then((rows) => Promise.all(rows.map(async (row) => ({ row, lines: await loadLines(row.order_id) }))))
      .then((orders) => {
        if (!live) return;
        const byDept = new Map<string, { row: OrderHeaderListRow; lines: OrderEntryLine[] }[]>();
        for (const o of orders) {
          const dept = (o.row.department_event || 'ORDER').toUpperCase();
          byDept.set(dept, [...(byDept.get(dept) ?? []), o]);
        }
        setGroups(Array.from(byDept).sort(([a], [b]) => a.localeCompare(b)).map(([dept, os]) => ({ dept, orders: os })));
        setChecked(new Set(orders.flatMap((o) => o.lines.filter((l) => itemByIdRef.current.has(l.item_id)).map((l) => key(o.row, l)))));
      })
      .catch((e: Error) => { if (live) { setGroups([]); setError(e.message); } });
    return () => { live = false; };
  }, [open, date, code, loadHeaders, loadLines]);

  const copyableIn = useCallback((os: { row: OrderHeaderListRow; lines: OrderEntryLine[] }[]) =>
    os.flatMap((o) => o.lines.filter((l) => itemById.has(l.item_id)).map((l) => ({ row: o.row, line: l, k: key(o.row, l) }))), [itemById]);
  const all = useMemo(() => copyableIn((groups ?? []).flatMap((g) => g.orders)), [groups, copyableIn]);
  const nChecked = all.filter((c) => checked.has(c.k)).length;
  const nOrders = (groups ?? []).reduce((n, g) => n + g.orders.length, 0);

  const copy = () => {
    const picks = all.filter((c) => checked.has(c.k));
    if (picks.length === 0) return;
    const sources = Array.from(new Map(picks.map((p) => [p.row.order_id, p.row])).values());
    onCopy(picks.map(({ line }) => ({ line, item: itemById.get(line.item_id)! })), sources);
  };

  const setMany = (ks: string[], on: boolean) => setChecked((prev) => {
    const next = new Set(prev);
    for (const k of ks) { if (on) next.add(k); else next.delete(k); }
    return next;
  });

  const dateLabel = date ? `${weekday(date, 'short')} ${date.slice(5, 7)}/${date.slice(8, 10)}/${date.slice(0, 4)}` : '';

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="flex w-[min(460px,100vw)] max-w-none sm:max-w-none flex-col gap-0 overflow-hidden p-0">
        <SheetHeader className="space-y-1 px-4 pb-3 pt-5 pr-10">
          <SheetTitle className="text-base">Copy order</SheetTitle>
          <SheetDescription>{customerName} · past orders</SheetDescription>
        </SheetHeader>

        <div className="flex flex-wrap items-end gap-2 px-4 pb-2 lg:px-3">
          <div className="w-32 space-y-1">
            <Label htmlFor="copy-when" className="text-xs">Orders from</Label>
            <select id="copy-when" className={selectCls} value={when}
              onChange={(e) => {
                const v = e.target.value as When;
                setWhen(v);
                if (v === 'week') setDate(addDays(productionDate, -7));
                if (v === 'yday') setDate(addDays(productionDate, -1));
              }}>
              <option value="week">Last {productionDate ? weekday(productionDate, 'long') : 'week'}</option>
              <option value="yday">Yesterday</option>
              <option value="date">Date</option>
            </select>
          </div>
          <div className="w-36 space-y-1">
            <Label htmlFor="copy-date" className="text-xs">Production Date</Label>
            <Input id="copy-date" type="date" className="h-9" value={date} max={productionDate}
              onChange={(e) => { setWhen('date'); setDate(e.target.value); }} />
          </div>
          <div className="w-[6.5rem] space-y-1">
            <Label htmlFor="copy-code" className="text-xs">Code</Label>
            <select id="copy-code" className={selectCls} value={code} onChange={(e) => setCode(e.target.value)}>
              <option value="">All</option>
              {productionCodes.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          </div>
        </div>

        <div className="flex items-center justify-between gap-2 px-4 pb-2 lg:px-3">
          <span className="text-xs text-muted-foreground">
            {groups ? `${nOrders} order${nOrders === 1 ? '' : 's'} · ${dateLabel}` : 'Loading…'}
          </span>
          <Button size="sm" className="h-8 gap-1" disabled={nChecked === 0} onClick={copy}>
            <Copy className="h-3.5 w-3.5" />
            {nChecked === 0 || nChecked === all.length ? 'Copy' : `Copy ${nChecked}`}
          </Button>
        </div>

        <div className="min-h-0 flex-1 space-y-2 overflow-auto px-4 pb-4 lg:px-3 lg:pb-3">
          {error && <p role="alert" className="text-xs text-destructive">{error}</p>}
          {groups?.length === 0 && <p className="rounded-md border border-border/80 px-3 py-3 text-sm text-muted-foreground">No orders for this customer on that date.</p>}
          {groups?.map((g) => {
            const ks = copyableIn(g.orders).map((c) => c.k);
            const n = ks.filter((k) => checked.has(k)).length;
            return (
              <section key={g.dept} aria-label={g.dept} className="overflow-hidden rounded-md border border-border/80 bg-card">
                <label className="flex items-center justify-between gap-2 bg-muted/60 px-3 py-1 text-sm font-semibold uppercase">
                  <span className="truncate">{g.dept}</span>
                  <Checkbox aria-label={`Check all ${g.dept}`} disabled={ks.length === 0}
                    checked={ks.length > 0 && n === ks.length ? true : n > 0 ? 'indeterminate' : false}
                    onCheckedChange={(v) => setMany(ks, v === true)} />
                </label>
                {g.orders.map(({ row, lines }) => (
                  <div key={row.order_id}>
                    <div className="truncate border-t border-border/60 px-3 py-0.5 text-xs text-muted-foreground">
                      <span>
                        {row.order_number || `Order #${row.order_id}`}
                        {row.production_code ? ` · ${row.production_code}` : ''}
                        {row.invoice_number ? ` · ${row.invoice_number}` : ''}
                        {` · ${lines.length} lines`}
                      </span>
                    </div>
                    {lines.map((l) => {
                      const item = itemById.get(l.item_id);
                      const k = key(row, l);
                      return (
                        <label key={k} className={cn('grid grid-cols-[3.5rem_minmax(0,1fr)_3rem_1rem] items-center gap-2 border-t border-border/40 px-3 py-0.5 text-xs', !item && 'text-muted-foreground')}>
                          <span className="tabular-nums">{l.item_number}</span>
                          <span className="truncate">
                            <span className={cn(!item && 'line-through')}>{l.item_description}</span>
                            {!item && ' (inactive)'}
                            {item?.in_pricebook === false && <span className="ml-1.5 text-[10px] font-bold uppercase text-amber-700 dark:text-amber-400">no price</span>}
                          </span>
                          <span className="text-right tabular-nums">{l.quantity}</span>
                          <Checkbox aria-label={`Copy ${l.item_description}`} disabled={!item}
                            checked={item ? checked.has(k) : false} onCheckedChange={(v) => setMany([k], v === true)} />
                        </label>
                      );
                    })}
                  </div>
                ))}
              </section>
            );
          })}
        </div>
      </SheetContent>
    </Sheet>
  );
}
