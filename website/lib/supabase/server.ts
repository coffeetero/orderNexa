import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import type { User } from '@supabase/supabase-js';

function isStaleSessionAuthError(err: unknown): boolean {
  if (err === null || typeof err !== 'object') return false;
  const o = err as { __isAuthError?: boolean; code?: string; message?: string };
  if (o.__isAuthError !== true) return false;
  if (o.code === 'refresh_token_not_found') return true;
  if (
    typeof o.message === 'string' &&
    /refresh token/i.test(o.message) &&
    /invalid|not found/i.test(o.message)
  ) {
    return true;
  }
  return false;
}

/**
 * Resolves the current user from Supabase auth cookies. Returns null when there is no
 * session or the refresh token is no longer valid (instead of throwing AuthApiError).
 */
export async function getSessionUser(): Promise<User | null> {
  try {
    const supabase = createClient();
    const {
      data: { user },
      error,
    } = await supabase.auth.getUser();
    if (error) {
      if (isStaleSessionAuthError(error)) return null;
      console.warn('[supabase] getUser:', error.message);
      return null;
    }
    return user;
  } catch (err) {
    if (isStaleSessionAuthError(err)) return null;
    throw err;
  }
}

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
