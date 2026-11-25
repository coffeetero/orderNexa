'use client';

import { Suspense, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { MailCheck } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';

/**
 * Landing page of the "Confirm your new email" link (Profile › Change email). The change is made only when the person
 * clicks the button, so mail scanners that open links do not make it for them. Works signed in or not.
 */
function ConfirmForm() {
  const token = useSearchParams().get('token') ?? '';
  const [state, setState] = useState<{ done?: string; error?: string; busy?: boolean }>({});

  async function confirm() {
    setState({ busy: true });
    const res = await fetch('/api/profile/email/confirm', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token }) });
    const j = (await res.json().catch(() => ({}))) as { data?: { email: string }; error?: string };
    setState(res.ok && j.data ? { done: j.data.email } : { error: j.error ?? 'The email could not be changed.' });
  }

  if (!token) return <p className="text-sm text-muted-foreground">This link is incomplete. Open it again from your email.</p>;
  if (state.done) {
    return (
      <div className="space-y-4 text-center">
        <p className="text-sm">Done. From now on, sign in with <span className="break-all font-medium">{state.done}</span>.</p>
        <Button asChild className="w-full"><Link href="/login">Sign in</Link></Button>
      </div>
    );
  }
  return (
    <div className="space-y-4 text-center">
      <p className="text-sm text-muted-foreground">Confirm to change the email you sign in with. Your access stays the same.</p>
      {state.error && <p role="alert" className="rounded-lg border border-destructive/20 bg-destructive/10 px-3 py-2 text-sm text-destructive">{state.error}</p>}
      <Button className="h-10 w-full" onClick={confirm} disabled={state.busy}>{state.busy ? 'Changing…' : 'Confirm new email'}</Button>
      <p className="text-xs text-muted-foreground"><Link href="/login" className="hover:text-foreground">Back to sign in</Link></p>
    </div>
  );
}

export default function ConfirmEmailPage() {
  return (
    <div className="flex min-h-[calc(100vh-4rem)] items-center justify-center px-4 py-12 text-foreground">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="mb-4 flex justify-center text-primary">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-primary/10"><MailCheck className="h-6 w-6" /></div>
          </div>
          <h1 className="text-2xl font-semibold tracking-tight">Confirm your new email</h1>
        </div>
        <Card className="border-border/60 bg-card shadow-sm">
          <CardContent className="pt-6"><Suspense fallback={null}><ConfirmForm /></Suspense></CardContent>
        </Card>
      </div>
    </div>
  );
}
