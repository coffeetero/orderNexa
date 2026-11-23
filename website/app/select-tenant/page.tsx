'use client';

import { Suspense, useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { Building2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { createClient } from '@/lib/supabase/client';

type Tenancy = { tenant_id: number; tenant_name: string; tenant_slug: string | null };
const supabase = createClient();

function safeNext(raw: string | null): string | null {
  return raw && raw.startsWith('/') && !raw.startsWith('//') ? raw : null;
}

function Picker() {
  const next = safeNext(useSearchParams().get('next'));
  const [tenancies, setTenancies] = useState<Tenancy[] | null>(null);
  const [hostSlug, setHostSlug] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function choose(t: Tenancy) {
    setBusy(true);
    setError('');
    const res = await fetch('/api/auth/select-tenant', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tenant_id: t.tenant_id }),
    });
    if (!res.ok) {
      setError((await res.json().catch(() => ({}))).error ?? 'Could not select that tenancy.');
      setBusy(false);
      return;
    }
    await supabase.auth.refreshSession(); // new token carries the tenant_id claim
    let target = next;
    if (!target) {
      const { data: profile } = await supabase.from('fnd_users').select('user_type').maybeSingle();
      target = profile?.user_type === 'TENANCY_USER' ? '/dashboard' : '/';
    }
    window.location.assign(target); // full load so every server component sees the new token
  }

  useEffect(() => {
    (async () => {
      const res = await fetch('/api/auth/tenancies');
      if (!res.ok) {
        window.location.assign('/login');
        return;
      }
      const body = await res.json();
      const list: Tenancy[] = body.tenancies ?? [];
      setTenancies(list);
      setHostSlug(body.host_slug ?? null);
      // Only one choice, or the web address already names the tenancy: no screen needed.
      const byHost = body.host_slug ? list.find((t) => t.tenant_slug === body.host_slug) : undefined;
      if (byHost) void choose(byHost);
      else if (!body.host_slug && list.length === 1) void choose(list[0]);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function signOut() {
    await supabase.auth.signOut();
    window.location.assign('/login');
  }

  if (tenancies === null) return <p className="p-8 text-center text-muted-foreground">Loading…</p>;

  const wrongAddress = hostSlug && !tenancies.some((t) => t.tenant_slug === hostSlug);
  return (
    <div className="min-h-[calc(100vh-4rem)] flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md space-y-4">
        <div className="text-center">
          <div className="flex justify-center mb-3 text-primary"><Building2 className="h-8 w-8" /></div>
          <h1 className="text-2xl font-bold">Choose a company</h1>
          <p className="text-sm text-muted-foreground">You can work in one company at a time.</p>
        </div>
        {wrongAddress && <p className="text-sm text-destructive">Your account has no access to the company at this web address.</p>}
        {error && <p className="text-sm text-destructive">{error}</p>}
        {tenancies.length === 0 && <p className="text-sm text-muted-foreground text-center">No company is assigned to your account.</p>}
        <div className="space-y-2">
          {tenancies.map((t) => (
            <Button key={t.tenant_id} variant="outline" className="w-full justify-start h-12" disabled={busy || (!!hostSlug && t.tenant_slug !== hostSlug)} onClick={() => choose(t)}>
              {t.tenant_name}
            </Button>
          ))}
        </div>
        <Button variant="ghost" className="w-full" onClick={signOut}>Sign out</Button>
      </div>
    </div>
  );
}

export default function SelectTenantPage() {
  return (
    <Suspense fallback={null}>
      <Picker />
    </Suspense>
  );
}
