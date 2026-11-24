import { createClient } from '@supabase/supabase-js';

/**
 * Service-role client for the few server-side jobs that act without a signed-in user (creating invite and
 * password-reset links). Bypasses row security: never import it from client code or return its results unchecked.
 */
export function createServiceClient() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Error('SUPABASE_SERVICE_ROLE_KEY is not set');
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, key, {
    db: { schema: process.env.NEXT_PUBLIC_DB_SCHEMA || 'public' },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
