
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

export function createClient() {
  const cookieStore = cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      // This setting tells Supabase to use your custom schema for all requests
      db: {
        schema: process.env.NEXT_PUBLIC_DB_SCHEMA || 'public',
      },
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value;
        },
        set(name: string, value: string, options: any) {
          try {
            cookieStore.set({ name, value, ...options });
          } catch (error) {
            // The `set` method was called from a Server Component.
            // This can be ignored if you have middleware refreshing
            // user sessions.
          }
        },
        remove(name: string, options: any) {
          try {
            cookieStore.set({ name, value: '', ...options });
          } catch (error) {
            // The `delete` method was called from a Server Component.
            // This can be ignored if you have middleware refreshing
            // user sessions.
          }
        },
      },
    }
  );
}

// import { createServerClient } from '@supabase/ssr';
// import { cookies } from 'next/headers';

// export function createClient() {
//   const cookieStore = cookies();

//   return createServerClient(
//     process.env.NEXT_PUBLIC_SUPABASE_URL!,
//     process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
//     {
//       cookies: {
//         get(name: string) {
//           return cookieStore.get(name)?.value;
//         },
//         set(name: string, value: string, options: Record<string, unknown>) {
//           try {
//             cookieStore.set({ name, value, ...options });
//           } catch {
//             // Server components may be unable to write cookies.
//           }
//         },
//         remove(name: string, options: Record<string, unknown>) {
//           try {
//             cookieStore.set({ name, value: '', ...options });
//           } catch {
//             // Server components may be unable to write cookies.
//           }
//         },
//       },
//     }
//   );
// }
