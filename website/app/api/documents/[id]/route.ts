import { NextResponse } from 'next/server';
import { createClient, getSessionUser } from '@/lib/supabase/server';
import { toInt } from '@/lib/api/nav';

export const dynamic = 'force-dynamic';

/** GET /api/documents/<id>?tenant_id=n[&download=1] → the saved PDF itself. */
export async function GET(request: Request, props: { params: Promise<{ id: string }> }) {
  const params = await props.params;
  const q = new URL(request.url).searchParams;
  const tenantId = toInt(q.get('tenant_id'));
  const id = toInt(params.id);
  if (tenantId === null || id === null) return NextResponse.json({ error: 'Invalid or missing id' }, { status: 400 });
  if (!(await getSessionUser())) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { data, error } = await (await createClient()).rpc('fnd_document_get', { p_tenant_id: tenantId, p_document_id: id });
  if (error || !data) return NextResponse.json({ error: error?.message ?? 'Document not found' }, { status: 404 });
  const bytes = Buffer.from(data.content_base64 as string, 'base64');
  const name = String(data.file_name).replace(/[^\w.\- ]/g, '_');
  return new NextResponse(bytes, {
    headers: {
      'Content-Type': data.content_type as string,
      'Content-Disposition': `${q.get('download') ? 'attachment' : 'inline'}; filename="${name}"`,
      'Cache-Control': 'private, no-store',
    },
  });
}
