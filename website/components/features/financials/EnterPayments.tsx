'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import { Button } from '@/components/ui/button';

/**
 * Financials › Cash › Enter Payments (approved 2026-11-25, docs/design/mockups/enter-payments.html; treated as a protected,
 * heads-down entry screen like Order Entry). The old BPS AR - Payments workflow: customer, received date, check no., amount;
 * then the cursor waits in Invoice #, ↑ ↓ (or typing, or a click) picks a transaction, Enter / Tab goes to Payment (defaults to
 * what is open on it), Enter applies and moves to the next. A credit (credit memo or negative invoice) or an earlier payment's
 * unapplied cash (PMT) is taken whole: it adds to the check balance and closes. A new payment needs its check no. or CASH. Allowance (with a reason saying why and which items) sits on the invoice. The list is read
 * only. Save sends everything in one call (ar_payment_enter); the database checks every rule again.
 */

interface CustomerOption { customer_id: number; customer_parent_id: number | null; customer_name: string; customer_number: string | null; customer_type?: string | null; sort_path?: string }
interface OpenInvoice { ar_transaction_id: number; document_number: string; transaction_date: string; amount: number; open: number; allowance: number; allowance_reason: string | null }
interface OpenCredit { ar_transaction_id: number; document_number: string; transaction_type: string; transaction_date: string; amount: number; available: number }
interface UnappliedPayment { ar_payment_id: number; payment_number: string | null; payment_date: string; payment_method: string | null; reference_number: string | null; amount: number; unapplied: number }
/** One line of the list: an open invoice, a credit (credit memo / negative invoice) or an earlier payment with unapplied cash. */
interface Row { key: string; txId?: number; payId?: number; date: string; type: string; number: string; amount: number; returns: number; open: number; credit: boolean; priorAllowance: number }
interface Line { payment: number; allowance: number; reason: string }

const money = (v: number) => `${v < 0 ? '-' : ''}$${Math.abs(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const num = (s: string) => { const v = Number.parseFloat(s.replace(/[$,\s]/g, '')); return Number.isFinite(v) ? Math.round(v * 100) / 100 : 0; };
const cents = (v: number) => Math.round(v * 100);
const shortDate = (d: string) => new Date(`${d}T12:00:00`).toLocaleDateString('en-US', { month: '2-digit', day: '2-digit', year: '2-digit' });
const localToday = () => new Date().toLocaleDateString('en-CA');
const IN = 'h-9 w-full min-w-0 rounded-md border border-input bg-background px-2.5 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring';
const LAB = 'mb-1 block text-[11px] font-semibold uppercase tracking-wider text-muted-foreground';
const TH = 'h-8 whitespace-nowrap bg-muted/50 px-2.5 text-left text-[11px] font-semibold uppercase tracking-wider text-muted-foreground';
const TD = 'whitespace-nowrap px-2.5 py-1.5';

async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  const j = (await res.json().catch(() => ({}))) as { data?: T; error?: string };
  if (!res.ok || j.error) throw new Error(j.error ?? 'Something went wrong. Try again.');
  return j.data as T;
}

export function EnterPayments({ tenantId }: { tenantId: number }) {
  const [customers, setCustomers] = useState<CustomerOption[]>([]);
  const [customerId, setCustomerId] = useState<number | null>(null);
  const [date, setDate] = useState(localToday());
  const [checkNo, setCheckNo] = useState('');
  const [amount, setAmount] = useState('');
  const [rows, setRows] = useState<Row[] | null>(null);
  const [lines, setLines] = useState<Map<string, Line>>(new Map());
  const [sel, setSel] = useState(-1);
  const [invoiceText, setInvoiceText] = useState('');
  const [pay, setPay] = useState('');
  const [allow, setAllow] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; tone: 'ok' | 'error' | 'ask'; confirm?: 'duplicate' | 'unapplied' } | null>(null);

  const customerRef = useRef<HTMLInputElement>(null);
  const dateRef = useRef<HTMLInputElement>(null);
  const invRef = useRef<HTMLInputElement>(null);
  const payRef = useRef<HTMLInputElement>(null);
  const tbodyRef = useRef<HTMLTableSectionElement>(null);

  useEffect(() => {
    call<CustomerOption[]>(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`)
      .then((c) => setCustomers(c.filter((x) => (x.customer_type ?? '').trim().toUpperCase() === 'ACCOUNT')))
      .catch((e: Error) => setMsg({ text: e.message, tone: 'error' }));
  }, [tenantId]);

  const loadItems = useCallback(async (id: number) => {
    setRows(null);
    try {
      const d = await call<{ invoices: OpenInvoice[]; credits: OpenCredit[]; unapplied_payments: UnappliedPayment[] }>(`/api/payments/open-items?tenant_id=${tenantId}&customer_id=${id}`);
      const list: Row[] = [
        ...d.invoices.map((i) => ({ key: `t${i.ar_transaction_id}`, txId: i.ar_transaction_id, date: i.transaction_date, type: 'INV', number: i.document_number, amount: Number(i.amount), returns: 0, open: Number(i.open), credit: false, priorAllowance: Number(i.allowance ?? 0) })),
        ...d.credits.map((c) => ({ key: `t${c.ar_transaction_id}`, txId: c.ar_transaction_id, date: c.transaction_date, type: c.transaction_type, number: c.document_number, amount: Number(c.amount), returns: 0, open: -Number(c.available), credit: true, priorAllowance: 0 })),
        ...(d.unapplied_payments ?? []).map((p) => ({
          key: `p${p.ar_payment_id}`, payId: p.ar_payment_id, date: p.payment_date, type: 'PMT',
          number: [p.payment_number ?? `#${p.ar_payment_id}`, p.payment_method === 'CASH' ? 'CASH' : p.reference_number].filter(Boolean).join(' · '),
          amount: -Number(p.amount), returns: 0, open: -Number(p.unapplied), credit: true, priorAllowance: 0,
        })),
      ].sort((a, b) => a.date.localeCompare(b.date) || a.number.localeCompare(b.number));
      setRows(list); setLines(new Map()); setSel(list.length ? 0 : -1); setInvoiceText(list[0]?.number ?? '');
    } catch (e) { setMsg({ text: (e as Error).message, tone: 'error' }); setRows([]); }
  }, [tenantId]);

  const lineOf = (key: string): Line => lines.get(key) ?? { payment: 0, allowance: 0, reason: '' };
  const balanceOf = (r: Row) => Math.round((r.open - lineOf(r.key).payment - lineOf(r.key).allowance) * 100) / 100;
  const applied = useMemo(() => Array.from(lines.values()).reduce((s, l) => s + cents(l.payment), 0) / 100, [lines]);
  const left = Math.round((num(amount) - applied) * 100) / 100;
  const dirty = lines.size > 0 || amount !== '' || checkNo !== '';

  const pick = useCallback((i: number) => {
    if (!rows?.length) return;
    const k = Math.max(0, Math.min(rows.length - 1, i));
    setSel(k); setInvoiceText(rows[k].number);
  }, [rows]);
  useEffect(() => { tbodyRef.current?.querySelector(`[data-i="${sel}"]`)?.scrollIntoView({ block: 'nearest' }); }, [sel]);

  /** Enter / Tab from Invoice #: Payment defaults from the transaction (a credit is taken whole). */
  const toPayment = () => {
    const r = rows?.[sel]; if (!r) return;
    const l = lineOf(r.key);
    setPay((r.credit ? r.open : Math.max(0, r.open - l.allowance)).toFixed(2));
    setAllow(l.allowance ? l.allowance.toFixed(2) : ''); setReason(l.reason);
    setTimeout(() => { payRef.current?.focus(); payRef.current?.select(); }, 0);
  };

  /** Enter in Payment / Allowance / Reason: records the line and moves on to the next open transaction. */
  const apply = () => {
    const r = rows?.[sel]; if (!r) return;
    const next = new Map(lines);
    if (r.credit) next.set(r.key, { payment: r.open, allowance: 0, reason: '' });
    else {
      const p = num(pay), a = num(allow);
      if (p < 0 || a < 0) { setMsg({ text: 'Amounts on an invoice cannot be negative.', tone: 'error' }); return; }
      if (cents(p) + cents(a) > cents(r.open)) { setMsg({ text: `Invoice ${r.number} has ${money(r.open)} open; the payment and allowance add up to more.`, tone: 'error' }); return; }
      if (a > 0 && !reason.trim()) { setMsg({ text: `Say why the allowance on invoice ${r.number} was given, and which items.`, tone: 'error' }); return; }
      if (p === 0 && a === 0) next.delete(r.key); else next.set(r.key, { payment: p, allowance: a, reason: a ? reason.trim() : '' });
    }
    setLines(next); setPay(''); setAllow(''); setReason(''); setMsg(null);
    const after = rows!.findIndex((x, j) => j > sel && Math.abs((x.open - (next.get(x.key)?.payment ?? 0) - (next.get(x.key)?.allowance ?? 0))) > 0.004);
    pick(after >= 0 ? after : sel);
    setTimeout(() => { invRef.current?.focus(); invRef.current?.select(); }, 0);
  };

  const reset = (keepCustomer: boolean) => {
    setLines(new Map()); setAmount(''); setCheckNo(''); setPay(''); setAllow(''); setReason('');
    if (keepCustomer && customerId !== null) void loadItems(customerId);
    else { setCustomerId(null); setRows(null); setTimeout(() => customerRef.current?.focus(), 0); }
  };

  const save = async (confirm?: 'duplicate' | 'unapplied') => {
    if (customerId === null) { setMsg({ text: 'Choose a customer.', tone: 'error' }); return; }
    if (left < 0) return;
    // a new payment (money in, or credits taken) needs its check number, or CASH; reapplying earlier cash alone does not
    const newMoney = num(amount) > 0 || (rows ?? []).some((r) => r.txId !== undefined && r.credit && lines.has(r.key));
    if (newMoney && !checkNo.trim()) {
      setMsg({ text: 'Enter the check number, or CASH for cash.', tone: 'error' });
      document.getElementById('pay-check')?.focus();
      return;
    }
    if (left > 0 && confirm !== 'unapplied' && confirm !== 'duplicate') {
      setMsg({ text: `${money(left)} is not applied to any invoice. Keep it on the customer's account as unapplied cash?`, tone: 'ask', confirm: 'unapplied' });
      return;
    }
    setBusy(true); setMsg(null);
    try {
      const d = await call<{ payment_number?: string; allowances_only?: boolean; count?: number; reapplied?: number }>('/api/payments/enter', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tenant_id: tenantId, customer_id: customerId, payment_date: date, check_no: checkNo, amount: num(amount), allow_duplicate: confirm === 'duplicate',
          lines: (rows ?? []).filter((r) => lines.has(r.key)).map((r) => {
            const l = lineOf(r.key);
            return r.payId !== undefined ? { ar_payment_id: r.payId, payment: l.payment }
              : { ar_transaction_id: r.txId, payment: l.payment, allowance: l.allowance, allowance_reason: l.reason };
          }),
        }),
      });
      const parts = d.allowances_only ? [] : [`Payment ${d.payment_number} saved`];
      if (d.reapplied) parts.push(`${d.reapplied} earlier payment${d.reapplied === 1 ? '' : 's'} applied`);
      if (d.count) parts.push(`${d.count} allowance${d.count === 1 ? '' : 's'} saved`);
      setMsg({ text: `${parts.join(', ')}.`, tone: 'ok' });
      reset(true);
      setTimeout(() => dateRef.current?.focus(), 0);
    } catch (e) {
      const text = (e as Error).message;
      if (text.startsWith('Duplicate reference')) setMsg({ text: `${text}. Save it anyway?`, tone: 'ask', confirm: 'duplicate' });
      else setMsg({ text, tone: 'error' });
    } finally { setBusy(false); }
  };

  const customer = customers.find((c) => c.customer_id === customerId);
  const balTone = left === 0 ? 'border-success text-success bg-success-soft' : left < 0 ? 'border-destructive text-destructive bg-destructive/10' : 'border-warning text-warning bg-warning-soft';
  const totals = (rows ?? []).reduce((t, r) => ({ amount: t.amount + r.amount, payment: t.payment + lineOf(r.key).payment, allowance: t.allowance + lineOf(r.key).allowance, balance: t.balance + balanceOf(r) }), { amount: 0, payment: 0, allowance: 0, balance: 0 });

  return (
    <div className="space-y-3 py-3">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <h1 className="text-lg font-semibold tracking-tight">Enter Payments</h1>
        <span className="text-sm text-muted-foreground">Financials › Cash</span>
        <span className="flex-1" />
        <Button variant="outline" size="sm" onClick={() => { setMsg(null); reset(true); }} disabled={busy || !dirty}>Cancel</Button>
        <Button size="sm" onClick={() => void save()} disabled={busy || customerId === null || left < 0 || (lines.size === 0 && num(amount) === 0)}>{busy ? 'Saving…' : 'Save payment'}</Button>
      </div>

      {msg && (
        <div role={msg.tone === 'error' ? 'alert' : 'status'} className={`flex flex-wrap items-center gap-3 rounded-md border px-3 py-2 text-sm ${msg.tone === 'error' ? 'border-destructive/30 bg-destructive/10 text-destructive' : msg.tone === 'ask' ? 'border-warning/40 bg-warning-soft' : 'border-success/30 bg-success-soft text-success'}`}>
          <span className="min-w-0 flex-1">{msg.text}</span>
          {msg.confirm && (
            <span className="flex gap-2">
              <Button size="sm" variant="outline" onClick={() => setMsg(null)}>Cancel</Button>
              <Button size="sm" onClick={() => void save(msg.confirm)} disabled={busy}>{msg.confirm === 'duplicate' ? 'Save anyway' : 'Keep on account and save'}</Button>
            </span>
          )}
        </div>
      )}

      <section className="rounded-lg border border-border bg-card shadow-sm">
        <div className="grid grid-cols-2 items-end gap-2.5 p-3 lg:grid-cols-[minmax(260px,2.2fr)_150px_150px_150px_170px]">
          <div className="col-span-2 min-w-0 lg:col-span-1">
            <label className={LAB} htmlFor="pay-customer">Customer</label>
            <EntityComboBox<CustomerOption>
              items={customers} value={customerId}
              onChange={(c) => { setCustomerId(c?.customer_id ?? null); setMsg(null); if (c) void loadItems(c.customer_id); else setRows(null); }}
              onAfterSelect={() => setTimeout(() => dateRef.current?.focus(), 0)}
              getId={(c) => c.customer_id}
              getLabel={(c) => (c.customer_number ? `${c.customer_number} · ${c.customer_name}` : c.customer_name)}
              getInputLabel={(c) => (c.customer_number ? `${c.customer_number} · ${c.customer_name}` : c.customer_name)}
              getSearchText={(c) => `${c.customer_number ?? ''} ${c.customer_name}`}
              getParentId={() => null}
              getSortKey={(c) => c.customer_name}
              getItemWeight={() => 'bold'}
              placeholder="Search number or name…"
              emptyText="No customers found." clearable alwaysOpen collapseOnSelect clearSearchOnFocus autoFocus
              inputRef={customerRef} triggerId="pay-customer"
            />
          </div>
          <div><label className={LAB} htmlFor="pay-date">Received</label><input id="pay-date" ref={dateRef} type="date" className={IN} value={date} onChange={(e) => setDate(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); document.getElementById('pay-check')?.focus(); } }} /></div>
          <div><label className={LAB} htmlFor="pay-check">Check no.</label><input id="pay-check" className={IN}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); document.getElementById('pay-amount')?.focus(); } }} value={checkNo} placeholder="or CASH" onChange={(e) => setCheckNo(e.target.value)} /></div>
          <div>
            <label className={LAB} htmlFor="pay-amount">Amount</label>
            <input id="pay-amount" className={`${IN} text-right tabular-nums`} value={amount} inputMode="decimal" placeholder="0.00"
              onChange={(e) => setAmount(e.target.value)}
              onBlur={() => amount && setAmount(num(amount).toFixed(2))}
              onKeyDown={(e) => { if (e.key === 'Enter' || (e.key === 'Tab' && !e.shiftKey)) { e.preventDefault(); if (amount) setAmount(num(amount).toFixed(2)); invRef.current?.focus(); invRef.current?.select(); } }} />
          </div>
          <div>
            <span className={LAB}>Check balance</span>
            <div className={`flex h-9 items-center justify-end rounded-md border px-3 text-base font-semibold tabular-nums ${balTone}`} aria-live="polite">{money(left)}</div>
          </div>
        </div>

        <div className="grid grid-cols-2 items-end gap-2.5 border-t border-border p-3 lg:grid-cols-[170px_150px_150px_minmax(0,1fr)]">
          <div>
            <label className={LAB} htmlFor="pay-inv">Invoice #</label>
            <input id="pay-inv" ref={invRef} className={`${IN} border-primary`} autoComplete="off" value={invoiceText} disabled={!rows?.length}
              onChange={(e) => { const t = e.target.value; setInvoiceText(t); const i = rows?.findIndex((r) => t.trim() && r.number.toLowerCase().startsWith(t.trim().toLowerCase())) ?? -1; if (i >= 0) setSel(i); }}
              onKeyDown={(e) => {
                if (e.key === 'ArrowDown') { e.preventDefault(); pick(sel + 1); }
                else if (e.key === 'ArrowUp') { e.preventDefault(); pick(sel - 1); }
                else if (e.key === 'Enter' || (e.key === 'Tab' && !e.shiftKey)) { e.preventDefault(); toPayment(); }
              }} />
          </div>
          <div>
            <label className={LAB} htmlFor="pay-pay">Payment</label>
            <input id="pay-pay" ref={payRef} className={`${IN} text-right tabular-nums`} inputMode="decimal" placeholder="0.00" value={pay} disabled={sel < 0}
              readOnly={!!rows?.[sel]?.credit} onChange={(e) => setPay(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); apply(); } else if (e.key === 'Escape') invRef.current?.focus(); }} />
          </div>
          <div>
            <label className={LAB} htmlFor="pay-allow">Allowance</label>
            <input id="pay-allow" className={`${IN} text-right tabular-nums`} inputMode="decimal" placeholder="0.00" value={allow} disabled={sel < 0 || !!rows?.[sel]?.credit}
              onChange={(e) => setAllow(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); apply(); } }} />
          </div>
          <div className="col-span-2 lg:col-span-1">
            <label className={LAB} htmlFor="pay-reason">Allowance reason</label>
            <input id="pay-reason" className={IN} placeholder="Why, and which items (e.g. 2 cases rye, moldy)" value={reason} disabled={sel < 0 || !!rows?.[sel]?.credit}
              onChange={(e) => setReason(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); apply(); } }} />
          </div>
        </div>
      </section>

      <section className="min-w-0 overflow-hidden rounded-lg border border-border bg-card shadow-sm">
        <div className="flex min-h-[40px] items-center justify-between gap-3 border-b border-border px-3 py-1.5">
          <h2 className="text-sm font-semibold">{customer ? `Open transactions · ${customer.customer_name}` : 'Open transactions'}</h2>
          {rows && <span className="text-xs text-muted-foreground">{rows.filter((r) => Math.abs(balanceOf(r)) > 0.004).length} still open after this payment</span>}
        </div>
        {customerId === null ? (
          <p className="px-4 py-6 text-center text-sm text-muted-foreground">Choose a customer to see what they owe.</p>
        ) : rows === null ? (
          <div className="space-y-2 px-4 py-3">{Array.from({ length: 6 }, (_, i) => <div key={i} className="h-5 animate-pulse rounded bg-muted/70" />)}</div>
        ) : rows.length === 0 ? (
          <p className="px-4 py-6 text-center text-sm text-muted-foreground">Nothing open for this customer. A payment stays on account as unapplied cash.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead><tr>
                <th className={TH}>Date</th><th className={TH}>Type</th><th className={TH}>Number</th><th className={`${TH} text-right`}>Amount</th>
                <th className={`${TH} text-right`}>Returns</th><th className={`${TH} text-right`}>Payment</th><th className={`${TH} text-right`}>Allowance</th>
                <th className={TH}>Reason</th><th className={`${TH} text-right`}>Balance</th>
              </tr></thead>
              <tbody ref={tbodyRef}>
                {rows.map((r, i) => {
                  const l = lineOf(r.key); const b = balanceOf(r); const done = Math.abs(b) < 0.005 && (l.payment !== 0 || l.allowance !== 0);
                  return (
                    <tr key={r.key} data-i={i} onClick={() => { pick(i); setTimeout(toPayment, 0); }}
                      className={`cursor-pointer border-t border-border ${i === sel ? 'bg-accent font-medium text-accent-foreground shadow-[inset_3px_0_0_hsl(var(--primary))]' : 'hover:bg-muted/40'} ${done && i !== sel ? 'text-muted-foreground' : ''}`}>
                      <td className={`${TD} text-muted-foreground`}>{shortDate(r.date)}</td>
                      <td className={TD}><span className={`rounded px-1.5 py-0.5 text-[11px] font-semibold ${r.type === 'CM' || r.type === 'PMT' ? 'bg-info-soft text-info' : 'bg-muted text-muted-foreground'}`}>{r.type}</span></td>
                      <td className={TD}>{r.number}</td>
                      <td className={`${TD} text-right tabular-nums ${r.amount < 0 ? 'text-info' : ''}`}>{money(r.amount)}</td>
                      <td className={`${TD} text-right tabular-nums text-muted-foreground`}>{r.returns ? money(-r.returns) : '—'}</td>
                      <td className={`${TD} text-right tabular-nums ${l.payment ? 'font-medium text-primary' : 'text-muted-foreground'}`}>{l.payment ? money(l.payment) : '—'}</td>
                      <td className={`${TD} text-right tabular-nums ${l.allowance ? 'font-medium text-primary' : 'text-muted-foreground'}`}>
                        {l.allowance ? money(l.allowance) : r.priorAllowance ? <span title="Allowance already on this invoice">{money(r.priorAllowance)}*</span> : '—'}
                      </td>
                      <td className={`${TD} max-w-[16rem] truncate ${l.reason ? '' : 'text-muted-foreground'}`} title={l.reason}>{l.reason || '—'}</td>
                      <td className={`${TD} text-right tabular-nums ${done ? 'font-semibold text-success' : b < 0 ? 'text-info' : ''}`}>{money(b)}</td>
                    </tr>
                  );
                })}
              </tbody>
              <tfoot>
                <tr className="border-t border-border bg-muted/50 font-semibold">
                  <td className={TD} colSpan={3}>{rows.length} open transaction{rows.length === 1 ? '' : 's'}</td>
                  <td className={`${TD} text-right tabular-nums`}>{money(totals.amount)}</td><td className={TD} />
                  <td className={`${TD} text-right tabular-nums`}>{money(totals.payment)}</td><td className={`${TD} text-right tabular-nums`}>{money(totals.allowance)}</td>
                  <td className={TD} /><td className={`${TD} text-right tabular-nums`}>{money(totals.balance)}</td>
                </tr>
              </tfoot>
            </table>
          </div>
        )}
        {rows && rows.length > 0 && (
          <p className="border-t border-border px-3 py-1.5 text-xs text-muted-foreground">
            {left === 0 ? 'Check fully applied.' : left > 0 ? `${money(left)} left to apply.` : `Applied ${money(-left)} more than the check. Reduce a payment.`}
            {' '}↑ ↓ pick · Enter / Tab to Payment · Enter applies{rows.some((r) => r.priorAllowance) ? ' · * allowance already on the invoice' : ''}
          </p>
        )}
      </section>
    </div>
  );
}
