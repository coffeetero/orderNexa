'use client';

import { useEffect, useState } from 'react';
import { Download } from 'lucide-react';
import type { CustomerOption } from '@/components/features/account/order-entry/OrderHeaderRow';
import { AccountPicker } from '@/components/features/orders/AccountPicker';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { toCustomerCsv, writeCustomerSheet, type CustomerExportRow } from '@/lib/customers/customer-file';

async function call<T>(url: string): Promise<T> {
  const res = await fetch(url);
  const j = (await res.json()) as { data?: T; error?: string };
  if (!res.ok || j.error) throw new Error(j.error ?? 'Request failed');
  return j.data as T;
}

function download(blob: Blob, name: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** Downloads customers (accounts, sites, departments with their parent numbers) as CSV or Excel in the Import Customers layout. */
export function ExportCustomers({ tenantId }: { tenantId: number }) {
  const [customers, setCustomers] = useState<CustomerOption[] | null>(null);
  const [account, setAccount] = useState<CustomerOption | null>(null);
  const [all, setAll] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null);

  useEffect(() => {
    call<CustomerOption[]>(`/api/customers?tenant_id=${tenantId}&hierarchy=true&active=false`)
      .then(setCustomers).catch((e: Error) => { setCustomers([]); setMessage({ text: e.message, error: true }); });
  }, [tenantId]);

  const exportFile = async (format: 'csv' | 'xlsx') => {
    setBusy(true); setMessage(null);
    try {
      const qs = new URLSearchParams({ tenant_id: String(tenantId) });
      if (all) qs.set('all', 'true');
      if (account) qs.set('account_id', String(account.customer_id));
      const rows = await call<CustomerExportRow[]>(`/api/customers/export?${qs}`);
      if (rows.length === 0) throw new Error('No customers match.');
      const name = `customers-${account?.customer_number ?? 'all'}-${new Date().toLocaleDateString('en-CA')}`;
      if (format === 'csv') {
        download(new Blob([toCustomerCsv(rows)], { type: 'text/csv' }), `${name}.csv`);
      } else {
        const { default: ExcelJS } = await import('exceljs');
        const wb = new ExcelJS.Workbook();
        writeCustomerSheet(wb, rows);
        const buf = await wb.xlsx.writeBuffer();
        download(new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }), `${name}.xlsx`);
      }
      const count = (t: string) => rows.filter((r) => r.customer_type === t).length;
      setMessage({ text: `Exported ${rows.length} customers: ${count('ACCOUNT')} accounts, ${count('SITE')} sites, ${count('DEPARTMENT')} departments.`, error: false });
    } catch (e) {
      setMessage({ text: (e as Error).message, error: true });
    } finally { setBusy(false); }
  };

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-2 sm:p-3">
      <div>
        <h1 className="text-2xl font-semibold">Export Customers</h1>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
          Download customers as CSV or Excel: one row per account, site and department, each with its parent&rsquo;s customer number.
          Import Customers reads the same file back.
        </p>
      </div>
      <Card><CardContent className="space-y-4 pt-6">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-[minmax(16rem,1fr)_auto_auto] lg:items-end">
          <div>
            <Label htmlFor="cexp-acct" className="text-xs">Customer account (optional)</Label>
            <AccountPicker customers={customers} value={account} onChange={setAccount} id="cexp-acct" />
          </div>
          <fieldset className="space-y-1">
            <legend className="text-xs font-medium">Customers</legend>
            <div className="flex h-10 items-center gap-4 text-sm">
              <label className="flex items-center gap-2"><input type="radio" name="cexp-active" checked={!all} onChange={() => setAll(false)} />Active only</label>
              <label className="flex items-center gap-2"><input type="radio" name="cexp-active" checked={all} onChange={() => setAll(true)} />All</label>
            </div>
          </fieldset>
          <div className="flex gap-2">
            <Button onClick={() => exportFile('csv')} disabled={busy} variant="outline" className="gap-1.5"><Download className="h-4 w-4" />CSV</Button>
            <Button onClick={() => exportFile('xlsx')} disabled={busy} className="gap-1.5"><Download className="h-4 w-4" />Excel</Button>
          </div>
        </div>
        <p className="text-xs text-muted-foreground">
          No account picked = all customers. Pricing book is for reference; Import Customers does not change it.
        </p>
        {message && <p role="status" className={`text-sm ${message.error ? 'text-destructive' : 'text-foreground'}`}>{message.text}</p>}
      </CardContent></Card>
    </div>
  );
}
