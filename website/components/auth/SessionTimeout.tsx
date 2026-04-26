'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

type SessionTimeoutProps = {
  timeoutMinutes: number;
};

export function SessionTimeout({ timeoutMinutes }: SessionTimeoutProps) {
  const router = useRouter();

  useEffect(() => {
    const supabase = createClient();
    const timeoutMs = timeoutMinutes * 60 * 1000;

    const timerId = window.setTimeout(async () => {
      await supabase.auth.signOut();
      router.replace('/login');
    }, timeoutMs);

    return () => {
      window.clearTimeout(timerId);
    };
  }, [router, timeoutMinutes]);

  return null;
}
