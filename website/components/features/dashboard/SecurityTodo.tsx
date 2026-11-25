'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { MailWarning, MapPin, UserX } from 'lucide-react';
import { Button } from '@/components/ui/button';

export interface SecuritySignal {
  kind: 'INACTIVE_USER' | 'NEW_LOCATION' | 'EMAIL_REUSE';
  user_id: number; user_name: string; email: string | null; self: boolean;
  last_active_at?: string; working_days?: number;
  city?: string; region?: string | null; country?: string | null; ip?: string | null; first_seen_at?: string;
  /** EMAIL_REUSE: someone tried to add this staff member's email as a new user */
  event_id?: number; customer_name?: string | null; attempted_by?: string | null; created_at?: string; is_active_here?: boolean;
}

const when = (iso?: string) => (iso ? new Date(iso).toLocaleString('en-US', { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '');
const place = (s: SecuritySignal) => [s.city, s.region, s.country].filter(Boolean).join(', ');

/**
 * One security To-Do on the Dashboard: a staff member inactive for N working days, or using BPS from a new place.
 * Buttons act through /api/todos/act. A signal about the reader themselves (only when nobody else manages users) shows
 * without buttons: nobody can clear their own.
 */
export function SecurityTodo({ tenantId, signal: s }: { tenantId: number; signal: SecuritySignal }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);

  async function post(url: string, body: unknown) {
    const res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    const j = (await res.json().catch(() => ({}))) as { error?: string };
    if (!res.ok) throw new Error(j.error ?? 'That did not work. Try again.');
  }

  async function act(action: 'DEACTIVATE' | 'STILL_HERE' | 'EXPECTED') {
    setBusy(action); setError(null);
    try {
      // a deactivation from an email-reuse To-Do (or of someone already inactive) also releases the email for the new account
      if (!(reuse && action === 'DEACTIVATE' && !s.is_active_here)) {
        await post('/api/todos/act', { tenant_id: tenantId, user_id: s.user_id, action, city: s.city, region: s.region, country: s.country, event_id: s.event_id });
      }
      if (reuse && action === 'DEACTIVATE') await post('/api/admin/users/release', { tenant_id: tenantId, user_id: s.user_id });
      router.refresh();
    } catch (e) { setError((e as Error).message); setBusy(null); setConfirming(false); }
  }

  const inactive = s.kind === 'INACTIVE_USER';
  const reuse = s.kind === 'EMAIL_REUSE';
  const deactivateLabel = reuse ? (s.is_active_here ? 'Deactivate and release email' : 'Release email') : 'Deactivate account';
  return (
    <li className="flex flex-wrap items-center gap-x-3 gap-y-1.5 px-4 py-2 text-sm">
      {reuse ? <MailWarning className="h-4 w-4 shrink-0 text-destructive" aria-hidden="true" />
        : inactive ? <UserX className="h-4 w-4 shrink-0 text-warning" aria-hidden="true" /> : <MapPin className="h-4 w-4 shrink-0 text-info" aria-hidden="true" />}
      <span className="min-w-0 flex-1">
        {reuse ? (
          <>{s.customer_name ? <span className="font-medium">{s.customer_name}</span> : 'Someone'}{s.attempted_by ? ` (${s.attempted_by})` : ''} tried to add <span className="font-medium">{s.user_name}</span> ({s.email}) as one of their users on {when(s.created_at)}, but {s.is_active_here ? <>this email belongs to <span className="font-medium">active staff</span> here. Has this person left the company?</> : 'this email belongs to a former staff member here. Release it so they can get a new account?'}</>
        ) : inactive ? (
          <><span className="font-medium">{s.user_name}</span> hasn&apos;t used BPS in {s.working_days} working day{s.working_days === 1 ? '' : 's'} (last {when(s.last_active_at)}). Is {s.self ? 'this you' : 'this person still with the company'}?</>
        ) : (
          <><span className="font-medium">{s.user_name}</span> used BPS from a new place: <span className="font-medium">{place(s)}</span>{s.ip ? <span className="text-muted-foreground"> (IP {s.ip})</span> : null} on {when(s.first_seen_at)}. Expected?</>
        )}
        {error && <span role="alert" className="block text-xs text-destructive">{error}</span>}
      </span>
      {s.self ? (
        <span className="rounded bg-muted px-2 py-0.5 text-xs text-muted-foreground">About you: needs another administrator</span>
      ) : confirming ? (
        <span className="flex items-center gap-2">
          <span className="text-xs">{reuse ? `${s.is_active_here ? 'Deactivate' : 'Release'} ${s.user_name}? Their old account ends for good (history is kept) and the email becomes free for a new account.` : `Deactivate ${s.user_name}? They lose access at once.`}</span>
          <Button size="sm" variant="destructive" className="h-7" disabled={busy !== null} onClick={() => act('DEACTIVATE')}>{busy === 'DEACTIVATE' ? 'Working…' : 'Confirm'}</Button>
          <Button size="sm" variant="ghost" className="h-7" disabled={busy !== null} onClick={() => setConfirming(false)}>Cancel</Button>
        </span>
      ) : (
        <span className="flex items-center gap-2">
          <Button size="sm" variant="outline" className="h-7" disabled={busy !== null} onClick={() => act(inactive || reuse ? 'STILL_HERE' : 'EXPECTED')}>
            {busy && busy !== 'DEACTIVATE' ? 'Saving…' : reuse ? (s.is_active_here ? 'Still with us' : 'Keep for now') : inactive ? 'Still with us' : 'Expected'}
          </Button>
          <Button size="sm" variant="ghost" className="h-7 text-destructive hover:text-destructive" disabled={busy !== null} onClick={() => setConfirming(true)}>{deactivateLabel}</Button>
        </span>
      )}
    </li>
  );
}
