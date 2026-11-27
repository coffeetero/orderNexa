'use client';

import { useCallback, useEffect, useState } from 'react';
import { ExternalLink, FilePlus2 } from 'lucide-react';
import { Button } from '@/components/ui/button';

interface Doc { document_id: number; document_type: string; title: string; as_of_date: string; byte_size: number; created_at: string }

const TYPE_LABEL: Record<string, string> = {
  INVOICE: 'Invoice', STATEMENT: 'Statement', AR_OPEN_BALANCES: 'AR Open Balances Report', AR_AGING: 'AR Aging', SALES: 'Sales report', FORECAST: 'Forecast',
};
const kb = (n: number) => (n >= 1_048_576 ? `${(n / 1_048_576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);

/** Saved PDFs for one account. Staff may also create the PDFs for invoices that have none yet. */
export function DocumentsList({ tenantId, customerId, types, canCreateInvoices = false }: {
  tenantId: number; customerId: number | null; types?: string[]; canCreateInvoices?: boolean;
}) {
  const [docs, setDocs] = useState<Doc[] | null>(null);
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    if (customerId === null) { setDocs([]); return; }
    try {
      const qs = new URLSearchParams({ tenant_id: String(tenantId), customer_id: String(customerId) });
      if (types?.length) qs.set('types', types.join(','));
      const res = await fetch(`/api/documents?${qs}`);
      const j = (await res.json()) as { data?: Doc[]; error?: string };
      if (!res.ok || !j.data) throw new Error(j.error ?? 'Could not load documents');
      setDocs(j.data);
    } catch (e) { setMessage({ text: (e as Error).message, error: true }); setDocs([]); }
  }, [tenantId, customerId, types]);
  useEffect(() => { void load(); }, [load]);

  async function createInvoices() {
    setBusy(true); setMessage(null);
    try {
      const res = await fetch('/api/documents/invoices', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tenant_id: tenantId, customer_id: customerId }) });
      const j = (await res.json()) as { data?: { created: number; remaining: number }; error?: string };
      if (!res.ok || !j.data) throw new Error(j.error ?? 'Could not create invoice documents');
      setMessage({ text: j.data.created === 0 ? 'Every issued invoice already has a PDF.' : `Created ${j.data.created} invoice PDF${j.data.created === 1 ? '' : 's'}${j.data.remaining > 0 ? `; ${j.data.remaining} more to create` : ''}.`, error: false });
      await load();
    } catch (e) { setMessage({ text: (e as Error).message, error: true }); } finally { setBusy(false); }
  }

  return (
    <div className="space-y-3 py-3">
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="mr-auto text-base font-medium">Documents</h2>
        {canCreateInvoices && (
          <Button size="sm" variant="outline" className="gap-1.5" onClick={createInvoices} disabled={busy || customerId === null}>
            <FilePlus2 className="h-4 w-4" />{busy ? 'Creating…' : 'Create invoice PDFs'}
          </Button>
        )}
      </div>
      {message && <p role="status" className={`text-sm ${message.error ? 'text-destructive' : 'text-foreground'}`}>{message.text}</p>}
      <div className="overflow-x-auto rounded-md border">
        <table className="w-full text-sm">
          <thead className="bg-muted/50 text-left text-xs"><tr><th className="px-3 py-2">Document</th><th className="px-3 py-2">Type</th><th className="px-3 py-2">As of</th><th className="px-3 py-2">Saved</th><th className="px-3 py-2">Size</th><th className="px-3 py-2" /></tr></thead>
          <tbody>
            {(docs ?? []).map((d) => (
              <tr key={d.document_id} className="border-t">
                <td className="px-3 py-2 font-medium">{d.title}</td>
                <td className="px-3 py-2">{TYPE_LABEL[d.document_type] ?? d.document_type}</td>
                <td className="px-3 py-2">{d.as_of_date}</td>
                <td className="px-3 py-2">{d.created_at.slice(0, 10)}</td>
                <td className="px-3 py-2">{kb(d.byte_size)}</td>
                <td className="px-3 py-2 text-right">
                  <a className="inline-flex items-center gap-1 text-primary hover:underline" href={`/api/documents/${d.document_id}?tenant_id=${tenantId}`} target="_blank" rel="noreferrer">
                    Open PDF <ExternalLink className="h-3.5 w-3.5" />
                  </a>
                </td>
              </tr>
            ))}
            {docs !== null && docs.length === 0 && <tr><td colSpan={6} className="px-3 py-4 text-muted-foreground">No documents yet.</td></tr>}
            {docs === null && <tr><td colSpan={6} className="px-3 py-4 text-muted-foreground">Loading…</td></tr>}
          </tbody>
        </table>
      </div>
    </div>
  );
}
