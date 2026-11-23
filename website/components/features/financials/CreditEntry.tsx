'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

interface InvoiceLine {
  ar_transaction_line_id: number;
  source_type: string;
  order_number: string | null;
  department_event: string | null;
  item_description: string | null;
  quantity: number;
  unit_price: number;
  amount: number;
  shipped_quantity: number | null;
  credited_quantity: number;
}
interface Invoice {
  ar_transaction_id: number;
  document_number: string;
  status: string;
  customer_name: string;
  delivery_date: string;
  amount: number;
  recognized_amount: number;
  credited_amount: number;
  lines: InvoiceLine[];
  credits: { document_number: string; amount: number; reason: string | null }[];
}

const money = (v: number) => Number(v).toFixed(2);

function InvoiceCard({ invoice, tenantId, onCredited }: { invoice: Invoice; tenantId: number; onCredited: (message: string) => void }) {
  const [qty, setQty] = useState<Record<number, string>>({});
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const lines = Object.entries(qty).filter(([, v]) => Number(v) > 0);

  const create = async () => {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/invoices/credit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tenant_id: tenantId, ar_transaction_id: invoice.ar_transaction_id, reason,
          lines: lines.map(([id, v]) => ({ ar_transaction_line_id: Number(id), quantity: Number(v) })),
        }),
      });
      const json = (await res.json()) as { data?: { document_number: string; amount: number }; error?: string };
      if (!res.ok || json.error || !json.data) throw new Error(json.error ?? 'Could not create the credit memo');
      onCredited(`Credit memo ${json.data.document_number} created for ${money(json.data.amount)}.`);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card><CardContent className="space-y-3 pt-6">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <span className="text-lg font-semibold">{invoice.document_number}</span>
          <span className="ml-2 font-medium">{invoice.customer_name}</span>
          <span className="ml-2 text-xs text-muted-foreground">deliver {invoice.delivery_date} · {invoice.status}</span>
        </div>
        <div className="text-xs text-muted-foreground tabular-nums">
          Invoice {money(invoice.amount)} · receivable {money(invoice.recognized_amount)} · credited {money(invoice.credited_amount)}
        </div>
      </div>

      <div>
        <div className="grid grid-cols-[1fr_4rem_4.5rem_4.5rem_5rem_6rem] gap-2 border-b pb-1 text-xs font-medium text-muted-foreground">
          <span>Order / item</span><span className="text-right">Invoiced</span><span className="text-right">Delivered</span>
          <span className="text-right">Credited</span><span className="text-right">Price</span><span className="text-right">Credit qty</span>
        </div>
        {invoice.lines.map((l) => (
          <div key={l.ar_transaction_line_id} className="grid grid-cols-[1fr_4rem_4.5rem_4.5rem_5rem_6rem] items-center gap-2 border-b py-1.5 text-sm">
            <span>
              {l.item_description} <span className="text-xs text-muted-foreground">{l.order_number}{l.department_event ? ` · ${l.department_event}` : ''}</span>
            </span>
            <span className="text-right tabular-nums">{l.quantity}</span>
            <span className="text-right tabular-nums">{l.shipped_quantity ?? '—'}</span>
            <span className="text-right tabular-nums">{l.credited_quantity}</span>
            <span className="text-right tabular-nums">{money(l.unit_price)}</span>
            <Input
              type="number" min={0} step="any" className="h-8 text-right tabular-nums" aria-label={`Credit quantity for ${l.item_description}`}
              value={qty[l.ar_transaction_line_id] ?? ''}
              onChange={(e) => setQty((q) => ({ ...q, [l.ar_transaction_line_id]: e.target.value }))}
            />
          </div>
        ))}
      </div>

      {invoice.credits.length > 0 && (
        <p className="text-xs text-muted-foreground">
          Earlier credits: {invoice.credits.map((c) => `${c.document_number} (${money(c.amount)}${c.reason ? `, ${c.reason}` : ''})`).join('; ')}
        </p>
      )}

      <div className="grid grid-cols-1 items-end gap-3 sm:grid-cols-[1fr_auto]">
        <div>
          <Label className="text-xs">Reason</Label>
          <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Kitchen short 2 breads" />
        </div>
        <Button onClick={create} disabled={busy || lines.length === 0}>{busy ? 'Creating…' : 'Create credit memo'}</Button>
      </div>
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    </CardContent></Card>
  );
}

export function CreditEntry({ tenantId }: { tenantId: number }) {
  const [q, setQ] = useState('');
  const [searched, setSearched] = useState('');
  const [invoices, setInvoices] = useState<Invoice[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const find = async (term = q) => {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/invoices/lookup?tenant_id=${tenantId}&q=${encodeURIComponent(term.trim())}`);
      const json = (await res.json()) as { data?: { invoices: Invoice[] }; error?: string };
      if (!res.ok || json.error) throw new Error(json.error ?? 'Lookup failed');
      setInvoices(json.data?.invoices ?? []);
      setSearched(term.trim());
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="mx-auto max-w-5xl space-y-6 p-2 sm:p-3">
      <div>
        <h1 className="text-2xl font-semibold">Enter credits</h1>
        <p className="text-sm text-muted-foreground">
          Find an invoice by its invoice number or by any order number on it, then credit what the customer did not receive.
          Printed invoices are never edited; a numbered credit memo is created instead.
        </p>
      </div>

      <Card><CardContent className="pt-6">
        <form className="grid grid-cols-1 items-end gap-3 sm:grid-cols-[1fr_auto]" onSubmit={(e) => { e.preventDefault(); void find(); }}>
          <div>
            <Label className="text-xs">Invoice number or order number</Label>
            <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="INV-001000 or 0115-1087" autoFocus />
          </div>
          <Button type="submit" disabled={busy || q.trim() === ''}>{busy ? 'Searching…' : 'Find'}</Button>
        </form>
        {error && <p role="alert" className="mt-3 text-sm text-destructive">{error}</p>}
        {message && <p role="status" className="mt-3 text-sm text-success">{message}</p>}
      </CardContent></Card>

      {invoices !== null && invoices.length === 0 && (
        <p className="text-sm text-muted-foreground">No issued invoice found for “{searched}”. Draft and cancelled invoices cannot be credited.</p>
      )}
      {invoices?.map((inv) => (
        <InvoiceCard
          key={`${inv.ar_transaction_id}-${inv.credits.length}`}
          invoice={inv} tenantId={tenantId}
          onCredited={(text) => { setMessage(text); void find(searched); }}
        />
      ))}
    </div>
  );
}
