'use client';

import { useMemo, useState } from 'react';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';

export interface PickAccount { customer_id: number; customer_name: string; customer_number: string | null; /** open balance (AR Open Balances list) */ balance?: number }

const money = (v: number) => `${v < 0 ? '-' : ''}$${Math.abs(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/**
 * Active accounts with a checkbox each and a select-all in the header. A search box appears when there are more than 10.
 * With onOpen, clicking a name opens that account (activeId is highlighted) while the checkbox still picks it for the report;
 * a balance, when the accounts carry one, shows at the right.
 */
export function CustomerPicker({ accounts, selected, onChange, onOpen, activeId }: {
  accounts: PickAccount[]; selected: Set<number>; onChange: (next: Set<number>) => void; onOpen?: (id: number) => void; activeId?: number | null;
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

  return (
    <div className="rounded-md border">
      {accounts.length > 10 && (
        <div className="border-b p-2">
          <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search customers" aria-label="Search customers" />
        </div>
      )}
      <div className="flex items-center gap-3 border-b bg-muted/50 px-3 py-2 text-xs font-medium">
        <Checkbox
          checked={allShown ? true : someShown ? 'indeterminate' : false}
          onCheckedChange={(v) => toggleAll(v === true)}
          aria-label="Select all customers"
          disabled={shown.length === 0}
        />
        <span className="flex-1">Customer</span>
        <span>{selected.size} of {accounts.length} selected</span>
      </div>
      <ul className="max-h-80 overflow-y-auto">
        {shown.map((a) => (
          <li key={a.customer_id} className="border-b last:border-0">
            {onOpen ? (
              <div className={`flex items-center gap-3 px-3 py-1.5 text-sm hover:bg-muted/60 ${activeId === a.customer_id ? 'bg-accent text-accent-foreground' : ''}`}>
                <Checkbox checked={selected.has(a.customer_id)} onCheckedChange={(v) => toggle(a.customer_id, v === true)} aria-label={`Include ${a.customer_name} in the report`} />
                <button type="button" onClick={() => onOpen(a.customer_id)} aria-current={activeId === a.customer_id ? 'true' : undefined}
                  className="min-w-0 flex-1 truncate rounded text-left font-medium hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                  {a.customer_name}
                </button>
                <span className="text-xs text-muted-foreground">{a.customer_number}</span>
                {a.balance !== undefined && <span className={`w-28 text-right tabular-nums ${a.balance < 0 ? 'text-success' : ''}`}>{money(Number(a.balance))}</span>}
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
