import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';
import { readBody } from '@/lib/api/admin-rpc';
import { invoiceSpec, renderSpecs } from '@/lib/reports/financial';

export const dynamic = 'force-dynamic';

/** POST /api/documents/invoices { tenant_id, customer_id } → creates and saves a PDF for each issued invoice of the account that has none yet. */
export async function POST(request: Request) {
  const body = await readBody(request);
  const tenantId = toInt(body?.tenant_id);
  const customerId = toInt(body?.customer_id);
  if (tenantId === null || customerId === null) return NextResponse.json({ error: 'tenant_id and customer_id are required' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const supabase = createClient();

  const list = await supabase.rpc('ar_invoices_unsaved_get', { p_tenant_id: tenantId, p_account_id: customerId });
  if (list.error) return NextResponse.json({ error: list.error.message }, { status: 400 });
  const ids = (list.data as number[]).slice(0, 100);

  let created = 0;
  for (const id of ids) {
    const doc = await supabase.rpc('ar_invoice_document_get', { p_tenant_id: tenantId, p_ar_transaction_id: id });
    if (doc.error) return NextResponse.json({ error: doc.error.message }, { status: 400 });
    const bytes = await renderSpecs([invoiceSpec(doc.data)]);
    const save = await supabase.rpc('fnd_document_save', {
      p_tenant_id: tenantId,
      p_payload: {
        document_type: 'INVOICE', title: `Invoice ${doc.data.document_number}`, as_of_date: doc.data.transaction_date, customer_id: doc.data.customer_id,
        parameters: { ar_transaction_id: id, document_number: doc.data.document_number }, file_name: `invoice-${doc.data.document_number}.pdf`,
        content_base64: Buffer.from(bytes).toString('base64'),
      },
    });
    if (save.error) return NextResponse.json({ error: save.error.message }, { status: 400 });
    created += 1;
  }
  return NextResponse.json({ data: { created, remaining: (list.data as number[]).length - created } });
}
