'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

export type ReportKind = 'bakers' | 'labels' | 'packaging' | 'invoices' | 'delivery';

interface Defaults {
  from_date: string;
  to_date: string;
  production_codes: { value: string; label: string }[];
}
interface CustomerRow {
  customer_id: number;
  customer_name: string;
  customer_number: string | null;
  document_count: number;
}

interface Props {
  tenantId: number;
  report: ReportKind;
  title: string;
  description: string;
  /** When set, the user first lists customers and ticks the ones to include (none are ticked by default). */
  customerBasis?: 'ORDER' | 'INVOICE' | 'PRINT';
  customerColumnLabel?: string;
}

export function ReportRunner({ tenantId, report, title, description, customerBasis, customerColumnLabel }: Props) {
  const [codes, setCodes] = useState<Defaults['production_codes']>([]);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [code, setCode] = useState('');
  const [customers, setCustomers] = useState<CustomerRow[] | null>(null);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const lastUrl = useRef<string | null>(null);

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

  useEffect(() => () => { if (lastUrl.current) URL.revokeObjectURL(lastUrl.current); }, []);

  const resetSelection = useCallback(() => {
    setCustomers(null);
    setSelected(new Set());
  }, []);

  const findCustomers = async () => {
    setBusy(true);
    setError(null);
    try {
      const qs = new URLSearchParams({ tenant_id: String(tenantId), from, to, basis: customerBasis ?? 'ORDER' });
      if (code) qs.set('production_code', code);
      const res = await fetch(`/api/reports/customers?${qs.toString()}`);
      const json = (await res.json()) as { data?: CustomerRow[]; error?: string };
      if (!res.ok || json.error) throw new Error(json.error ?? 'Could not load customers');
      setCustomers(json.data ?? []);
      setSelected(new Set());
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const run = async () => {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/reports/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          report, tenant_id: tenantId, from, to, production_code: code || null, customer_ids: Array.from(selected),
        }),
      });
      if (!res.ok) {
        const json = (await res.json()) as { error?: string };
        throw new Error(json.error ?? 'Report failed');
      }
      const url = URL.createObjectURL(await res.blob());
      if (lastUrl.current) URL.revokeObjectURL(lastUrl.current);
      lastUrl.current = url;
      setPdfUrl(url);
      // The Packaging List numbers invoices when printed, so the list of customers is now stale.
      if (report === 'packaging') resetSelection();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const allSelected = customers !== null && customers.length > 0 && selected.size === customers.length;
  const someSelected = selected.size > 0 && !allSelected;
  const toggleAll = (checked: boolean) =>
    setSelected(checked && customers ? new Set(customers.map((c) => c.customer_id)) : new Set());
  const toggleOne = (id: number, checked: boolean) =>
    setSelected((prev) => {
      const next = new Set(prev);
      if (checked) next.add(id); else next.delete(id);
      return next;
    });

  const needsList = customerBasis !== undefined;
  const canFind = !busy && Boolean(from && to);
  const canRun = !busy && Boolean(from && to) && (!needsList || selected.size > 0);

  return (
    <div className="mx-auto max-w-5xl space-y-6 p-2 sm:p-3">
      <div>
        <h1 className="text-2xl font-semibold">{title}</h1>
        <p className="text-sm text-muted-foreground">{description}</p>
      </div>

      <Card><CardContent className="pt-6">
        <div className="grid grid-cols-1 items-end gap-3 sm:grid-cols-[10rem_10rem_12rem_auto]">
          <div>
            <Label className="text-xs">From production date</Label>
            <Input type="date" value={from} onChange={(e) => { setFrom(e.target.value); resetSelection(); }} />
          </div>
          <div>
            <Label className="text-xs">To production date</Label>
            <Input type="date" value={to} onChange={(e) => { setTo(e.target.value); resetSelection(); }} />
          </div>
          <div>
            <Label className="text-xs">Production code</Label>
            <select
              className="h-9 w-full rounded-md border border-input bg-background px-2 text-sm"
              value={code}
              onChange={(e) => { setCode(e.target.value); resetSelection(); }}
            >
              <option value="">All codes</option>
              {codes.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          </div>
          {needsList ? (
            <Button variant="outline" onClick={findCustomers} disabled={!canFind}>Find customers</Button>
          ) : (
            <Button onClick={run} disabled={!canRun}>{busy ? 'Working…' : 'Run'}</Button>
          )}
        </div>
        {error && <p role="alert" className="mt-3 text-sm text-destructive">{error}</p>}
      </CardContent></Card>

      {needsList && customers !== null && (
        <Card><CardContent className="pt-6">
          {customers.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {customerBasis === 'INVOICE'
                ? 'No invoices for these dates. Process the run first (Production > Process Run).'
                : customerBasis === 'PRINT'
                  ? 'No issued invoices for these dates. Draft invoices get their numbers when the Packaging List is printed.'
                  : 'No orders for these dates.'}
            </p>
          ) : (
            <>
              <div className="flex items-center justify-between gap-3 pb-2">
                <label className="flex items-center gap-2 text-sm font-medium">
                  <Checkbox
                    checked={allSelected ? true : someSelected ? 'indeterminate' : false}
                    onCheckedChange={(v) => toggleAll(v === true)}
                    aria-label="Select all customers"
                  />
                  Select all ({customers.length})
                </label>
                <Button onClick={run} disabled={!canRun}>{busy ? 'Working…' : 'Run'}</Button>
              </div>
              <div className="grid grid-cols-[2rem_1fr_6rem_6rem] gap-2 border-b pb-1 text-xs font-medium text-muted-foreground">
                <span /><span>Customer</span><span>Number</span><span className="text-right">{customerColumnLabel ?? 'Orders'}</span>
              </div>
              {customers.map((c) => (
                <label key={c.customer_id} className="grid cursor-pointer grid-cols-[2rem_1fr_6rem_6rem] items-center gap-2 border-b py-2 text-sm">
                  <Checkbox checked={selected.has(c.customer_id)} onCheckedChange={(v) => toggleOne(c.customer_id, v === true)} />
                  <span>{c.customer_name}</span>
                  <span className="text-muted-foreground">{c.customer_number ?? ''}</span>
                  <span className="text-right tabular-nums">{c.document_count}</span>
                </label>
              ))}
            </>
          )}
        </CardContent></Card>
      )}

      {pdfUrl && (
        <Card><CardContent className="pt-6">
          <div className="mb-2 flex items-center justify-between">
            <h2 className="text-lg font-medium">Report</h2>
            <a className="text-sm underline" href={pdfUrl} target="_blank" rel="noreferrer">Open in new tab</a>
          </div>
          <iframe title={`${title} PDF`} src={pdfUrl} className="h-[75vh] w-full rounded border" />
        </CardContent></Card>
      )}
    </div>
  );
}
