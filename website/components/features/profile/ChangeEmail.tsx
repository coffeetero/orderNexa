'use client';

import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { createClient } from '@/lib/supabase/client';

/**
 * Profile › Sign-in email: the address the person signs in with, and a way to change it. A confirmation link goes to the
 * new address (/api/profile/email); the change happens when it is opened. Access does not depend on the email.
 */
export function ChangeEmail() {
  const [current, setCurrent] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [next, setNext] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ text: string; error: boolean; link?: string } | null>(null);

  useEffect(() => {
    createClient().auth.getUser().then(({ data }) => setCurrent(data.user?.email ?? null));
  }, []);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setMessage(null);
    try {
      const res = await fetch('/api/profile/email', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: next }) });
      const j = (await res.json().catch(() => ({}))) as { data?: { sent: boolean; email: string; link?: string }; error?: string };
      if (!res.ok || !j.data) throw new Error(j.error ?? 'The request could not be sent.');
      setMessage(j.data.sent
        ? { text: `We sent a link to ${j.data.email}. Your sign-in email changes when you open it (within 24 hours).`, error: false }
        : { text: 'Email is not set up here, so no message was sent. Open this link to confirm:', error: false, link: j.data.link });
      setEditing(false); setNext('');
    } catch (err) {
      setMessage({ text: (err as Error).message, error: true });
    } finally { setBusy(false); }
  }

  return (
    <Card className="border-border/60">
      <CardContent className="space-y-3 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="text-sm font-medium">Sign-in email</p>
            <p className="break-all text-sm text-muted-foreground">{current ?? '…'}</p>
          </div>
          {!editing && <Button size="sm" variant="outline" onClick={() => { setEditing(true); setMessage(null); }} disabled={!current}>Change email</Button>}
        </div>
        {editing && (
          <form onSubmit={send} className="flex flex-wrap items-end gap-3">
            <div className="min-w-[260px] flex-1 space-y-1.5">
              <Label htmlFor="new-email">New email</Label>
              <Input id="new-email" type="email" autoComplete="email" value={next} onChange={(e) => setNext(e.target.value)} required autoFocus />
            </div>
            <Button type="submit" size="sm" disabled={busy || !next.trim()}>{busy ? 'Sending…' : 'Send confirmation link'}</Button>
            <Button type="button" size="sm" variant="ghost" onClick={() => { setEditing(false); setNext(''); }}>Cancel</Button>
          </form>
        )}
        {editing && <p className="text-xs text-muted-foreground">Your roles and companies stay the same. Your current address gets a notice once the change is made.</p>}
        {message && (
          <p role="status" className={`text-sm ${message.error ? 'text-destructive' : 'text-foreground'}`}>
            {message.text}{message.link && <> <a href={message.link} className="break-all text-primary underline">{message.link}</a></>}
          </p>
        )}
      </CardContent>
    </Card>
  );
}
