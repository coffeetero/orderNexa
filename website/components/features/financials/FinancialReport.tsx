'use client';

import { useEffect, useRef, useState } from 'react';
import { Download, Play, Printer, Save } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { CustomerPicker, type PickAccount } from './CustomerPicker';
import type { ReportKind } from '@/lib/reports/financial';

const CONFIG: Record<ReportKind, { title: string; help: string }> = {
  ar: { title: 'AR Open Balances', help: 'Unpaid invoices and credits for the selected customers, as of a date.' },
  aging: { title: 'AR Aging Report', help: 'What each selected customer owes, by how far past due it is.' },
  statements: { title: 'Customer Statements', help: 'One statement per selected customer. Saving keeps each customer’s statement with its own as-of date.' },
  sales: { title: 'Sales Reports', help: 'Invoiced sales, credits and items for the selected customers over a date range.' },
  forecast: { title: 'Revenue Forecasting', help: 'Projects revenue from each customer’s sales history, at its weekly average.' },
};

const today = () => new Date().toLocaleDateString('en-CA');
const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toLocaleDateString('en-CA');

interface Result { title: string; fileName: string; url: string }

export function FinancialReport({ tenantId, kind }: { tenantId: number; kind: ReportKind }) {
  const cfg = CONFIG[kind];
  const [accounts, setAccounts] = useState<PickAccount[] | null>(null);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [asOf, setAsOf] = useState(today());
  const [from, setFrom] = useState(kind === 'sales' ? daysAgo(30) : daysAgo(90));
  const [to, setTo] = useState(today());
  const [lookback, setLookback] = useState('8');
  const [horizon, setHorizon] = useState('4');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null);
  const [result, setResult] = useState<Result | null>(null);
  const frame = useRef<HTMLIFrameElement>(null);

  // AR Open Balances, AR Aging and Sales list only active accounts that have an invoice in the period (up to the as-of date, or from-to).
  const needsInvoices = kind === 'ar' || kind === 'aging' || kind === 'sales';
  const periodFrom = kind === 'sales' ? from : '';
  const periodTo = kind === 'sales' ? to : asOf;

  useEffect(() => {
    const qs = new URLSearchParams({ tenant_id: String(tenantId) });
    if (needsInvoices) {
      qs.set('with_invoices', '1');
      if (periodFrom) qs.set('from', periodFrom);
      if (periodTo) qs.set('to', periodTo);
    }
    let live = true;
    fetch(`/api/reports/financial?${qs}`)
      .then((r) => r.json())
      .then((j: { data?: PickAccount[]; error?: string }) => {
        if (!live) return;
        if (j.error) { setMessage({ text: j.error, error: true }); return; }
        const list = j.data ?? [];
        setAccounts(list);
        setSelected((prev) => new Set(Array.from(prev).filter((id) => list.some((a) => a.customer_id === id))));
      })
      .catch((e: Error) => live && setMessage({ text: e.message, error: true }));
    return () => { live = false; };
  }, [tenantId, needsInvoices, periodFrom, periodTo]);

  useEffect(() => () => { if (result) URL.revokeObjectURL(result.url); }, [result]);

  async function run(save: boolean) {
    setBusy(true);
    setMessage(null);
    try {
      const res = await fetch('/api/reports/financial', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tenant_id: tenantId, kind, customer_ids: Array.from(selected), as_of: asOf, from, to,
          lookback_weeks: Number(lookback), horizon_weeks: Number(horizon), save,
        }),
      });
      const j = (await res.json()) as { data?: { title: string; file_name: string; pdf_base64: string; saved_ids: number[] }; error?: string };
      if (!res.ok || !j.data) throw new Error(j.error ?? 'The report could not be created');
      const bytes = Uint8Array.from(atob(j.data.pdf_base64), (c) => c.charCodeAt(0));
      setResult({ title: j.data.title, fileName: j.data.file_name, url: URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' })) });
      if (save) setMessage({ text: j.data.saved_ids.length === 1 ? 'Saved to documents.' : `Saved ${j.data.saved_ids.length} documents.`, error: false });
    } catch (e) {
      setMessage({ text: (e as Error).message, error: true });
    } finally {
      setBusy(false);
    }
  }

  const none = selected.size === 0;
  return (
    <div className="mx-auto max-w-5xl space-y-4 p-2 sm:p-3">
      <div>
        <h1 className="text-2xl font-semibold">{cfg.title}</h1>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">{cfg.help}</p>
      </div>

      <Card><CardContent className="space-y-4 pt-6">
        <div className="flex flex-wrap items-end gap-4">
          {kind === 'sales' ? (
            <>
              <div><Label htmlFor="from" className="text-xs">From</Label><Input id="from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></div>
              <div><Label htmlFor="to" className="text-xs">To</Label><Input id="to" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></div>
            </>
          ) : (
            <>
              {kind === 'statements' && <div><Label htmlFor="from" className="text-xs">Statement from</Label><Input id="from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></div>}
              <div><Label htmlFor="asof" className="text-xs">As of date</Label><Input id="asof" type="date" value={asOf} onChange={(e) => setAsOf(e.target.value)} /></div>
            </>
          )}
          {kind === 'forecast' && (
            <>
              <div><Label htmlFor="lb" className="text-xs">Weeks of history</Label><Input id="lb" type="number" min={2} max={104} value={lookback} onChange={(e) => setLookback(e.target.value)} className="w-28" /></div>
              <div><Label htmlFor="hz" className="text-xs">Weeks to project</Label><Input id="hz" type="number" min={1} max={52} value={horizon} onChange={(e) => setHorizon(e.target.value)} className="w-28" /></div>
            </>
          )}
          <Button onClick={() => run(false)} disabled={busy || none} className="ml-auto gap-1.5"><Play className="h-4 w-4" />{busy ? 'Running…' : 'Run'}</Button>
        </div>
        {needsInvoices && <p className="text-xs text-muted-foreground">Only active customers with an invoice {kind === 'sales' ? 'in this period' : 'on or before the as-of date'} are listed.</p>}
        {accounts === null ? <p className="text-sm text-muted-foreground">Loading customers…</p> : <CustomerPicker accounts={accounts} selected={selected} onChange={setSelected} />}
        {message && <p role="status" className={`text-sm ${message.error ? 'text-destructive' : 'text-foreground'}`}>{message.text}</p>}
      </CardContent></Card>

      {result && (
        <Card><CardContent className="space-y-3 pt-6">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="mr-auto text-lg font-medium">{result.title}</h2>
            <Button asChild variant="outline" size="sm" className="gap-1.5"><a href={result.url} download={result.fileName}><Download className="h-4 w-4" />Download</a></Button>
            <Button variant="outline" size="sm" className="gap-1.5" onClick={() => frame.current?.contentWindow?.print()}><Printer className="h-4 w-4" />Print</Button>
            <Button size="sm" className="gap-1.5" onClick={() => run(true)} disabled={busy}><Save className="h-4 w-4" />Save to documents</Button>
          </div>
          <iframe ref={frame} src={result.url} title={result.title} className="h-[70vh] w-full rounded-md border" />
        </CardContent></Card>
      )}
    </div>
  );
}
