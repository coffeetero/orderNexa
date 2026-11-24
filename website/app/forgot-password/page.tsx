'use client';

import { useState } from 'react';
import Link from 'next/link';
import { ArrowLeft, Mail } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent } from '@/components/ui/card';

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState('');

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true); setError('');
    const res = await fetch('/api/auth/forgot', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email }) });
    setBusy(false);
    if (res.ok) setDone(true); else setError('Something went wrong. Please try again.');
  }

  return (
    <div className="flex min-h-[calc(100vh-4rem)] items-center justify-center px-4 py-12 text-foreground">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <Link href="/login" className="mb-6 inline-flex items-center gap-1.5 text-sm text-muted-foreground transition-colors hover:text-foreground">
            <ArrowLeft className="h-3.5 w-3.5" /> Back to sign in
          </Link>
          <div className="mb-4 flex justify-center text-primary">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-primary/10"><Mail className="h-6 w-6" /></div>
          </div>
          <h1 className="text-3xl font-bold" style={{ fontFamily: "'Playfair Display', Georgia, serif" }}>Forgot password</h1>
        </div>
        <Card className="border-border/60 bg-card shadow-sm">
          <CardContent className="pt-6">
            {done ? (
              <p className="text-sm">If <strong>{email}</strong> has an account, we sent it a link to choose a new password. Check your inbox (and spam folder).</p>
            ) : (
              <form onSubmit={submit} className="space-y-4">
                <div className="space-y-1.5 text-left">
                  <Label htmlFor="email">Email address</Label>
                  <Input id="email" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
                </div>
                {error && <div className="rounded-lg border border-destructive/20 bg-destructive/10 px-3 py-2 text-xs text-destructive">{error}</div>}
                <Button type="submit" className="h-10 w-full" disabled={busy}>{busy ? 'Sending…' : 'Send reset link'}</Button>
              </form>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
