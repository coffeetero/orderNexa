'use client';

import { useMemo, useState } from 'react';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';

export interface PickAccount { customer_id: number; customer_name: string; customer_number: string | null; /** open balance (AR Open Balances list) */ balance?: number }

const money = (v: number) => `${v < 0 ? '-' : ''}$${Math.abs(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/**
 * Active accounts with a checkbox each and a select-all in the header. A search box appears when there are more than 10.
 * With onOpen, clicking a name opens that account (activeId is highlighted) while the checkbox still picks it for the report;
 * a balance, when the accounts carry one, shows at the right.
 */
export function CustomerPicker({ accounts, selected, onChange, onOpen, activeId, inSidebar = false }: {
  accounts: PickAccount[]; selected: Set<number>; onChange: (next: Set<number>) => void; onOpen?: (id: number) => void; activeId?: number | null;
  /** In the page sidebar: 12px rows, full height with its own scroll (AR Open Balances, owner request 2026-11-27). */
  inSidebar?: boolean;
}) {
  const [q, setQ] = useState('');
  const shown = useMemo(() => {
    const t = q.trim().toLowerCase();
    return t ? accounts.filter((a) => a.customer_name.toLowerCase().includes(t) || (a.customer_number ?? '').toLowerCase().includes(t)) : accounts;
  }, [accounts, q]);
  const allShown = shown.length > 0 && shown.every((a) => selected.has(a.customer_id));
  const someShown = shown.some((a) => selected.has(a.customer_id));

  const toggleAll = (on: boolean) => {
    const next = new Set(selected);
    shown.forEach((a) => (on ? next.add(a.customer_id) : next.delete(a.customer_id)));
    onChange(next);
  };
  const toggle = (id: number, on: boolean) => {
    const next = new Set(selected);
    if (on) next.add(id); else next.delete(id);
    onChange(next);
  };

  const selectAll = (
    <Checkbox
      checked={allShown ? true : someShown ? 'indeterminate' : false}
      onCheckedChange={(v) => toggleAll(v === true)}
      aria-label="Select all customers"
      disabled={shown.length === 0}
    />
  );

  return (
    <div className={cn('rounded-md border', inSidebar && 'flex min-h-0 flex-1 flex-col bg-card')}>
      {accounts.length > 10 && (
        <div className="border-b p-2">
          <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search customers" aria-label="Search customers" className={cn(inSidebar && 'h-8 text-xs')} />
        </div>
      )}
      <div className={cn('flex items-center border-b bg-muted/50 py-2 text-xs font-medium', inSidebar ? 'gap-2 px-2' : 'gap-3 px-3')}>
        {!inSidebar && selectAll}
        <span className="flex-1">Customer</span>
        <span>{selected.size} of {accounts.length} selected</span>
        {inSidebar && selectAll}
      </div>
      <ul className={cn('overflow-y-auto', inSidebar ? 'min-h-0 flex-1' : 'max-h-80')}>
        {shown.map((a) => (
          <li key={a.customer_id} className="border-b last:border-0">
            {onOpen ? (
              <div className={cn('flex items-center py-1.5 hover:bg-muted/60', inSidebar ? 'gap-2 px-2 text-xs' : 'gap-3 px-3 text-sm', activeId === a.customer_id && 'bg-accent text-accent-foreground')}>
                {!inSidebar && <Checkbox checked={selected.has(a.customer_id)} onCheckedChange={(v) => toggle(a.customer_id, v === true)} aria-label={`Include ${a.customer_name} in the report`} />}
                <button type="button" onClick={() => onOpen(a.customer_id)} aria-current={activeId === a.customer_id ? 'true' : undefined}
                  title={a.customer_name}
                  className="min-w-0 flex-1 truncate rounded text-left font-medium hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                  {a.customer_name}
                </button>
                <span className="shrink-0 text-xs text-muted-foreground">{a.customer_number}</span>
                {a.balance !== undefined && <span className={cn('text-right tabular-nums', inSidebar ? 'w-[4.75rem] shrink-0' : 'w-28', a.balance < 0 && 'text-success')}>{money(Number(a.balance))}</span>}
                {inSidebar && <Checkbox checked={selected.has(a.customer_id)} onCheckedChange={(v) => toggle(a.customer_id, v === true)} aria-label={`Include ${a.customer_name} in the report`} className="shrink-0" />}
              </div>
            ) : (
              <label className="flex cursor-pointer items-center gap-3 px-3 py-1.5 text-sm hover:bg-muted/60">
                <Checkbox checked={selected.has(a.customer_id)} onCheckedChange={(v) => toggle(a.customer_id, v === true)} aria-label={a.customer_name} />
                <span className="flex-1 truncate">{a.customer_name}</span>
                <span className="text-xs text-muted-foreground">{a.customer_number}</span>
              </label>
            )}
          </li>
        ))}
        {shown.length === 0 && <li className="px-3 py-3 text-sm text-muted-foreground">No customers match.</li>}
      </ul>
    </div>
  );
}
