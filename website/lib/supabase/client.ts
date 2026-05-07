import { createBrowserClient } from '@supabase/ssr';

type BrowserClient = ReturnType<typeof createBrowserClient<any, string>>;

let browserClient: BrowserClient | undefined;

export function createClient(): BrowserClient {
  if (!browserClient) {
    browserClient = createBrowserClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        // This ensures the browser-side client uses the same schema as the server
        db: {
          schema: process.env.NEXT_PUBLIC_DB_SCHEMA || 'public',
        },
      }
    );
  }

  return browserClient;
}

// import { createBrowserClient } from '@supabase/ssr';
// import type { SupabaseClient } from '@supabase/supabase-js';

// let browserClient: SupabaseClient | null = null;

// export function createClient(): SupabaseClient {
//   if (!browserClient) {
//     browserClient = createBrowserClient(
//       process.env.NEXT_PUBLIC_SUPABASE_URL!,
//       process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
//     );
//   }

//   return browserClient;
// }
