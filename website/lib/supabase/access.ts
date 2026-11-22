import { createClient } from '@/lib/supabase/server';

export type UserAccess = {
  userType: string | null;
  userName: string | null;
  /** Customer portal slug; only set for CUSTOMER_USER accounts linked to a customer. */
  accountSlug: string | null;
};

/**
 * Resolves who the signed-in auth user is inside BPS.
 *
 * `fnd_users` has no account_slug column: a customer user's slug lives on the
 * customer they are linked to (fnd_user_customers -> fnd_customers.account_slug).
 * This is the same path the login page uses.
 */
export async function getUserAccess(authUserId: string): Promise<UserAccess> {
  const supabase = createClient();

  const { data: profile, error: profileError } = await supabase
    .from('fnd_users')
    .select('user_id, user_type, user_name')
    .eq('auth_user_id', authUserId)
    .maybeSingle();

  if (profileError) {
    console.warn('[access] fnd_users lookup failed:', profileError.message);
  }
  if (!profile) {
    return { userType: null, userName: null, accountSlug: null };
  }

  const base = {
    userType: (profile.user_type as string | null) ?? null,
    userName: (profile.user_name as string | null) ?? null,
  };

  if (base.userType !== 'CUSTOMER_USER') {
    return { ...base, accountSlug: null };
  }

  const { data: link, error: linkError } = await supabase
    .from('fnd_user_customers')
    .select('customer_id')
    .eq('user_id', profile.user_id)
    .eq('is_active', true)
    .order('customer_id')
    .limit(1)
    .maybeSingle();

  if (linkError) {
    console.warn('[access] fnd_user_customers lookup failed:', linkError.message);
  }
  if (!link?.customer_id) {
    return { ...base, accountSlug: null };
  }

  const { data: customer, error: customerError } = await supabase
    .from('fnd_customers')
    .select('account_slug')
    .eq('customer_id', link.customer_id)
    .maybeSingle();

  if (customerError) {
    console.warn('[access] fnd_customers lookup failed:', customerError.message);
  }

  return { ...base, accountSlug: (customer?.account_slug as string | null) ?? null };
}
