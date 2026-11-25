'use client';

import { Fragment, useEffect, useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import { Button } from '@/components/ui/button';

/** What was applied to an open document: a payment or credit (for an invoice), or an invoice (for an unapplied payment). */
interface Applied {
  number: string; type: string; date: string; amount: number; applied_on: string; applied: number;
  /** other documents the same payment or credit covered */
  covers: { number: string; type: string; date: string; applied: number }[];
}
interface OpenItem {
  ar_transaction_id: number | null; ar_payment_id: number | null; document_number: string; type: string; date: string; due_date: string;
  amount: number; paid: number; open: number; days_past_due: number; applied: Applied[];
}
interface Details { as_of: string; customer_id: number; customer_name: string; customer_number: string | null; balance: number; items: OpenItem[] }

const TYPE_NAME: Record<string, string> = { INV: 'Invoice', CM: 'Credit memo', PMT: 'Payment' };
/** Money with the sign in front of the $ ("-$5,768.69"). */
const money = (v: number | null | undefined) => {
  const n = Number(v ?? 0);
  return `${n < 0 ? '-' : ''}$${Math.abs(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
};
const TH = 'h-8 whitespace-nowrap bg-muted/50 px-3 text-left text-[11px] font-semibold uppercase tracking-wider text-muted-foreground';
const TD = 'px-3 py-1.5 whitespace-nowrap';
const keyOf = (i: OpenItem) => `${i.ar_transaction_id ?? ''}-${i.ar_payment_id ?? ''}`;

/**
 * One account's open items on a date (ar_open_item_details_get). A row with applications opens to show each payment or credit applied to
 * it and the other documents that payment or credit covered, so a user can see why something is still open.
 */
export function OpenItemsDetail({ tenantId, accountId, asOf }: { tenantId: number; accountId: number; asOf: string }) {
  const [data, setData] = useState<Details | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState<Set<string>>(new Set());

  useEffect(() => {
    let live = true;
    setData(null); setError(null); setOpen(new Set());
    const qs = new URLSearchParams({ tenant_id: String(tenantId), account_id: String(accountId), as_of: asOf });
    fetch(`/api/reports/financial/open-items?${qs}`)
      .then((r) => r.json())
      .then((j: { data?: Details; error?: string }) => { if (live) { if (j.error) setError(j.error); else setData(j.data ?? null); } })
      .catch((e: Error) => live && setError(e.message));
    return () => { live = false; };
  }, [tenantId, accountId, asOf]);

  const toggle = (k: string) => setOpen((prev) => { const n = new Set(prev); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const withApplied = data?.items.filter((i) => i.applied.length > 0) ?? [];
  const allOpen = withApplied.length > 0 && withApplied.every((i) => open.has(keyOf(i)));

  return (
    <section className="min-w-0 overflow-hidden rounded-lg border border-border bg-card text-card-foreground shadow-sm" aria-busy={!data && !error}>
      <div className="flex min-h-[40px] flex-wrap items-center gap-x-3 gap-y-1 border-b border-border px-4 py-1.5">
        <h2 className="text-sm font-semibold">{data ? data.customer_name : 'Open items'}</h2>
        {data && (
          <span className="text-xs text-muted-foreground">
            {data.customer_number ? `${data.customer_number} · ` : ''}{data.items.length} open item{data.items.length === 1 ? '' : 's'} as of {data.as_of}
          </span>
        )}
        {data && <span className="ml-auto text-sm font-semibold tabular-nums">Balance {money(data.balance)}</span>}
        {withApplied.length > 0 && (
          <Button variant="ghost" size="sm" className="h-7 px-2 text-xs" onClick={() => setOpen(allOpen ? new Set() : new Set(withApplied.map(keyOf)))}>
            {allOpen ? 'Collapse all' : 'Expand all'}
          </Button>
        )}
      </div>

      {error ? (
        <p role="alert" className="px-4 py-3 text-sm text-destructive">{error}</p>
      ) : !data ? (
        <div className="space-y-2 px-4 py-3" aria-label="Loading">{Array.from({ length: 6 }, (_, i) => <div key={i} className="h-5 animate-pulse rounded bg-muted/70" />)}</div>
      ) : data.items.length === 0 ? (
        <p className="px-4 py-3 text-sm text-muted-foreground">Nothing is open for this customer on {data.as_of}.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr>
                <th className={`${TH} w-8`}><span className="sr-only">Show applications</span></th>
                <th className={TH}>Document</th><th className={TH}>Type</th><th className={TH}>Date</th><th className={TH}>Due</th>
                <th className={`${TH} text-right`}>Days past due</th><th className={`${TH} text-right`}>Amount</th>
                <th className={`${TH} text-right`}>Paid</th><th className={`${TH} text-right`}>Open</th>
              </tr>
            </thead>
            <tbody>
              {data.items.map((i) => {
                const k = keyOf(i); const shown = open.has(k);
                return (
                  <Fragment key={k}>
                    <tr className="border-t border-border hover:bg-muted/40">
                      <td className="px-1 py-1 text-center">
                        {i.applied.length > 0 && (
                          <button type="button" onClick={() => toggle(k)} aria-expanded={shown}
                            aria-label={`${shown ? 'Hide' : 'Show'} what was applied to ${i.document_number}`}
                            className="inline-flex h-6 w-6 items-center justify-center rounded text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                            {shown ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                          </button>
                        )}
                      </td>
                      <td className={`${TD} font-medium`}>{i.document_number}</td>
                      <td className={TD}>{TYPE_NAME[i.type] ?? i.type}</td>
                      <td className={`${TD} text-muted-foreground`}>{i.date}</td>
                      <td className={`${TD} text-muted-foreground`}>{i.due_date}</td>
                      <td className={`${TD} text-right ${i.days_past_due > 90 ? 'text-destructive' : ''}`}>{i.days_past_due > 0 ? i.days_past_due.toLocaleString('en-US') : '—'}</td>
                      <td className={`${TD} text-right`}>{money(i.amount)}</td>
                      <td className={`${TD} text-right text-muted-foreground`}>
                        {money(i.paid)}
                        {i.applied.length > 0 && <span className="ml-1.5 text-xs">({i.applied.length})</span>}
                      </td>
                      <td className={`${TD} text-right font-semibold ${i.open < 0 ? 'text-success' : ''}`}>{money(i.open)}</td>
                    </tr>
                    {shown && (
                      <tr className="bg-muted/30">
                        <td />
                        <td colSpan={8} className="px-3 pb-3 pt-1">
                          <p className="pb-1 text-xs font-medium text-muted-foreground">
                            {i.type === 'PMT' ? 'Applied to' : 'Paid by'}
                          </p>
                          <table className="w-full text-sm">
                            <tbody>
                              {i.applied.map((a, n) => (
                                <Fragment key={n}>
                                  <tr className="border-t border-border/70">
                                    <td className="whitespace-nowrap py-1 pr-3 font-medium">{a.number}</td>
                                    <td className="py-1 pr-3">{TYPE_NAME[a.type] ?? a.type} of {money(a.amount)} dated {a.date}</td>
                                    <td className="py-1 pr-3 text-muted-foreground">applied {a.applied_on}</td>
                                    <td className="py-1 text-right font-medium tabular-nums">{money(a.applied)}</td>
                                  </tr>
                                  {a.covers.length > 0 && (
                                    <tr>
                                      <td />
                                      <td colSpan={3} className="pb-1.5 text-xs text-muted-foreground">
                                        Also covered: {a.covers.map((c) => `${TYPE_NAME[c.type] ?? c.type} ${c.number} (${c.date}) ${money(c.applied)}`).join(' · ')}
                                      </td>
                                    </tr>
                                  )}
                                </Fragment>
                              ))}
                            </tbody>
                          </table>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })}
            </tbody>
            <tfoot>
              <tr className="border-t border-border bg-muted/50 font-semibold">
                <td colSpan={8} className={TD}>Balance</td>
                <td className={`${TD} text-right`}>{money(data.balance)}</td>
              </tr>
            </tfoot>
          </table>
        </div>
      )}
    </section>
  );
}
