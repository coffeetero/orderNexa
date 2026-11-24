'use client';

import { Suspense, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { Wheat, Eye, EyeOff, ArrowLeft } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent } from '@/components/ui/card';
import { createClient } from '@/lib/supabase/client';

const supabase = createClient();

function LoginForm() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    // --- STAGE 0: ENTRY ---

    // 1. Authenticate with Supabase Auth
    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
      email, password,
    });

    if (authError) {
      console.error("❌ [Stage 1] Auth Error:", authError.message);
      setError(authError.message);
      setLoading(false);
      return;
    }

    if (authData?.user) {
      try {
        // Where this user starts (decided server-side by /api/auth/landing)
        const res = await fetch('/api/auth/landing');
        const landing = await res.json().catch(() => ({}));
        if (!res.ok || !landing.href) {
          await supabase.auth.signOut();
          setError(landing.error ?? 'Access Denied: User record not found.');
          setLoading(false);
          return;
        }
        router.refresh();
        router.replace(landing.href);
      } catch (err) {
        console.error('🔥 [Critical] Login Logic failed:', err);
        setError('An unexpected error occurred during login.');
        setLoading(false);
      }
    }
  };

  // UI remains unchanged...
  return (
    <div className="min-h-[calc(100vh-4rem)] flex items-center justify-center px-4 py-12 text-foreground">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <Link href="/" className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors mb-6">
            <ArrowLeft className="h-3.5 w-3.5" /> Back to home
          </Link>
          <div className="flex justify-center mb-4 text-primary">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-primary/10">
              <Wheat className="h-6 w-6" />
            </div>
          </div>
          <h1 className="text-3xl font-bold" style={{ fontFamily: "'Playfair Display', Georgia, serif" }}>
            Welcome Back
          </h1>
        </div>

        <Card className="border-border/60 shadow-sm bg-card">
          <CardContent className="pt-6">
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="space-y-1.5 text-left">
                <Label htmlFor="email">Email address</Label>
                <Input id="email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
              </div>
              <div className="space-y-1.5 text-left">
                <div className="flex items-center justify-between">
                  <Label htmlFor="password">Password</Label>
                  <Link href="/forgot-password" className="text-xs text-muted-foreground hover:text-foreground">Forgot password?</Link>
                </div>
                <div className="relative">
                  <Input id="password" type={showPassword ? 'text' : 'password'} value={password} onChange={(e) => setPassword(e.target.value)} required />
                  <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground">
                    {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
              </div>
              {error && <div className="rounded-lg bg-destructive/10 border border-destructive/20 px-3 py-2 text-xs text-destructive">{error}</div>}
              <Button type="submit" className="w-full h-10" disabled={loading}>
                {loading ? 'Signing in...' : 'Sign In'}
              </Button>
            </form>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={<div className="min-h-screen flex items-center justify-center animate-spin">...</div>}>
      <LoginForm />
    </Suspense>
  );
}