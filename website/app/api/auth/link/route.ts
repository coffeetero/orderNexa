import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export const dynamic = 'force-dynamic';

/**
 * GET /api/auth/link?token_hash=…&type=invite|recovery → { valid: true, email } or { valid: false }.
 * Whose invite or password-reset link this is, for the Choose your password page, without using the link up
 * (fnd_link_email_get). Works before sign-in.
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const tokenHash = q.get('token_hash') ?? '';
  const type = q.get('type') === 'recovery' ? 'recovery' : 'invite';
  if (!/^[A-Za-z0-9_-]{20,200}$/.test(tokenHash)) return NextResponse.json({ valid: false });
  const { data, error } = await (await createClient()).rpc('fnd_link_email_get', { p_token_hash: tokenHash, p_type: type });
  if (error) return NextResponse.json({ error: 'The link could not be checked' }, { status: 500 });
  return NextResponse.json(data ?? { valid: false });
}
