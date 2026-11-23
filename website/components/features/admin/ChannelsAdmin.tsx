'use client';

import { useCallback, useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { adminCall, adminDelete, adminPost, PageHead, useBanner } from './adminShared';

interface Row { phone_number_id?: number; phone_number: string; channel: string; label: string | null; is_active: boolean }
type Notify = (text: string, type: 'success' | 'error') => void;

function NumberRow({ row, tenantId, notify, onChanged }: { row: Row; tenantId: number; notify: Notify; onChanged: () => void }) {
  const [r, setR] = useState(row);
  const [busy, setBusy] = useState(false);
  const run = async (fn: () => Promise<unknown>, done: string) => {
    setBusy(true);
    try { await fn(); notify(done, 'success'); onChanged(); } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  };
  return (
    <div className="grid grid-cols-2 items-end gap-3 border-b py-3 sm:grid-cols-[13rem_9rem_1fr_auto_auto_auto]">
      <div><Label className="text-xs">Number</Label><Input aria-label="Number" value={r.phone_number} placeholder="+15551234567" onChange={(e) => setR({ ...r, phone_number: e.target.value })} /></div>
      <div><Label className="text-xs">Channel</Label>
        <select aria-label="Channel" className="h-10 w-full rounded-md border bg-background px-2 text-sm" value={r.channel} onChange={(e) => setR({ ...r, channel: e.target.value })}>
          <option value="VOICE">Voice</option><option value="SMS">SMS</option><option value="WHATSAPP">WhatsApp</option>
        </select></div>
      <div><Label className="text-xs">Label</Label><Input aria-label="Label" value={r.label ?? ''} onChange={(e) => setR({ ...r, label: e.target.value })} /></div>
      <label className="flex items-center gap-2 text-sm"><Checkbox checked={r.is_active} onCheckedChange={(v) => setR({ ...r, is_active: v === true })} /> Active</label>
      <Button size="sm" disabled={busy || !r.phone_number} onClick={() => run(() => adminPost('/api/admin/channels', { tenant_id: tenantId, number: r }), 'Number saved.')}>Save</Button>
      {r.phone_number_id ? <Button size="sm" variant="outline" disabled={busy} onClick={() => run(() => adminDelete(`/api/admin/channels?tenant_id=${tenantId}&phone_number_id=${r.phone_number_id}`), 'Number deleted.')}>Delete</Button> : <span />}
    </div>
  );
}

export function ChannelsAdmin({ tenantId }: { tenantId: number }) {
  const { notify, banner } = useBanner();
  const [rows, setRows] = useState<Row[]>([]);
  const [adding, setAdding] = useState(0);
  const load = useCallback(async () => {
    try { setRows(await adminCall<Row[]>(`/api/admin/channels?tenant_id=${tenantId}`)); setAdding(0); } catch (e) { notify((e as Error).message, 'error'); }
  }, [tenantId, notify]);
  useEffect(() => { void load(); }, [load]);

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <PageHead title="Phone & Messaging Numbers">
        The numbers your customers call or message (Twilio, WhatsApp). Each number belongs to one company, so an incoming call or message opens the right
        company. Numbers are stored with the country code.
      </PageHead>
      {banner}
      <div>
        {rows.map((r) => <NumberRow key={`${r.phone_number_id}-${r.phone_number}-${r.channel}`} row={r} tenantId={tenantId} notify={notify} onChanged={load} />)}
        {Array.from({ length: adding }).map((_, i) => (
          <NumberRow key={`new-${i}`} row={{ phone_number: '', channel: 'VOICE', label: '', is_active: true }} tenantId={tenantId} notify={notify} onChanged={load} />
        ))}
        {rows.length === 0 && adding === 0 && <p className="py-3 text-sm text-muted-foreground">No numbers yet.</p>}
      </div>
      <Button size="sm" variant="outline" onClick={() => setAdding(1)} disabled={adding > 0}>Add number</Button>
    </div>
  );
}
