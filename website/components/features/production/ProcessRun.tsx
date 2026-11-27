'use client';

import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

interface Defaults {
  from_date: string;
  to_date: string;
  production_codes: { value: string; label: string }[];
}
interface RunResult {
  production_run_id: number;
  production_date: string;
  production_code: string;
  orders: number;
  shipments: number;
  invoices: number;
  orders_waiting_approval?: number;
  memos?: number;
}

export function ProcessRun({ tenantId }: { tenantId: number }) {
  const [codes, setCodes] = useState<Defaults['production_codes']>([]);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [results, setResults] = useState<RunResult[] | null>(null);

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

  const run = async () => {
    setBusy(true);
    setError(null);
    setResults(null);
    try {
      const res = await fetch('/api/production/process', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tenant_id: tenantId, from, to, production_code: code || null }),
      });
      const json = (await res.json()) as { data?: RunResult[]; error?: string };
      if (!res.ok || json.error) throw new Error(json.error ?? 'Posting failed');
      setResults(json.data ?? []);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="mx-auto max-w-4xl space-y-6 p-2 sm:p-3">
      <div>
        <h1 className="text-2xl font-semibold">Post Orders to Production</h1>
        <p className="text-sm text-muted-foreground">
          Locks the runs in the date range and prepares shipments and draft invoices. Post as often as you like (for
          example once most orders are in, and again later) until a delivery has shipped. No invoice numbers are used until
          Post Orders to AR. Changes to orders already posted to AR become debit or credit memos on their invoice.
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
          <Button onClick={run} disabled={busy || !from || !to}>{busy ? 'Posting…' : 'Post to Production'}</Button>
        </div>
        {error && <p role="alert" className="mt-3 text-sm text-destructive">{error}</p>}
      </CardContent></Card>

      {results && (
        <Card><CardContent className="pt-6">
          <h2 className="mb-2 text-lg font-medium">Posted {results.length} run{results.length === 1 ? '' : 's'} to production</h2>
          <div className="grid grid-cols-[1fr_6rem_6rem_6rem_6rem] gap-2 border-b pb-1 text-xs font-medium text-muted-foreground">
            <span>Production</span><span className="text-right">Orders</span><span className="text-right">Shipments</span><span className="text-right">Invoices</span><span />
          </div>
          {results.map((r) => (
            <div key={r.production_run_id} className="grid grid-cols-[1fr_6rem_6rem_6rem_6rem] gap-2 border-b py-2 text-sm">
              <span>{r.production_date} · {r.production_code}</span>
              <span className="text-right tabular-nums">{r.orders}</span>
              <span className="text-right tabular-nums">{r.shipments}</span>
              <span className="text-right tabular-nums">{r.invoices}</span>
              <span />
              {(r.memos ?? 0) > 0 && (
                <span className="col-span-5 text-xs text-amber-700 dark:text-amber-400">
                  {r.memos} debit/credit memo{r.memos === 1 ? '' : 's'} added to invoices already posted to AR. Print those invoices again.
                </span>
              )}
              {(r.orders_waiting_approval ?? 0) > 0 && (
                <span className="col-span-5 text-xs text-amber-700 dark:text-amber-400">
                  {r.orders_waiting_approval} imported order{r.orders_waiting_approval === 1 ? ' is' : 's are'} waiting for approval and {r.orders_waiting_approval === 1 ? 'was' : 'were'} left out (Orders › Import Orders).
                </span>
              )}
            </div>
          ))}
        </CardContent></Card>
      )}
    </div>
  );
}
