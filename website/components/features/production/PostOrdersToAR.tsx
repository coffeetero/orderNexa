'use client';

import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { money } from '@/lib/pdf/kit';

interface Defaults {
  from_date: string;
  to_date: string;
  production_codes: { value: string; label: string }[];
}
interface PostedInvoice {
  ar_transaction_id: number;
  document_number: string;
  customer_name: string;
  production_date: string;
  production_code: string;
  amount: number;
}

/** Post Orders to AR: gives the draft invoices their numbers (the only step that does). May run ahead, e.g. Friday for Saturday to Monday. */
export function PostOrdersToAR({ tenantId }: { tenantId: number }) {
  const [codes, setCodes] = useState<Defaults['production_codes']>([]);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [posted, setPosted] = useState<PostedInvoice[] | null>(null);

  useEffect(() => {
    fetch(`/api/production/defaults?tenant_id=${tenantId}`)
      .then((r) => r.json())
      .then((json: { data?: Defaults; error?: string }) => {
        if (json.error || !json.data) throw new Error(json.error ?? 'Could not load defaults');
        setFrom(json.data.from_date);
        setTo(json.data.to_date);
        setCodes(json.data.production_codes);
      })
      .catch((e: Error) => setError(e.message));
  }, [tenantId]);

  const post = async () => {
    setBusy(true);
    setError(null);
    setPosted(null);
    try {
      const res = await fetch('/api/production/post-to-ar', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tenant_id: tenantId, from, to, production_code: code || null }),
      });
      const json = (await res.json()) as { data?: { numbered: number; invoices: PostedInvoice[] }; error?: string };
      if (!res.ok || json.error) throw new Error(json.error ?? 'Posting failed');
      setPosted(json.data?.invoices ?? []);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const codeLabel = (v: string) => codes.find((c) => c.value === v)?.label ?? v;

  return (
    <div className="mx-auto max-w-4xl space-y-6 p-2 sm:p-3">
      <div>
        <h1 className="text-2xl font-semibold">Post Orders to AR</h1>
        <p className="text-sm text-muted-foreground">
          Gives the draft invoices of the runs in the date range their invoice numbers. This is the only step that numbers
          invoices. Standing orders for those dates must be posted first, and the orders are posted to production again so
          the invoices match them. Later changes to these orders become debit or credit memos on the same invoice.
        </p>
      </div>

      <Card><CardContent className="pt-6">
        <div className="grid grid-cols-1 items-end gap-3 sm:grid-cols-[10rem_10rem_12rem_auto]">
          <div>
            <Label className="text-xs">From production date</Label>
            <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div>
            <Label className="text-xs">To production date</Label>
            <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </div>
          <div>
            <Label className="text-xs">Production code</Label>
            <select
              className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm"
              value={code}
              onChange={(e) => setCode(e.target.value)}
            >
              <option value="">All codes</option>
              {codes.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          </div>
          <Button onClick={post} disabled={busy || !from || !to}>{busy ? 'Posting…' : 'Post to AR'}</Button>
        </div>
        {error && <p role="alert" className="mt-3 text-sm text-destructive">{error}</p>}
      </CardContent></Card>

      {posted && (
        <Card><CardContent className="pt-6">
          <h2 className="mb-2 text-lg font-medium">
            {posted.length === 0 ? 'No draft invoices to post for these dates.' : `Posted ${posted.length} invoice${posted.length === 1 ? '' : 's'}`}
          </h2>
          {posted.length > 0 && (
            <>
              <div className="grid grid-cols-[8rem_1fr_10rem_7rem] gap-2 border-b pb-1 text-xs font-medium text-muted-foreground">
                <span>Invoice</span><span>Customer</span><span>Production</span><span className="text-right">Amount</span>
              </div>
              {posted.map((r) => (
                <div key={r.ar_transaction_id} className="grid grid-cols-[8rem_1fr_10rem_7rem] gap-2 border-b py-2 text-sm">
                  <span className="tabular-nums">{r.document_number}</span>
                  <span className="truncate">{r.customer_name}</span>
                  <span>{r.production_date} · {codeLabel(r.production_code)}</span>
                  <span className="text-right tabular-nums">{money(r.amount)}</span>
                </div>
              ))}
            </>
          )}
        </CardContent></Card>
      )}
    </div>
  );
}
