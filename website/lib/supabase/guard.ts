import { notFound } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

/** Server pages call this first: the page does not exist for a user who cannot read the area (the database enforces the data anyway). */
export async function requireArea(area: string): Promise<void> {
  const { data } = await createClient().rpc('fnd_has_access', { p_area: area, p_action: 'R' });
  if (data !== true) notFound();
}
