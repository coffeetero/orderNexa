'use client';

import { Suspense, useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { Eye, EyeOff, KeyRound } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent } from '@/components/ui/card';
import { createClient } from '@/lib/supabase/client';

const supabase = createClient();

/**
 * Landing page of invite and password-reset emails. The one-time token is used only when the person submits, so mail
 * scanners that open links do not use it up. On opening, the page looks up whose link it is without using it
 * (/api/auth/link): it shows that email, or says at once that the link no longer works.
 */
function AcceptForm() {
  const router = useRouter();
  const params = useSearchParams();
  const tokenHash = params.get('token_hash') ?? '';
  const type = params.get('type') === 'recovery' ? 'recovery' : 'invite';
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [show, setShow] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  // whose link this is: undefined while checking, null when the link no longer works
  const [linkEmail, setLinkEmail] = useState<string | null | undefined>(undefined);

  useEffect(() => {
    if (!tokenHash) return;
    let live = true;
    fetch(`/api/auth/link?${new URLSearchParams({ token_hash: tokenHash, type })}`)
      .then((r) => r.json())
      .then((j: { valid?: boolean; email?: string; error?: string }) => {
        if (!live) return;
        // if the check itself fails, let the person try: the link is still verified on submit
        setLinkEmail(j.error ? '' : j.valid && j.email ? j.email : null);
      })
      .catch(() => live && setLinkEmail(''));
    return () => { live = false; };
  }, [tokenHash, type]);

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError('');
    if (password.length < 8) return setError('Use at least 8 characters.');
    if (password !== confirm) return setError('The two passwords do not match.');
    setBusy(true);
    const verified = await supabase.auth.verifyOtp({ token_hash: tokenHash, type });
    if (verified.error) {
      setBusy(false);
      return setError('This link has expired or was already used. Ask for a new invite, or use "Forgot password".');
    }
    const updated = await supabase.auth.updateUser({ password });
    if (updated.error) { setBusy(false); return setError(updated.error.message); }
    const res = await fetch('/api/auth/landing');
    const json = await res.json().catch(() => ({}));
    if (!res.ok || !json.href) { setBusy(false); return setError(json.error ?? 'Your password is set, but we could not open your account.'); }
    router.refresh();
    router.replace(json.href);
  }

  if (!tokenHash) {
    return <p className="text-sm text-muted-foreground">This link is incomplete. Open it again from your email.</p>;
  }
  if (linkEmail === null) {
    return (
      <div className="space-y-4 text-center">
        <p role="alert" className="text-sm">
          This link has expired or was already used.{' '}
          {type === 'invite' ? 'Ask the person who invited you to send a new invite.' : 'Ask for a new link below.'}
        </p>
        <div className="flex justify-center gap-4 text-sm">
          <Link href="/forgot-password" className="font-medium text-primary hover:underline">Forgot password</Link>
          <Link href="/login" className="text-muted-foreground hover:text-foreground">Back to sign in</Link>
        </div>
      </div>
    );
  }
  return (
    <form onSubmit={submit} className="space-y-4">
      <div className="min-h-[40px] text-center text-sm text-muted-foreground" aria-live="polite">
        {linkEmail === undefined ? 'Checking your link…' : linkEmail ? (
          <>{type === 'invite' ? 'Choosing the password for' : 'New password for'}<br /><span className="font-medium text-foreground break-all">{linkEmail}</span></>
        ) : null}
      </div>
      <div className="space-y-1.5 text-left">
        <Label htmlFor="password">New password</Label>
        <div className="relative">
          <Input id="password" type={show ? 'text' : 'password'} autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
          <button type="button" onClick={() => setShow(!show)} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground" aria-label={show ? 'Hide password' : 'Show password'}>
            {show ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </button>
        </div>
      </div>
      <div className="space-y-1.5 text-left">
        <Label htmlFor="confirm">Confirm password</Label>
        <Input id="confirm" type={show ? 'text' : 'password'} autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} required />
      </div>
      {error && <div className="rounded-lg border border-destructive/20 bg-destructive/10 px-3 py-2 text-xs text-destructive">{error}</div>}
      <Button type="submit" className="h-10 w-full" disabled={busy}>{busy ? 'Saving…' : type === 'invite' ? 'Set password and continue' : 'Save new password'}</Button>
      <p className="text-center text-xs text-muted-foreground"><Link href="/login" className="hover:text-foreground">Back to sign in</Link></p>
    </form>
  );
}

export default function AcceptPage() {
  return (
    <div className="flex min-h-[calc(100vh-4rem)] items-center justify-center px-4 py-12 text-foreground">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="mb-4 flex justify-center text-primary">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-primary/10"><KeyRound className="h-6 w-6" /></div>
          </div>
          <h1 className="text-3xl font-bold" style={{ fontFamily: "'Playfair Display', Georgia, serif" }}>Choose your password</h1>
        </div>
        <Card className="border-border/60 bg-card shadow-sm">
          <CardContent className="pt-6">
            <Suspense fallback={null}><AcceptForm /></Suspense>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
