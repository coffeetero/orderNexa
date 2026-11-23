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
      if (!res.ok || json.error) throw new Error(json.error ?? 'Processing failed');
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
        <h1 className="text-2xl font-semibold">Process run</h1>
        <p className="text-sm text-muted-foreground">
          Locks the runs in the date range and prepares shipments and draft invoices. Nothing is printed and no invoice
          numbers are used until the Packaging List is printed. You can process a run again until a delivery has shipped.
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
          <Button onClick={run} disabled={busy || !from || !to}>{busy ? 'Processing…' : 'Process'}</Button>
        </div>
        {error && <p role="alert" className="mt-3 text-sm text-destructive">{error}</p>}
      </CardContent></Card>

      {results && (
        <Card><CardContent className="pt-6">
          <h2 className="mb-2 text-lg font-medium">Processed {results.length} run{results.length === 1 ? '' : 's'}</h2>
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
            </div>
          ))}
        </CardContent></Card>
      )}
    </div>
  );
}
