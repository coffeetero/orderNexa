'use client';

import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { adminCall, adminPost } from './adminShared';

interface SenderSettings { tenant_name: string; email_from_address: string | null; email_reply_to: string | null }

/** Who the tenancy's customer emails (invites, password resets) come from, and where replies go. */
export function EmailSenderPanel({ tenantId, notify }: { tenantId: number; notify: (text: string, type: 'success' | 'error') => void }) {
  const [saved, setSaved] = useState<SenderSettings | null>(null);
  const [edit, setEdit] = useState<{ from: string; replyTo: string } | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    adminCall<SenderSettings>(`/api/admin/email-sender?tenant_id=${tenantId}`).then(setSaved).catch((e: Error) => notify(e.message, 'error'));
  }, [tenantId, notify]);

  async function save() {
    if (!edit || !saved) return;
    setBusy(true);
    try {
      await adminPost('/api/admin/email-sender', { tenant_id: tenantId, email_from_address: edit.from, email_reply_to: edit.replyTo });
      setSaved({ ...saved, email_from_address: edit.from.trim().toLowerCase() || null, email_reply_to: edit.replyTo.trim().toLowerCase() || null });
      setEdit(null);
      notify('Email sender saved.', 'success');
    } catch (e) { notify((e as Error).message, 'error'); } finally { setBusy(false); }
  }

  if (!saved) return null;
  return (
    <div className="rounded-md border p-3 text-sm">
      {edit ? (
        <div className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5"><Label htmlFor="es-from">From address</Label><Input id="es-from" type="email" value={edit.from} placeholder="orders@yourcompany.com" onChange={(e) => setEdit({ ...edit, from: e.target.value })} /></div>
            <div className="space-y-1.5"><Label htmlFor="es-reply">Replies go to</Label><Input id="es-reply" type="email" value={edit.replyTo} placeholder="office@yourcompany.com" onChange={(e) => setEdit({ ...edit, replyTo: e.target.value })} /></div>
          </div>
          <p className="text-xs text-muted-foreground">
            The From address must be on a domain that has been set up for sending; otherwise emails fail and you get a link to pass on by hand.
            Leave it empty to send under your company name from the system address. Replies should go to a mailbox someone reads.
          </p>
          <div className="flex gap-2"><Button size="sm" onClick={save} disabled={busy}>Save</Button><Button size="sm" variant="outline" onClick={() => setEdit(null)}>Cancel</Button></div>
        </div>
      ) : (
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            Emails to customers come from <span className="font-medium">{saved.tenant_name}</span>{' '}
            <span className="text-muted-foreground">&lt;{saved.email_from_address ?? 'system address'}&gt;</span>
            {saved.email_reply_to ? <> · replies go to <span className="text-muted-foreground">{saved.email_reply_to}</span></> : <span className="text-amber-700 dark:text-amber-400"> · no reply address</span>}
          </div>
          <Button size="sm" variant="outline" onClick={() => setEdit({ from: saved.email_from_address ?? '', replyTo: saved.email_reply_to ?? '' })}>Change</Button>
        </div>
      )}
    </div>
  );
}
