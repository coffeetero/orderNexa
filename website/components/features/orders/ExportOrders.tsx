'use client';

import { useEffect, useState } from 'react';
import { Download } from 'lucide-react';
import type { CustomerOption } from '@/components/features/account/order-entry/OrderHeaderRow';
import { AccountPicker } from '@/components/features/orders/AccountPicker';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toImportCsv, type ImportRow } from '@/lib/orders/import-csv';

interface Code { value: string; label: string }

async function call<T>(url: string): Promise<T> {
  const res = await fetch(url);
  const j = (await res.json()) as { data?: T; error?: string };
  if (!res.ok || j.error) throw new Error(j.error ?? 'Request failed');
  return j.data as T;
}

const tomorrow = () => new Date(Date.now() + 86_400_000).toLocaleDateString('en-CA');

/** Downloads an account's orders for one production date and code as a CSV that Import Orders reads back. */
export function ExportOrders({ tenantId }: { tenantId: number }) {
  const [customers, setCustomers] = useState<CustomerOption[] | null>(null);
  const [codes, setCodes] = useState<Code[]>([]);
  const [account, setAccount] = useState<CustomerOption | null>(null);
  const [date, setDate] = useState(tomorrow());
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null);

  useEffect(() => {
    call<CustomerOption[]>(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=true`)
      .then(setCustomers).catch((e: Error) => { setCustomers([]); setMessage({ text: e.message, error: true }); });
    call<{ production_codes: Code[] }>(`/api/production/defaults?tenant_id=${tenantId}`)
      .then((d) => { setCodes(d.production_codes); setCode((c) => c || d.production_codes[0]?.value || ''); })
      .catch((e: Error) => setMessage({ text: e.message, error: true }));
  }, [tenantId]);

  // Load the lines whenever the account, date or code changes; Export downloads exactly what the grid shows.
  const [rows, setRows] = useState<ImportRow[] | null>(null);
  useEffect(() => {
    setRows(null); setMessage(null); setBusy(false);
    if (!account || !code || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return;
    let stale = false;
    const qs = new URLSearchParams({ tenant_id: String(tenantId), customer_id: String(account.customer_id), production_date: date, production_code: code });
    setBusy(true);
    call<ImportRow[]>(`/api/orders/export?${qs}`)
      .then((r) => { if (!stale) setRows(r); })
      .catch((e: Error) => { if (!stale) setMessage({ text: e.message, error: true }); })
      .finally(() => { if (!stale) setBusy(false); });
    return () => { stale = true; };
  }, [tenantId, account, date, code]);

  const exportOrders = () => {
    if (!account || !rows || rows.length === 0) return;
    const url = URL.createObjectURL(new Blob([toImportCsv(rows)], { type: 'text/csv' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `orders-${account.customer_number ?? account.customer_id}-${date}-${code}.csv`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    setMessage({ text: `Exported ${rows.length} line${rows.length === 1 ? '' : 's'}.`, error: false });
  };

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-2 sm:p-3">
      <div>
        <h1 className="text-2xl font-semibold">Export Orders</h1>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Download a customer account&rsquo;s orders (the account and its departments and sites) for one production date and code.
          The file has the Import Orders layout: Cus no, Customer, Department/Event, Item no, Item description, Qty.
        </p>
      </div>
      <Card><CardContent className="space-y-4 pt-6">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-[minmax(16rem,1fr)_10rem_10rem_auto] lg:items-end">
          <div>
            <Label htmlFor="exp-cust" className="text-xs">Customer account</Label>
            <AccountPicker customers={customers} value={account} onChange={setAccount} id="exp-cust" />
          </div>
          <div><Label htmlFor="exp-date" className="text-xs">Production date</Label><Input id="exp-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} /></div>
          <div>
            <Label htmlFor="exp-code" className="text-xs">Production code</Label>
            <select id="exp-code" className="h-10 w-full rounded-md border border-input bg-background px-2 text-sm" value={code} onChange={(e) => setCode(e.target.value)}>
              {codes.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
          </div>
          <Button onClick={exportOrders} disabled={busy || !rows || rows.length === 0} className="gap-1.5"><Download className="h-4 w-4" />Export</Button>
        </div>
        <p className="text-xs text-muted-foreground">Opening the file in Excel drops leading zeros from item numbers; edit it in a text editor or Sheets if you plan to import it again.</p>
        {message && <p role="status" className={`text-sm ${message.error ? 'text-destructive' : 'text-foreground'}`}>{message.text}</p>}
      </CardContent></Card>

      {account && (busy || rows) && (
        <Card><CardContent className="space-y-3 pt-6">
          <h2 className="text-lg font-medium">
            {account.customer_name}{account.customer_number ? ` (${account.customer_number})` : ''} · {date} {code}
            {rows && <span className="ml-2 text-sm font-normal text-muted-foreground">{rows.length} line{rows.length === 1 ? '' : 's'}</span>}
          </h2>
          {busy && !rows ? <p className="text-sm text-muted-foreground">Loading…</p> : rows && rows.length === 0 ? (
            <p className="text-sm text-muted-foreground">No orders for this account, date and code.</p>
          ) : rows && (
            <div className="max-h-[32rem] overflow-auto rounded-md border">
              <table className="w-full text-sm">
                <thead className="sticky top-0 bg-muted text-left text-xs">
                  <tr><th className="px-2 py-1.5">Cus no</th><th className="px-2 py-1.5">Customer</th><th className="px-2 py-1.5">Department/Event</th><th className="px-2 py-1.5">Item no</th><th className="px-2 py-1.5">Item description</th><th className="px-2 py-1.5 text-right">Qty</th></tr>
                </thead>
                <tbody>
                  {rows.map((r, i) => (
                    <tr key={i} className="border-t">
                      <td className="px-2 py-1">{r.cus_no}</td><td className="px-2 py-1">{r.customer_name}</td><td className="px-2 py-1">{r.department_event}</td><td className="px-2 py-1">{r.item_number}</td>
                      <td className="px-2 py-1">{r.item_desc}</td><td className="px-2 py-1 text-right">{r.qty}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent></Card>
      )}
    </div>
  );
}
