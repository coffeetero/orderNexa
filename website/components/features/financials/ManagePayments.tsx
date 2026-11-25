'use client';

import { useCallback, useEffect, useState } from 'react';
import { Plus, Search, Wand2 } from 'lucide-react';
import type { CustomerOption } from '@/components/features/account/order-entry/OrderHeaderRow';
import { AccountPicker } from '@/components/features/orders/AccountPicker';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

type Status = 'APPLIED' | 'PARTIAL' | 'UNAPPLIED' | 'VOID';
interface PaymentRow {
  ar_payment_id: number; payment_number: string | null; payment_date: string; customer_id: number; customer_name: string;
  customer_number: string | null; payment_method: string | null; reference_number: string | null; amount: number;
  applied: number; unapplied: number; status: Status; void_reason: string | null;
}
interface Application {
  ar_payment_application_id: number; document_number: string; transaction_type: string; customer_name: string; transaction_date: string;
  document_amount: number; applied_amount: number; applied_at: string; reversed_at: string | null; reversal_reason: string | null;
  reversed_by_name: string | null; open: number;
}
interface CreditApplication {
  ar_credit_application_id: number; credit_document_number: string; document_number: string; applied_amount: number;
  applied_at: string; reversed_at: string | null; reversal_reason: string | null; reversed_by_name: string | null;
}
interface PaymentDetail extends PaymentRow {
  created_at: string; created_by_name: string | null; voided_at: string | null; voided_by_name: string | null; legacy: boolean;
  applications: Application[]; credit_applications: CreditApplication[];
}
interface OpenInvoice { ar_transaction_id: number; document_number: string; customer_name: string; transaction_date: string; due_date: string | null; amount: number; open: number }
interface OpenCredit { ar_transaction_id: number; document_number: string; transaction_type: string; customer_name: string; transaction_date: string; amount: number; available: number }
interface UnappliedPayment { ar_payment_id: number; payment_number: string | null; payment_date: string; unapplied: number }
interface OpenItems { invoices: OpenInvoice[]; credits: OpenCredit[]; unapplied_payments: UnappliedPayment[] }
type Amounts = Record<number, string>;

const METHODS: { value: string; label: string }[] = [
  { value: 'CHECK', label: 'Check' }, { value: 'ACH', label: 'ACH' }, { value: 'CARD', label: 'Card' }, { value: 'CASH', label: 'Cash' },
  { value: 'WIRE', label: 'Wire' }, { value: 'ZELLE', label: 'Zelle' }, { value: 'MISC', label: 'Other' },
];
const methodLabel = (v: string | null) => METHODS.find((m) => m.value === v)?.label ?? v ?? '';
const STATUS: Record<Status, { label: string; cls: string }> = {
  APPLIED: { label: 'Applied', cls: 'bg-success-soft text-success' },
  PARTIAL: { label: 'Partly applied', cls: 'bg-warning-soft text-warning' },
  UNAPPLIED: { label: 'Unapplied', cls: 'bg-info-soft text-info' },
  VOID: { label: 'Void', cls: 'bg-destructive/10 text-destructive' },
};
const Badge = ({ s }: { s: Status }) => <span className={`whitespace-nowrap rounded px-2 py-0.5 text-xs font-medium ${STATUS[s].cls}`}>{STATUS[s].label}</span>;

const money = (v: unknown) => Number(v ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const toCents = (v: unknown) => Math.round(Number(v || 0) * 100);
const sumCents = (a: Amounts) => Object.values(a).reduce((s, v) => s + Math.max(0, toCents(v)), 0);
const lines = (a: Amounts) => Object.entries(a).filter(([, v]) => toCents(v) > 0).map(([id, v]) => ({ ar_transaction_id: Number(id), amount: toCents(v) / 100 }));
/** A timestamp's day where the user is (unapply and void times). */
const day = (ts: string | null) => (ts ? new Date(ts).toLocaleDateString('en-CA') : '');
const isoDay = (offset = 0) => new Date(Date.now() + offset * 86_400_000).toLocaleDateString('en-CA');
const selectCls = 'h-10 w-full rounded-md border border-input bg-background px-2 text-sm';

async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init);
  const j = (await res.json()) as { data?: T; error?: string };
  if (!res.ok || j.error) throw new Error(j.error ?? 'Request failed');
  return j.data as T;
}
const post = <T,>(url: string, body: unknown) => call<T>(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

/** Credits and invoices with an amount box each, Auto-apply (oldest first, computed in the database) and the running totals. */
function Allocation({ items, cashCents, invAmt, setInvAmt, credAmt, setCredAmt, onAuto, busy }: {
  items: OpenItems; cashCents: number; invAmt: Amounts; setInvAmt: (a: Amounts) => void; credAmt: Amounts; setCredAmt: (a: Amounts) => void;
  onAuto: () => void; busy: boolean;
}) {
  const credits = sumCents(credAmt);
  const applied = sumCents(invAmt);
  const left = cashCents + credits - applied;
  const toggleInvoice = (inv: OpenInvoice, on: boolean) => {
    const rest = { ...invAmt };
    delete rest[inv.ar_transaction_id];
    if (!on) { setInvAmt(rest); return; }
    const room = cashCents + credits - sumCents(rest);
    const cents = room > 0 ? Math.min(toCents(inv.open), room) : toCents(inv.open);
    setInvAmt({ ...rest, [inv.ar_transaction_id]: (cents / 100).toFixed(2) });
  };

  return (
    <div className="space-y-3">
      {items.credits.length > 0 && (
        <div className="rounded-md border">
          <div className="border-b bg-muted/50 px-3 py-1.5 text-xs font-medium">Credits to use</div>
          <table className="w-full text-sm">
            <tbody>
              {items.credits.map((c) => (
                <tr key={c.ar_transaction_id} className="border-b last:border-0">
                  <td className="px-3 py-1">{c.document_number} <span className="text-xs text-muted-foreground">{c.transaction_date} · {c.customer_name}</span></td>
                  <td className="px-2 py-1 text-right tabular-nums text-muted-foreground">available {money(c.available)}</td>
                  <td className="w-32 px-2 py-1">
                    <Input type="number" min={0} step="0.01" className="h-8 text-right tabular-nums" aria-label={`Use of credit ${c.document_number}`}
                      value={credAmt[c.ar_transaction_id] ?? ''} onChange={(e) => setCredAmt({ ...credAmt, [c.ar_transaction_id]: e.target.value })} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-sm font-medium">{items.invoices.length} open invoice{items.invoices.length === 1 ? '' : 's'}</span>
        <div className="flex gap-2">
          <Button type="button" variant="outline" size="sm" onClick={() => setInvAmt({})} disabled={applied === 0}>Clear</Button>
          <Button type="button" variant="outline" size="sm" className="gap-1.5" onClick={onAuto} disabled={busy || cashCents + credits <= 0 || items.invoices.length === 0}>
            <Wand2 className="h-4 w-4" />Auto-apply oldest first
          </Button>
        </div>
      </div>
      {items.invoices.length === 0 ? (
        <p className="text-sm text-muted-foreground">No open invoices. The payment stays on account as unapplied cash.</p>
      ) : (
        <div className="max-h-[28rem] overflow-auto rounded-md border">
          <table className="w-full text-sm">
            <thead className="sticky top-0 z-10 bg-muted text-left text-xs">
              <tr>
                <th className="w-8 px-2 py-1.5" /><th className="px-2 py-1.5">Invoice</th><th className="px-2 py-1.5">Date</th>
                <th className="px-2 py-1.5">Customer</th><th className="px-2 py-1.5 text-right">Amount</th><th className="px-2 py-1.5 text-right">Open</th>
                <th className="w-32 px-2 py-1.5 text-right">Apply</th>
              </tr>
            </thead>
            <tbody>
              {items.invoices.map((inv) => {
                const v = invAmt[inv.ar_transaction_id] ?? '';
                const over = toCents(v) > toCents(inv.open);
                return (
                  <tr key={inv.ar_transaction_id} className="border-t">
                    <td className="px-2 py-1"><Checkbox checked={toCents(v) > 0} onCheckedChange={(on) => toggleInvoice(inv, on === true)} aria-label={`Pay invoice ${inv.document_number}`} /></td>
                    <td className="px-2 py-1 font-medium">{inv.document_number}</td>
                    <td className="whitespace-nowrap px-2 py-1 tabular-nums">{inv.transaction_date}</td>
                    <td className="px-2 py-1 text-muted-foreground">{inv.customer_name}</td>
                    <td className="px-2 py-1 text-right tabular-nums">{money(inv.amount)}</td>
                    <td className="px-2 py-1 text-right tabular-nums">{money(inv.open)}</td>
                    <td className="px-2 py-1">
                      <Input type="number" min={0} step="0.01" aria-label={`Apply to invoice ${inv.document_number}`} aria-invalid={over}
                        className={`h-8 text-right tabular-nums ${over ? 'border-destructive' : ''}`}
                        value={v} onChange={(e) => setInvAmt({ ...invAmt, [inv.ar_transaction_id]: e.target.value })} />
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      <div className="flex flex-wrap justify-end gap-x-6 gap-y-1 text-sm tabular-nums">
        <span>Cash {money(cashCents / 100)}</span>
        {credits > 0 && <span>Credits {money(credits / 100)}</span>}
        <span>Applied {money(applied / 100)}</span>
        <span className={`font-semibold ${left < 0 ? 'text-destructive' : ''}`}>{left < 0 ? 'Over by' : 'Left unapplied'} {money(Math.abs(left) / 100)}</span>
      </div>
      {credits > applied && <p className="text-sm text-warning">Apply at least the credits used to invoices.</p>}
    </div>
  );
}

function useAllocation(tenantId: number, customerId: number | null, setError: (e: string | null) => void) {
  const [items, setItems] = useState<OpenItems | null>(null);
  const [invAmt, setInvAmt] = useState<Amounts>({});
  const [credAmt, setCredAmt] = useState<Amounts>({});
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    setItems(null); setInvAmt({}); setCredAmt({});
    if (customerId === null) return;
    let stale = false;
    call<OpenItems>(`/api/payments/open-items?tenant_id=${tenantId}&customer_id=${customerId}`)
      .then((d) => { if (!stale) setItems(d); })
      .catch((e: Error) => { if (!stale) setError(e.message); });
    return () => { stale = true; };
  }, [tenantId, customerId, setError]);

  const auto = async (source: { customer_id: number; amount: number } | { ar_payment_id: number }) => {
    setBusy(true); setError(null);
    try {
      const r = await post<{ applications: { ar_transaction_id: number; amount: number }[] }>('/api/payments/open-items', { tenant_id: tenantId, ...source, credits: lines(credAmt) });
      setInvAmt(Object.fromEntries(r.applications.map((a) => [a.ar_transaction_id, Number(a.amount).toFixed(2)])));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  return { items, invAmt, setInvAmt, credAmt, setCredAmt, busy, auto };
}

function NewPayment({ tenantId, customers, onSaved, onCancel, onOpen }: {
  tenantId: number; customers: CustomerOption[] | null; onSaved: (d: PaymentDetail) => void; onCancel: () => void; onOpen: (id: number) => void;
}) {
  const [account, setAccount] = useState<CustomerOption | null>(null);
  const [date, setDate] = useState(isoDay());
  const [method, setMethod] = useState('CHECK');
  const [reference, setReference] = useState('');
  const [amount, setAmount] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [duplicate, setDuplicate] = useState<string | null>(null);
  const alloc = useAllocation(tenantId, account?.customer_id ?? null, setError);
  const cashCents = Math.max(0, toCents(amount));

  const save = async (allowDuplicate: boolean) => {
    if (!account) return;
    setSaving(true); setError(null); setDuplicate(null);
    try {
      const d = await post<PaymentDetail>('/api/payments', {
        tenant_id: tenantId, customer_id: account.customer_id, payment_date: date, payment_method: method, reference_number: reference,
        amount: cashCents / 100, applications: lines(alloc.invAmt), credits: lines(alloc.credAmt), allow_duplicate: allowDuplicate,
      });
      onSaved(d);
    } catch (e) {
      const msg = (e as Error).message;
      if (msg.startsWith('Duplicate reference')) setDuplicate(msg); else setError(msg);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Card><CardContent className="space-y-4 pt-6">
      <h2 className="text-lg font-medium">New payment</h2>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-[minmax(16rem,2fr)_10rem_9rem_minmax(8rem,1fr)_9rem]">
        <div><Label htmlFor="pay-cust" className="text-xs">Customer account</Label><AccountPicker customers={customers} value={account} onChange={setAccount} id="pay-cust" /></div>
        <div><Label htmlFor="pay-date" className="text-xs">Payment date</Label><Input id="pay-date" type="date" max={isoDay()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
        <div>
          <Label htmlFor="pay-method" className="text-xs">Method</Label>
          <select id="pay-method" className={selectCls} value={method} onChange={(e) => setMethod(e.target.value)}>
            {METHODS.map((m) => <option key={m.value} value={m.value}>{m.label}</option>)}
          </select>
        </div>
        <div><Label htmlFor="pay-ref" className="text-xs">{method === 'CHECK' ? 'Check number' : 'Reference'}</Label><Input id="pay-ref" value={reference} onChange={(e) => setReference(e.target.value)} /></div>
        <div><Label htmlFor="pay-amt" className="text-xs">Amount</Label><Input id="pay-amt" type="number" min={0} step="0.01" className="text-right tabular-nums" value={amount} onChange={(e) => setAmount(e.target.value)} /></div>
      </div>

      {account && !alloc.items && <p className="text-sm text-muted-foreground">Loading open invoices…</p>}
      {account && alloc.items && (
        <>
          {alloc.items.unapplied_payments.length > 0 && (
            <p className="text-sm text-info">
              Unapplied cash already on account:{' '}
              {alloc.items.unapplied_payments.map((p, i) => (
                <span key={p.ar_payment_id}>{i > 0 && ', '}
                  <button type="button" className="underline" onClick={() => onOpen(p.ar_payment_id)}>{p.payment_number ?? p.ar_payment_id}</button> ({money(p.unapplied)})
                </span>
              ))}. Open a payment to apply it.
            </p>
          )}
          <Allocation items={alloc.items} cashCents={cashCents} invAmt={alloc.invAmt} setInvAmt={alloc.setInvAmt} credAmt={alloc.credAmt} setCredAmt={alloc.setCredAmt}
            busy={alloc.busy} onAuto={() => void alloc.auto({ customer_id: account.customer_id, amount: cashCents / 100 })} />
        </>
      )}

      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      {duplicate && (
        <div role="alert" className="flex flex-wrap items-center gap-3 rounded-md bg-warning-soft p-3 text-sm">
          <span className="flex-1">{duplicate}. Save it anyway?</span>
          <Button size="sm" onClick={() => void save(true)} disabled={saving}>Save anyway</Button>
          <Button size="sm" variant="outline" onClick={() => setDuplicate(null)}>Cancel</Button>
        </div>
      )}
      <div className="flex justify-end gap-2">
        <Button variant="outline" onClick={onCancel}>Cancel</Button>
        <Button onClick={() => void save(false)} disabled={saving || !account || !alloc.items}>{saving ? 'Saving…' : 'Save payment'}</Button>
      </div>
    </CardContent></Card>
  );
}

function Reapply({ tenantId, payment, onDone, onCancel }: { tenantId: number; payment: PaymentDetail; onDone: (d: PaymentDetail) => void; onCancel: () => void }) {
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const alloc = useAllocation(tenantId, payment.customer_id, setError);
  const save = async () => {
    setSaving(true); setError(null);
    try {
      onDone(await post<PaymentDetail>(`/api/payments/${payment.ar_payment_id}`, {
        tenant_id: tenantId, action: 'apply', applications: lines(alloc.invAmt), credits: lines(alloc.credAmt),
      }));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSaving(false);
    }
  };
  return (
    <div className="space-y-3 rounded-md border p-3">
      <h3 className="text-sm font-medium">Apply to invoices</h3>
      {!alloc.items ? <p className="text-sm text-muted-foreground">Loading open invoices…</p> : (
        <Allocation items={alloc.items} cashCents={toCents(payment.unapplied)} invAmt={alloc.invAmt} setInvAmt={alloc.setInvAmt} credAmt={alloc.credAmt}
          setCredAmt={alloc.setCredAmt} busy={alloc.busy} onAuto={() => void alloc.auto({ ar_payment_id: payment.ar_payment_id })} />
      )}
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <div className="flex justify-end gap-2">
        <Button variant="outline" size="sm" onClick={onCancel}>Cancel</Button>
        <Button size="sm" onClick={() => void save()} disabled={saving || sumCents(alloc.invAmt) === 0}>{saving ? 'Applying…' : 'Apply'}</Button>
      </div>
    </div>
  );
}

function PaymentPanel({ tenantId, payment, onChanged }: { tenantId: number; payment: PaymentDetail; onChanged: (d: PaymentDetail) => void }) {
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [reason, setReason] = useState('');
  const [mode, setMode] = useState<'view' | 'apply' | 'void'>('view');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const live = payment.applications.filter((a) => !a.reversed_at);
  const liveCredits = payment.credit_applications.filter((c) => !c.reversed_at);
  const isVoid = payment.status === 'VOID';

  useEffect(() => { setPicked(new Set()); setReason(''); setMode('view'); setError(null); }, [payment]);

  const act = async (body: Record<string, unknown>) => {
    setBusy(true); setError(null);
    try {
      onChanged(await post<PaymentDetail>(`/api/payments/${payment.ar_payment_id}`, { tenant_id: tenantId, ...body }));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  const unapply = (all: boolean) => act({
    action: 'unapply', reason,
    application_ids: all ? [] : Array.from(picked).filter((k) => k.startsWith('a')).map((k) => Number(k.slice(1))),
    credit_application_ids: all ? [] : Array.from(picked).filter((k) => k.startsWith('c')).map((k) => Number(k.slice(1))),
  });
  const toggle = (key: string, on: boolean) => {
    const next = new Set(picked);
    if (on) next.add(key); else next.delete(key);
    setPicked(next);
  };

  return (
    <Card><CardContent className="space-y-4 pt-6">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-2"><span className="text-lg font-semibold">{payment.payment_number ?? payment.ar_payment_id}</span><Badge s={payment.status} /></div>
          <div className="font-medium">{payment.customer_name}{payment.customer_number ? ` (${payment.customer_number})` : ''}</div>
          <div className="text-xs text-muted-foreground">
            {payment.payment_date} · {methodLabel(payment.payment_method)}{payment.reference_number ? ` ${payment.reference_number}` : ''}
            {payment.legacy ? ' · migrated' : payment.created_by_name ? ` · entered by ${payment.created_by_name}` : ''}
          </div>
        </div>
        <div className="grid grid-cols-[auto_auto] gap-x-3 text-right text-sm tabular-nums">
          <span className="text-muted-foreground">Amount</span><span>{money(payment.amount)}</span>
          <span className="text-muted-foreground">Applied</span><span>{money(payment.applied)}</span>
          <span className="text-muted-foreground">Unapplied</span><span className="font-semibold">{money(payment.unapplied)}</span>
        </div>
      </div>
      {isVoid && (
        <p className="rounded-md bg-destructive/10 p-2 text-sm text-destructive">
          Voided {day(payment.voided_at)}{payment.voided_by_name ? ` by ${payment.voided_by_name}` : ''}: {payment.void_reason}
        </p>
      )}

      <div className="overflow-x-auto rounded-md border">
        <table className="w-full text-sm">
          <thead className="bg-muted text-left text-xs">
            <tr>
              <th className="w-8 px-2 py-1.5" /><th className="px-2 py-1.5">Invoice</th><th className="px-2 py-1.5">Date</th>
              <th className="px-2 py-1.5 text-right">Applied</th><th className="px-2 py-1.5 text-right">Open now</th>
            </tr>
          </thead>
          <tbody>
            {payment.applications.map((a) => (
              <tr key={`a${a.ar_payment_application_id}`} className={`border-t ${a.reversed_at ? 'text-muted-foreground' : ''}`}>
                <td className="px-2 py-1">
                  {!a.reversed_at && <Checkbox checked={picked.has(`a${a.ar_payment_application_id}`)} onCheckedChange={(on) => toggle(`a${a.ar_payment_application_id}`, on === true)} aria-label={`Select ${a.document_number}`} />}
                </td>
                <td className="px-2 py-1">
                  <span className={a.reversed_at ? 'line-through' : 'font-medium'}>{a.document_number}</span>
                  {a.transaction_type === 'CM' && <span className="ml-1 text-xs">(credit)</span>}
                  <span className="ml-2 text-xs text-muted-foreground">{a.customer_name}</span>
                  {a.reversed_at && <div className="text-xs">Unapplied {day(a.reversed_at)}{a.reversed_by_name ? ` by ${a.reversed_by_name}` : ''}: {a.reversal_reason}</div>}
                </td>
                <td className="whitespace-nowrap px-2 py-1 tabular-nums">{a.transaction_date}</td>
                <td className={`px-2 py-1 text-right tabular-nums ${a.reversed_at ? 'line-through' : ''}`}>{money(a.applied_amount)}</td>
                <td className="px-2 py-1 text-right tabular-nums">{money(a.open)}</td>
              </tr>
            ))}
            {payment.credit_applications.map((c) => (
              <tr key={`c${c.ar_credit_application_id}`} className={`border-t ${c.reversed_at ? 'text-muted-foreground' : ''}`}>
                <td className="px-2 py-1">
                  {!c.reversed_at && <Checkbox checked={picked.has(`c${c.ar_credit_application_id}`)} onCheckedChange={(on) => toggle(`c${c.ar_credit_application_id}`, on === true)} aria-label={`Select credit ${c.credit_document_number}`} />}
                </td>
                <td className="px-2 py-1" colSpan={2}>
                  <span className={c.reversed_at ? 'line-through' : 'font-medium'}>{c.document_number}</span>
                  <span className="ml-2 text-xs text-muted-foreground">credit {c.credit_document_number}</span>
                  {c.reversed_at && <div className="text-xs">Unapplied {day(c.reversed_at)}{c.reversed_by_name ? ` by ${c.reversed_by_name}` : ''}: {c.reversal_reason}</div>}
                </td>
                <td className={`px-2 py-1 text-right tabular-nums ${c.reversed_at ? 'line-through' : ''}`}>{money(c.applied_amount)}</td>
                <td />
              </tr>
            ))}
            {payment.applications.length + payment.credit_applications.length === 0 && (
              <tr><td colSpan={5} className="px-2 py-3 text-sm text-muted-foreground">Nothing applied yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {!isVoid && mode === 'view' && (
        <div className="space-y-3">
          {live.length + liveCredits.length > 0 && (
            <div className="grid gap-2 sm:grid-cols-[1fr_auto_auto] sm:items-end">
              <div><Label htmlFor="unapply-reason" className="text-xs">Reason for unapplying (optional)</Label><Input id="unapply-reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Applied to the wrong invoice" /></div>
              <Button variant="outline" onClick={() => void unapply(false)} disabled={busy || picked.size === 0}>Unapply selected</Button>
              <Button variant="outline" onClick={() => void unapply(true)} disabled={busy}>Unapply all</Button>
            </div>
          )}
          <div className="flex flex-wrap justify-end gap-2">
            {payment.unapplied > 0 && <Button onClick={() => setMode('apply')}>Apply unapplied cash</Button>}
            <Button variant="outline" className="text-destructive" onClick={() => setMode('void')}>Void payment…</Button>
          </div>
        </div>
      )}
      {mode === 'apply' && <Reapply tenantId={tenantId} payment={payment} onDone={onChanged} onCancel={() => setMode('view')} />}
      {mode === 'void' && (
        <div className="space-y-2 rounded-md border border-destructive/40 p-3">
          <p className="text-sm">Voiding unapplies everything on this payment and keeps it on file as void. Use it for a bounced check or a payment entered in error.</p>
          <div className="grid gap-2 sm:grid-cols-[1fr_auto_auto] sm:items-end">
            <div><Label htmlFor="void-reason" className="text-xs">Reason</Label><Input id="void-reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. NSF check returned by the bank" autoFocus /></div>
            <Button variant="outline" onClick={() => setMode('view')}>Cancel</Button>
            <Button variant="destructive" onClick={() => void act({ action: 'void', reason })} disabled={busy || reason.trim() === ''}>Void payment</Button>
          </div>
        </div>
      )}
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    </CardContent></Card>
  );
}

/** Financials › Manage Payments: search payments, enter a payment and apply it, unapply / reapply, void. Rules live in the database. */
export function ManagePayments({ tenantId, initialPaymentId }: { tenantId: number; initialPaymentId: number | null }) {
  const [customers, setCustomers] = useState<CustomerOption[] | null>(null);
  const [account, setAccount] = useState<CustomerOption | null>(null);
  const [from, setFrom] = useState(isoDay(-30));
  const [to, setTo] = useState(isoDay());
  const [method, setMethod] = useState('');
  const [reference, setReference] = useState('');
  const [amount, setAmount] = useState('');
  const [unappliedOnly, setUnappliedOnly] = useState(false);
  const [rows, setRows] = useState<PaymentRow[] | null>(null);
  const [truncated, setTruncated] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [detail, setDetail] = useState<PaymentDetail | null>(null);
  const [entering, setEntering] = useState(false);

  useEffect(() => {
    call<CustomerOption[]>(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`)
      .then(setCustomers).catch((e: Error) => { setCustomers([]); setError(e.message); });
  }, [tenantId]);

  const search = useCallback(async () => {
    setBusy(true); setError(null);
    const qs = new URLSearchParams({ tenant_id: String(tenantId) });
    if (account) qs.set('customer_id', String(account.customer_id));
    if (from) qs.set('date_from', from);
    if (to) qs.set('date_to', to);
    if (method) qs.set('payment_method', method);
    if (reference.trim()) qs.set('reference', reference.trim());
    if (amount.trim()) qs.set('amount', amount.trim());
    if (unappliedOnly) qs.set('unapplied_only', '1');
    try {
      const r = await call<{ rows: PaymentRow[]; truncated: boolean }>(`/api/payments?${qs}`);
      setRows(r.rows); setTruncated(r.truncated);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }, [tenantId, account, from, to, method, reference, amount, unappliedOnly]);

  const open = useCallback(async (id: number) => {
    setError(null); setEntering(false);
    try { setDetail(await call<PaymentDetail>(`/api/payments?tenant_id=${tenantId}&id=${id}`)); } catch (e) { setError((e as Error).message); }
  }, [tenantId]);

  // first load: the last 30 days, and the payment named in the link (health checks link here)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { void search(); if (initialPaymentId) void open(initialPaymentId); }, []);

  const changed = (d: PaymentDetail, text?: string) => {
    setDetail(d); setEntering(false); setNotice(text ?? null);
    setRows((list) => (list ? list.map((r) => (r.ar_payment_id === d.ar_payment_id ? { ...r, ...d } : r)) : list));
  };

  return (
    <div className="mx-auto max-w-[110rem] space-y-4 p-2 sm:p-3">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">Payment History</h1>
          <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
            Enter customer payments and apply them to open invoices. What is not applied stays on account. Payments are never deleted: unapply or void them.
          </p>
        </div>
        {!entering && <Button className="gap-1.5" onClick={() => { setEntering(true); setNotice(null); }}><Plus className="h-4 w-4" />New payment</Button>}
      </div>

      {entering ? (
        <NewPayment tenantId={tenantId} customers={customers} onCancel={() => setEntering(false)} onOpen={(id) => void open(id)}
          onSaved={(d) => { changed(d, `Payment ${d.payment_number} saved.`); void search(); }} />
      ) : (
        <Card><CardContent className="pt-6">
          <form className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 lg:items-end 2xl:grid-cols-[minmax(16rem,2fr)_9.5rem_9.5rem_8rem_minmax(7rem,1fr)_8rem_auto_auto]"
            onSubmit={(e) => { e.preventDefault(); void search(); }}>
            <div><Label htmlFor="f-cust" className="text-xs">Customer account</Label><AccountPicker customers={customers} value={account} onChange={setAccount} id="f-cust" /></div>
            <div><Label htmlFor="f-from" className="text-xs">From</Label><Input id="f-from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></div>
            <div><Label htmlFor="f-to" className="text-xs">To</Label><Input id="f-to" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></div>
            <div>
              <Label htmlFor="f-method" className="text-xs">Method</Label>
              <select id="f-method" className={selectCls} value={method} onChange={(e) => setMethod(e.target.value)}>
                <option value="">All</option>
                {METHODS.map((m) => <option key={m.value} value={m.value}>{m.label}</option>)}
              </select>
            </div>
            <div><Label htmlFor="f-ref" className="text-xs">Reference or number</Label><Input id="f-ref" value={reference} onChange={(e) => setReference(e.target.value)} /></div>
            <div><Label htmlFor="f-amt" className="text-xs">Amount</Label><Input id="f-amt" type="number" step="0.01" className="text-right" value={amount} onChange={(e) => setAmount(e.target.value)} /></div>
            <label className="flex h-10 items-center gap-2 text-sm"><Checkbox checked={unappliedOnly} onCheckedChange={(v) => setUnappliedOnly(v === true)} />Unapplied only</label>
            <Button type="submit" className="gap-1.5" disabled={busy}><Search className="h-4 w-4" />{busy ? 'Searching…' : 'Search'}</Button>
          </form>
        </CardContent></Card>
      )}
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      {notice && <p role="status" className="text-sm text-success">{notice}</p>}

      <div className={`grid gap-4 ${detail ? '2xl:grid-cols-[minmax(0,1fr)_minmax(0,34rem)]' : ''}`}>
        {!entering && (
          <Card className="min-w-0"><CardContent className="space-y-2 pt-6">
            <div className="text-sm text-muted-foreground">
              {rows === null ? 'Loading…' : `${rows.length} payment${rows.length === 1 ? '' : 's'}${truncated ? ' (first 500; narrow the search)' : ''}`}
              {rows && rows.length > 0 && ` · ${money(rows.filter((r) => r.status !== 'VOID').reduce((s, r) => s + toCents(r.amount), 0) / 100)} received`}
            </div>
            {rows && rows.length > 0 && (
              <div className="max-h-[40rem] overflow-auto rounded-md border">
                <table className="w-full text-sm">
                  <thead className="sticky top-0 z-10 bg-muted text-left text-xs">
                    <tr>
                      <th className="px-2 py-1.5">Date</th><th className="px-2 py-1.5">Payment</th><th className="px-2 py-1.5">Customer</th>
                      <th className="px-2 py-1.5">Method</th><th className="px-2 py-1.5 text-right">Amount</th>
                      <th className="px-2 py-1.5 text-right">Unapplied</th><th className="px-2 py-1.5">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((r) => (
                      <tr key={r.ar_payment_id} onClick={() => void open(r.ar_payment_id)}
                        className={`cursor-pointer border-t hover:bg-muted/60 ${detail?.ar_payment_id === r.ar_payment_id ? 'bg-muted' : ''}`}>
                        <td className="whitespace-nowrap px-2 py-1 tabular-nums">{r.payment_date}</td>
                        <td className="whitespace-nowrap px-2 py-1">
                          <button type="button" className="font-medium hover:underline" onClick={(e) => { e.stopPropagation(); void open(r.ar_payment_id); }}>{r.payment_number ?? r.ar_payment_id}</button>
                        </td>
                        <td className="max-w-[14rem] truncate px-2 py-1" title={r.customer_name}>{r.customer_name}</td>
                        <td className="whitespace-nowrap px-2 py-1">{methodLabel(r.payment_method)}{r.reference_number ? <span className="text-muted-foreground"> {r.reference_number}</span> : null}</td>
                        <td className={`px-2 py-1 text-right tabular-nums ${r.status === 'VOID' ? 'line-through text-muted-foreground' : ''}`}>{money(r.amount)}</td>
                        <td className="px-2 py-1 text-right tabular-nums">{r.status === 'VOID' ? '' : money(r.unapplied)}</td>
                        <td className="px-2 py-1"><Badge s={r.status} /></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            {rows && rows.length === 0 && <p className="text-sm text-muted-foreground">No payments match.</p>}
          </CardContent></Card>
        )}
        {detail && <div className="min-w-0"><PaymentPanel tenantId={tenantId} payment={detail} onChanged={(d) => changed(d)} /></div>}
      </div>
    </div>
  );
}
