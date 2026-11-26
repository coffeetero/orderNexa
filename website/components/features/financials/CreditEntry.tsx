'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { Button } from '@/components/ui/button';

interface CustomerOption { customer_id: number; customer_parent_id: number | null; customer_name: string; customer_number: string | null; customer_type?: string | null }
interface CreditLine {
  ar_transaction_line_id: number;
  source_type: string;
  item_description: string | null;
  quantity: number;
  unit_price: number;
  amount: number;
  credited_quantity: number;
  remaining_quantity: number;
}
interface CreditOrder {
  order_id: number;
  order_date: string | null;
  order_number: string;
  department_event: string | null;
  po_number: string | null;
  customer_name: string | null;
  amount: number;
  invoice_id: number | null;
  invoice_number: string | null;
  status: string;
  credited_amount: number;
  lines: CreditLine[];
}

const money = (v: number) => `${v < 0 ? '-' : ''}$${Math.abs(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const qtyText = (v: number) => Number(v).toLocaleString('en-US', { maximumFractionDigits: 3 });
const localToday = () => new Date().toLocaleDateString('en-CA');
const shortDate = (d: string | null) => (d ? new Date(`${d.slice(0, 10)}T12:00:00`).toLocaleDateString('en-US', { month: '2-digit', day: '2-digit', year: 'numeric' }) : '');
const IN = 'h-9 w-full min-w-0 rounded-md border border-input bg-background px-2.5 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring';
const LAB = 'bps-label mb-1 block text-xs font-semibold text-muted-foreground';
const TH = 'h-8 whitespace-nowrap bg-muted/50 px-2.5 text-left text-[11px] font-semibold uppercase tracking-wider text-muted-foreground';
const TD = 'whitespace-nowrap px-2.5 py-1.5';

async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  const j = (await res.json().catch(() => ({}))) as { data?: T; error?: string };
  if (!res.ok || j.error) throw new Error(j.error ?? 'Something went wrong. Try again.');
  return j.data as T;
}

/** The order's invoice status as a word and a status colour. */
function statusOf(o: CreditOrder): { text: string; dot: string } {
  const credited = o.credited_amount > 0 ? ` · credited ${money(o.credited_amount)}` : '';
  switch (o.status) {
    case 'NONE': return { text: 'Not invoiced', dot: 'bg-muted-foreground' };
    case 'DRAFT': return { text: 'Draft', dot: 'bg-muted-foreground' };
    case 'CLOSED': return { text: `Paid${credited}`, dot: 'bg-success' };
    case 'PARTIAL': return { text: `Part paid${credited}`, dot: 'bg-info' };
    default: return { text: `Invoiced · open${credited}`, dot: 'bg-warning' };
  }
}
const creditable = (o: CreditOrder) => o.lines.length > 0;

interface FindMatch {
  order_id: number;
  order_number: string;
  department_event: string | null;
  account_id: number;
  account_name: string;
  account_number: string | null;
  production_date: string;
  production_code: string;
  invoice_number: string | null;
  po_number: string | null;
}
const FIND_KINDS = [
  { value: 'ORDER', label: 'Order No.' },
  { value: 'INVOICE', label: 'Invoice No.' },
  { value: 'PO', label: 'PO No.' },
];

export function CreditEntry({ tenantId }: { tenantId: number }) {
  const [customers, setCustomers] = useState<CustomerOption[]>([]);
  const [codes, setCodes] = useState<{ value: string; label: string }[]>([]);
  const [customerId, setCustomerId] = useState<number | null>(null);
  const [date, setDate] = useState(localToday());
  const [code, setCode] = useState('');
  const [orders, setOrders] = useState<CreditOrder[] | null>(null);
  const [selId, setSelId] = useState<number | null>(null);
  const [qty, setQty] = useState<Record<number, string>>({});
  const [reason, setReason] = useState('');
  /** False while the reason is the one built from the credit lines; true once the user types their own. */
  const [reasonEdited, setReasonEdited] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [findKind, setFindKind] = useState('ORDER');
  const [findQ, setFindQ] = useState('');
  const [matches, setMatches] = useState<FindMatch[] | null>(null);
  /** The account of the last found order, kept so an inactive account (not in the picker's list) still shows by name. */
  const [foundAccount, setFoundAccount] = useState<CustomerOption | null>(null);
  const customerRef = useRef<HTMLInputElement | null>(null);
  const dateRef = useRef<HTMLInputElement | null>(null);
  /** The order to select once the list for a found order's customer, date and time has loaded. */
  const pendingSelRef = useRef<number | null>(null);

  useEffect(() => {
    call<CustomerOption[]>(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`)
      .then((c) => setCustomers(c.filter((x) => (x.customer_type ?? '').trim().toUpperCase() === 'ACCOUNT')))
      .catch((e: Error) => setError(e.message));
    call<{ value: string; label: string }[]>(`/api/valuesets?tenant_id=${tenantId}&code=PRODUCTIONCODE`)
      .then((c) => { setCodes(c ?? []); if (c?.length) setCode(c[0].value); })
      .catch(() => {});
  }, [tenantId]);

  const load = useCallback(async (keepSelection?: number | null) => {
    if (customerId === null || !date || !code) { setOrders(null); return; }
    setError(null);
    try {
      const qs = new URLSearchParams({ tenant_id: String(tenantId), customer_id: String(customerId), production_date: date, production_code: code });
      const data = await call<{ orders: CreditOrder[] }>(`/api/invoices/credit-orders?${qs.toString()}`);
      const list = data.orders ?? [];
      setOrders(list);
      const want = pendingSelRef.current ?? keepSelection;
      pendingSelRef.current = null;
      const keep = list.find((o) => o.order_id === want && creditable(o));
      setSelId(keep ? keep.order_id : list.find(creditable)?.order_id ?? null);
      const found = list.find((o) => o.order_id === want);
      if (found && !creditable(found)) setMessage(`Order ${found.order_number} is not invoiced yet: change it in Enter Orders instead.`);
    } catch (e) {
      setOrders(null);
      setError((e as Error).message);
    }
  }, [tenantId, customerId, date, code]);

  useEffect(() => { setQty({}); if (pendingSelRef.current === null) setMessage(null); void load(); }, [load]);

  /** Opens a found order: its account, production date and time, with the order selected. */
  const openMatch = (m: FindMatch) => {
    setMatches(null);
    setMessage(null);
    if (m.account_id === customerId && m.production_date === date && m.production_code === code) {
      const o = orders?.find((x) => x.order_id === m.order_id);
      if (o && creditable(o)) { setSelId(o.order_id); setQty({}); }
      else if (o) setMessage(`Order ${o.order_number} is not invoiced yet: change it in Enter Orders instead.`);
      return;
    }
    pendingSelRef.current = m.order_id;
    setFoundAccount({ customer_id: m.account_id, customer_parent_id: null, customer_name: m.account_name, customer_number: m.account_number, customer_type: 'ACCOUNT' });
    setCustomerId(m.account_id);
    setDate(m.production_date);
    setCode(m.production_code);
  };

  const find = async () => {
    const q = findQ.trim();
    if (q === '') { customerRef.current?.focus(); return; }
    setError(null);
    setMessage(null);
    try {
      const qs = new URLSearchParams({ tenant_id: String(tenantId), kind: findKind, q });
      const data = await call<{ matches: FindMatch[] }>(`/api/invoices/credit-find?${qs.toString()}`);
      const list = data.matches ?? [];
      const label = FIND_KINDS.find((k) => k.value === findKind)?.label ?? 'number';
      if (list.length === 0) { setMatches(null); setError(`No order found for ${label} ${q}.`); return; }
      // one customer, date and time: open it straight away; otherwise let the user pick
      const slots = new Set(list.map((m) => `${m.account_id}|${m.production_date}|${m.production_code}`));
      if (slots.size === 1) openMatch(list[0]);
      else setMatches(list);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  const selected = orders?.find((o) => o.order_id === selId) ?? null;
  const lineCredit = (l: CreditLine) => (Number(qty[l.ar_transaction_line_id]) || 0) * l.unit_price;
  const typed = selected ? selected.lines.filter((l) => Number(qty[l.ar_transaction_line_id]) > 0) : [];
  // the database refuses these too; flag them here so Save stays off until they are fixed
  const overLimit = (l: CreditLine) => {
    const v = Number(qty[l.ar_transaction_line_id]);
    return qty[l.ar_transaction_line_id] !== undefined && qty[l.ar_transaction_line_id] !== '' && (!Number.isFinite(v) || v < 0 || v > l.remaining_quantity);
  };
  const anyOver = selected ? selected.lines.some(overLimit) : false;
  const creditTotal = selected ? selected.lines.reduce((s, l) => s + (overLimit(l) ? 0 : lineCredit(l)), 0) : 0;
  // "Credit 12 Kaiser Roll, Credit 2 Brioche" from the lines being credited, until the user writes their own reason
  const autoReason = typed.map((l) => `Credit ${qtyText(Number(qty[l.ar_transaction_line_id]))} ${l.item_description ?? ''}`.trim()).join(', ');
  const reasonText = reasonEdited ? reason : autoReason;

  const pick = (o: CreditOrder) => {
    if (!creditable(o) || o.order_id === selId) return;
    setSelId(o.order_id);
    setQty({});
    setReason('');
    setReasonEdited(false);
    setMessage(null);
  };

  const cancel = () => { setQty({}); setReason(''); setReasonEdited(false); setError(null); };

  /** Starts over: clears the number, customer and lists, puts the date back to today and the cursor in Number. */
  const clearAll = () => {
    cancel();
    setFindQ('');
    setMatches(null);
    setFoundAccount(null);
    setCustomerId(null);
    setDate(localToday());
    setOrders(null);
    setSelId(null);
    setMessage(null);
    pendingSelRef.current = null;
    setTimeout(() => document.getElementById('cr-find')?.focus(), 0);
  };

  const save = async () => {
    if (!selected?.invoice_id || typed.length === 0 || anyOver) return;
    setBusy(true);
    setError(null);
    try {
      const data = await call<{ document_number: string; amount: number }>('/api/invoices/credit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tenant_id: tenantId, ar_transaction_id: selected.invoice_id, reason: reasonText,
          lines: typed.map((l) => ({ ar_transaction_line_id: l.ar_transaction_line_id, quantity: Number(qty[l.ar_transaction_line_id]) })),
        }),
      });
      setMessage(`Credit memo ${data.document_number} saved for ${money(data.amount)} on invoice ${selected.invoice_number}.`);
      setQty({});
      setReason('');
      setReasonEdited(false);
      await load(selected.order_id);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const onListKey = (e: React.KeyboardEvent) => {
    if (!orders || (e.key !== 'ArrowDown' && e.key !== 'ArrowUp')) return;
    e.preventDefault();
    const list = orders.filter(creditable);
    const i = list.findIndex((o) => o.order_id === selId);
    const next = list[e.key === 'ArrowDown' ? Math.min(list.length - 1, i + 1) : Math.max(0, i - 1)];
    if (next) pick(next);
  };

  const pickerItems = foundAccount && !customers.some((c) => c.customer_id === foundAccount.customer_id) ? [...customers, foundAccount] : customers;
  const customer = pickerItems.find((c) => c.customer_id === customerId);
  /** While a number is in the Find box, the customer, date and time come from it; clear the number to change them. */
  const findActive = findQ.trim() !== '';
  const codeLabel = codes.find((c) => c.value === code)?.label ?? code;
  const dateLabel = date ? new Date(`${date}T12:00:00`).toLocaleDateString('en-US', { month: '2-digit', day: '2-digit', year: 'numeric' }) : '';

  return (
    <div className="space-y-3 p-2 sm:p-3">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <h1 className="text-lg font-semibold">Enter Credits</h1>
        <span className="text-sm text-muted-foreground">Financials › Adjustments</span>
      </div>

      <section className="rounded-lg border border-border bg-card shadow-sm">
        <div className="grid grid-cols-2 items-end gap-2.5 p-3 lg:grid-cols-[130px_170px_minmax(240px,1fr)_150px_130px]">
          <div>
            <label className={LAB} htmlFor="cr-find-kind">Find by</label>
            <select id="cr-find-kind" className={IN} value={findKind} onChange={(e) => setFindKind(e.target.value)}>
              {FIND_KINDS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}
            </select>
          </div>
          <div>
            <label className={LAB} htmlFor="cr-find">Number</label>
            <input
              id="cr-find" className={IN} value={findQ} autoFocus autoComplete="off"
              placeholder="Enter to find, blank to skip"
              onChange={(e) => setFindQ(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); void find(); } }}
            />
          </div>
          <div className="col-span-2 min-w-0 lg:col-span-1">
            <label className={LAB} htmlFor="cr-customer">Customer</label>
            <EntityComboBox<CustomerOption>
              items={pickerItems} value={customerId} disabled={findActive}
              onChange={(c) => setCustomerId(c?.customer_id ?? null)}
              onAfterSelect={() => setTimeout(() => dateRef.current?.focus(), 0)}
              getId={(c) => c.customer_id}
              getLabel={(c) => (c.customer_number ? `${c.customer_number} · ${c.customer_name}` : c.customer_name)}
              getInputLabel={(c) => (c.customer_number ? `${c.customer_number} · ${c.customer_name}` : c.customer_name)}
              getSearchText={(c) => `${c.customer_number ?? ''} ${c.customer_name}`}
              getParentId={() => null}
              getSortKey={(c) => c.customer_name}
              getItemWeight={() => 'bold'}
              placeholder="Search number or name…"
              emptyText="No customers found." clearable alwaysOpen collapseOnSelect clearSearchOnFocus
              inputRef={customerRef} triggerId="cr-customer"
            />
          </div>
          <div>
            <label className={LAB} htmlFor="cr-date">Production Date</label>
            <input id="cr-date" ref={dateRef} type="date" className={`${IN} disabled:opacity-50`} value={date} disabled={customerId === null || findActive} onChange={(e) => setDate(e.target.value)} />
          </div>
          <div>
            <label className={LAB} htmlFor="cr-code">Production Time</label>
            <select id="cr-code" className={`${IN} disabled:opacity-50`} value={code} disabled={customerId === null || findActive} onChange={(e) => setCode(e.target.value)}>
              {codes.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          </div>
        </div>
        {error && <p role="alert" className="px-3 pb-3 text-sm text-destructive">{error}</p>}
        {message && <p role="status" className="px-3 pb-3 text-sm text-success">{message}</p>}
      </section>

      {matches && (
        <section className="rounded-lg border border-border bg-card shadow-sm">
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-border px-3 py-2">
            <h2 className="text-sm font-semibold">{matches.length} orders match {findQ.trim()}</h2>
            <span className="text-sm text-muted-foreground">Click one to open it</span>
          </div>
          <div className="max-h-[17rem] overflow-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 z-[1] bg-card"><tr>
                <th className={TH}>Order No.</th><th className={TH}>Dept/Event</th><th className={TH}>Customer</th>
                <th className={TH}>Production Date</th><th className={TH}>Time</th><th className={TH}>Invoice</th><th className={TH}>PO</th>
              </tr></thead>
              <tbody>
                {matches.map((m) => (
                  <tr key={m.order_id} onClick={() => openMatch(m)} className="cursor-pointer border-t border-border hover:bg-muted/40">
                    <td className={TD}>{m.order_number}</td>
                    <td className={TD}>{m.department_event}</td>
                    <td className={TD}>{m.account_number ? `${m.account_number} · ` : ''}{m.account_name}</td>
                    <td className={`${TD} tabular-nums`}>{m.production_date}</td>
                    <td className={TD}>{m.production_code}</td>
                    <td className={TD}>{m.invoice_number ?? ''}</td>
                    <td className={TD}>{m.po_number ?? ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {orders !== null && (
        <section className="rounded-lg border border-border bg-card shadow-sm">
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-border px-3 py-2">
            <h2 className="text-sm font-semibold">Orders for {customer?.customer_name} · {dateLabel} {codeLabel}</h2>
            {orders.length > 0 && <span className="text-sm text-muted-foreground">↑ ↓ or click to pick</span>}
            <span className="flex-1" />
            <Button variant="outline" size="sm" onClick={clearAll} disabled={busy}>Clear</Button>
            <Button variant="outline" size="sm" onClick={cancel} disabled={busy}>Cancel</Button>
            <Button size="sm" onClick={() => void save()} disabled={busy || typed.length === 0 || anyOver}>{busy ? 'Saving…' : 'Save'}</Button>
          </div>
          {orders.length === 0 ? (
            <p className="px-3 py-3 text-sm text-muted-foreground">No orders for this customer, date and time.</p>
          ) : (
            <div className="max-h-[17rem] overflow-auto" tabIndex={0} onKeyDown={onListKey} role="listbox" aria-label="Orders">
              <table className="w-full text-sm">
                <thead className="sticky top-0 z-[1] bg-card"><tr>
                  <th className={`${TH} text-center`}>Date</th><th className={`${TH} text-center`}>Order No.</th><th className={TH}>Dept/Event</th><th className={TH}>PO Number</th>
                  <th className={`${TH} text-right`}>Amount</th><th className={`${TH} text-center`}>Invoice No.</th><th className={TH}>Status</th>
                </tr></thead>
                <tbody>
                  {orders.map((o) => {
                    const st = statusOf(o);
                    const sel = o.order_id === selId;
                    const ok = creditable(o);
                    return (
                      <tr key={o.order_id} role="option" aria-selected={sel} aria-disabled={!ok}
                        ref={sel ? (el) => el?.scrollIntoView({ block: 'nearest' }) : undefined}
                        title={ok ? undefined : 'Not invoiced yet: change the order in Enter Orders instead'}
                        onClick={() => pick(o)}
                        className={`border-t border-border ${sel ? 'bps-sel bg-accent font-medium text-accent-foreground shadow-[inset_3px_0_0_hsl(var(--primary))]' : ok ? 'cursor-pointer hover:bg-muted/40' : 'text-muted-foreground'}`}>
                        <td className={`${TD} text-center tabular-nums`}>{shortDate(o.order_date)}</td>
                        <td className={`${TD} text-center`}>{o.order_number}</td>
                        <td className={TD}>{o.department_event}{o.customer_name ? <span className="text-muted-foreground"> ({o.customer_name})</span> : null}</td>
                        <td className={TD}>{o.po_number ?? ''}</td>
                        <td className={`${TD} text-right tabular-nums`}>{money(o.amount)}</td>
                        <td className={`${TD} text-center`}>{o.invoice_number ?? ''}</td>
                        <td className={TD}>
                          <span className="inline-flex items-center gap-1.5 rounded-full border border-border px-2 text-xs font-medium">
                            <span className={`h-1.5 w-1.5 rounded-full ${st.dot}`} />{st.text}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </section>
      )}

      {selected && (
        <section className="rounded-lg border border-border bg-card shadow-sm">
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-border px-3 py-2">
            <h2 className="text-sm font-semibold">Order Detail</h2>
            <span className="text-sm text-muted-foreground">
              Order <b className="font-semibold text-foreground">{selected.order_number}</b>
              {selected.department_event ? ` · ${selected.department_event}` : ''} · Invoice No. <b className="font-semibold text-foreground">{selected.invoice_number}</b>
            </span>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead><tr>
                <th className={TH}>Item name</th><th className={`${TH} text-center`}>Qty</th><th className={`${TH} text-right`}>Price</th>
                <th className={`${TH} text-right`}>Extended</th><th className={`${TH} text-center`}>Credited Qty</th><th className={`${TH} text-right`}>Credit Qty</th><th className={`${TH} text-right`}>Credit Amt</th>
              </tr></thead>
              <tbody>
                {selected.lines.map((l) => {
                  const c = lineCredit(l);
                  return (
                    <tr key={l.ar_transaction_line_id} className="border-t border-border">
                      <td className={TD}>{l.item_description}</td>
                      <td className={`${TD} text-center tabular-nums`}>{qtyText(l.quantity)}</td>
                      <td className={`${TD} text-right tabular-nums`}>{money(l.unit_price)}</td>
                      <td className={`${TD} text-right tabular-nums`}>{money(l.amount)}</td>
                      <td className={`${TD} text-center tabular-nums ${l.credited_quantity > 0 ? 'font-semibold text-destructive' : 'text-muted-foreground'}`}>
                        {l.credited_quantity > 0 ? qtyText(l.credited_quantity) : '—'}
                      </td>
                      <td className={`${TD} text-right`}>
                        <input
                          type="number" min={0} max={l.remaining_quantity} step="any" inputMode="decimal"
                          aria-invalid={overLimit(l)}
                          title={`Up to ${qtyText(l.remaining_quantity)}`}
                          className={`bps-entry ml-auto block h-8 w-24 rounded-md border bg-background px-2 text-right text-sm tabular-nums focus-visible:outline-none focus-visible:ring-2 disabled:opacity-50 ${overLimit(l) ? 'border-destructive text-destructive focus-visible:ring-destructive' : 'border-input focus-visible:ring-ring'}`}
                          aria-label={`Credit quantity for ${l.item_description ?? 'line'}`}
                          disabled={l.remaining_quantity <= 0}
                          value={qty[l.ar_transaction_line_id] ?? ''}
                          onChange={(e) => setQty((q) => ({ ...q, [l.ar_transaction_line_id]: e.target.value }))}
                          onKeyDown={(e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); void save(); } }}
                        />
                      </td>
                      <td className={`${TD} text-right font-semibold tabular-nums text-destructive`}>
                        {overLimit(l) ? <span className="text-xs font-medium">Only {qtyText(l.remaining_quantity)} left</span> : c ? money(-c) : ''}
                      </td>
                    </tr>
                  );
                })}
                <tr className="border-t border-border bg-muted/40 font-semibold">
                  <td className={TD}>Order total</td><td className={TD} /><td className={TD} />
                  <td className={`${TD} text-right tabular-nums`}>{money(selected.lines.reduce((s, l) => s + l.amount, 0))}</td>
                  <td className={TD} /><td className={TD} />
                  <td className={`${TD} text-right tabular-nums text-destructive`}>{creditTotal ? money(-creditTotal) : ''}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div className="flex flex-wrap items-end gap-2.5 border-t border-border p-3">
            <div className="min-w-[16rem] flex-1">
              <label className={LAB} htmlFor="cr-reason">Reason</label>
              <input id="cr-reason" className={IN} value={reasonText} placeholder="Filled in from the credit lines; type to change it"
                onChange={(e) => { setReason(e.target.value); setReasonEdited(true); }} />
            </div>
          </div>
        </section>
      )}
    </div>
  );
}
