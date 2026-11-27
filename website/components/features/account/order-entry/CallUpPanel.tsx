'use client';

import { useCallback, useEffect, useState } from 'react';
import { Phone } from 'lucide-react';
import { Checkbox } from '@/components/ui/checkbox';
import { cn } from '@/lib/utils';

export interface CallUpOrder {
  order_id: number;
  order_number: string;
  production_code: string;
  department_event: string | null;
  amount: number;
}
export interface CallUpRow {
  customer_id: number;
  customer_number: string;
  customer_name: string;
  customer_type: string;
  /** Production times with Call ticked for the day. */
  codes: string[] | null;
  parent_name: string | null;
  phone: string | null;
  assigned: string[];
  called_at: string | null;
  called_by: string | null;
  not_posted: boolean;
  orders: CallUpOrder[];
}

const HIDE_KEY = 'bps.callup.hideCalled';

/**
 * Order Entry side panel: the day's Call Up List (customers with Call ticked on their standing order). Clicking a
 * customer opens their order; the clerk ticks Called. Called customers move to the bottom, or are hidden.
 */
export function CallUpPanel({
  tenantId,
  date,
  refreshKey,
  codeLabel,
  onOpen,
}: {
  tenantId: number;
  date: string;
  /** Changes when an order is saved or opened, so amounts stay current. */
  refreshKey: unknown;
  codeLabel: (code: string) => string;
  onOpen: (row: CallUpRow, order: CallUpOrder | null) => void;
}) {
  const [rows, setRows] = useState<CallUpRow[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [hideCalled, setHideCalled] = useState(false);

  useEffect(() => {
    try { setHideCalled(window.localStorage.getItem(HIDE_KEY) === '1'); } catch { /* storage unavailable */ }
  }, []);

  const load = useCallback(async () => {
    if (!date) return;
    try {
      const res = await fetch(`/api/call-up?tenant_id=${tenantId}&date=${date}`);
      const json = (await res.json()) as { data?: CallUpRow[]; error?: string };
      if (!res.ok || json.error) throw new Error(json.error ?? 'failed');
      setRows(json.data ?? []);
      setFailed(false);
    } catch {
      setFailed(true);
    }
  }, [tenantId, date]);

  useEffect(() => { void load(); }, [load, refreshKey]);

  const toggleHide = (v: boolean) => {
    setHideCalled(v);
    try { window.localStorage.setItem(HIDE_KEY, v ? '1' : '0'); } catch { /* storage unavailable */ }
  };

  const setCalled = async (row: CallUpRow, called: boolean) => {
    setRows((prev) => prev?.map((r) => (r.customer_id === row.customer_id ? { ...r, called_at: called ? new Date().toISOString() : null } : r)) ?? prev);
    try {
      const res = await fetch('/api/call-up', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tenant_id: tenantId, customer_id: row.customer_id, date, called }),
      });
      if (!res.ok) throw new Error('failed');
    } catch {
      setFailed(true);
    }
    void load();
  };

  const all = rows ?? [];
  const done = all.filter((r) => r.called_at).length;
  const shown = [...all]
    .filter((r) => !(hideCalled && r.called_at))
    .sort((a, b) => Number(Boolean(a.called_at)) - Number(Boolean(b.called_at)));

  return (
    <section className="flex min-h-0 flex-1 flex-col border-t border-border pt-3" aria-label="Call Up List">
      <div className="px-2">
        <h2 className="flex items-baseline justify-between text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          <span>Call Up List</span>
          {rows && all.length > 0 && <span className="tabular-nums normal-case tracking-normal">{done} of {all.length} called</span>}
        </h2>
        <label className="mt-1.5 flex cursor-pointer items-center gap-2 text-xs text-muted-foreground select-none">
          <Checkbox checked={hideCalled} onCheckedChange={(v) => toggleHide(v === true)} />
          hide already called
        </label>
      </div>

      <ul className="mt-2 min-h-0 flex-1 space-y-0.5 overflow-y-auto px-1 pb-2">
        {rows === null && !failed && <li className="px-2 py-1 text-xs text-muted-foreground">Loading…</li>}
        {rows !== null && all.length === 0 && (
          <li className="px-2 py-1 text-xs text-muted-foreground">No calls for this day. Tick Call on a standing order to add one.</li>
        )}
        {rows !== null && all.length > 0 && shown.length === 0 && (
          <li className="px-2 py-1 text-xs text-muted-foreground">All {all.length} calls done.</li>
        )}
        {shown.map((r) => {
          const called = Boolean(r.called_at);
          return (
            <li key={r.customer_id} className={cn('flex items-start gap-2 rounded px-1.5 py-1 hover:bg-muted/40', called && 'opacity-55')}>
              <div className="min-w-0 flex-1">
                <button
                  type="button"
                  className="block w-full truncate text-left text-xs font-medium text-foreground hover:underline"
                  onClick={() => onOpen(r, r.orders[0] ?? null)}
                  title={r.parent_name ? `${r.customer_name} (${r.parent_name})` : r.customer_name}
                >
                  {r.customer_number ? `${r.customer_number} · ` : ''}{r.customer_name}
                </button>
                <div className="flex flex-wrap items-center gap-x-2 text-[11px] text-muted-foreground">
                  {r.orders.map((o) => (
                    <button key={o.order_id} type="button" className="tabular-nums hover:underline" onClick={() => onOpen(r, o)}>
                      {codeLabel(o.production_code)} ${Number(o.amount ?? 0).toFixed(2)}
                    </button>
                  ))}
                  {r.not_posted && <span className="text-amber-700 dark:text-amber-400">not posted</span>}
                  {r.phone && (
                    <a href={`tel:${r.phone.replace(/[^\d+]/g, '')}`} className="inline-flex items-center gap-0.5 hover:underline">
                      <Phone className="h-3 w-3" />{r.phone}
                    </a>
                  )}
                  {r.assigned.length > 0 && <span>· {r.assigned.join(', ')}</span>}
                </div>
              </div>
              <Checkbox
                className="ml-auto mt-0.5 shrink-0"
                checked={called}
                onCheckedChange={(v) => void setCalled(r, v === true)}
                aria-label={`Called ${r.customer_name}`}
              />
            </li>
          );
        })}
      </ul>
      {failed && <p className="px-2 text-xs text-muted-foreground">Couldn&apos;t refresh the call list.</p>}
    </section>
  );
}
