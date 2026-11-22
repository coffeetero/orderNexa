import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';
import { bakersPdf, type BakersData } from '@/lib/pdf/bakers';
import { deliveryPdf, type DeliveryData } from '@/lib/pdf/delivery';
import { labelsPdf, type LabelsData } from '@/lib/pdf/labels';
import { packagingPdf, type PackagingData } from '@/lib/pdf/packaging';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

const isDate = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);

function pdfResponse(bytes: Uint8Array, filename: string): Response {
  return new Response(bytes, {
    headers: { 'Content-Type': 'application/pdf', 'Content-Disposition': `inline; filename="${filename}"`, 'Cache-Control': 'no-store' },
  });
}

const fail = (message: string, status = 400) => NextResponse.json({ error: message }, { status });

/**
 * POST /api/reports/run { report: 'bakers'|'labels'|'packaging'|'delivery', tenant_id, from, to, production_code?, customer_ids? }
 * → application/pdf. The data and every total come from the database functions (om_report_*); this route only draws them.
 * Labels and Packaging need customer_ids. Printing records the print time on the runs; Packaging also numbers the invoices.
 */
export async function POST(request: Request) {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return fail('Invalid JSON body');
  }
  const report = typeof body.report === 'string' ? body.report : '';
  const tenantId = toInt(body.tenant_id);
  if (!['bakers', 'labels', 'packaging', 'delivery'].includes(report) || tenantId === null || !isDate(body.from) || !isDate(body.to)) {
    return fail('report, tenant_id, from and to (YYYY-MM-DD) are required');
  }
  const code = typeof body.production_code === 'string' && body.production_code.trim() !== '' ? body.production_code : null;
  const ids = Array.isArray(body.customer_ids) ? body.customer_ids.map(toInt).filter((n): n is number => n !== null) : [];
  if ((report === 'labels' || report === 'packaging') && ids.length === 0) return fail('Select at least one customer');

  const auth = await requireStaff();
  if (!auth.ok) return auth.response;

  const supabase = createClient();
  const args = { p_tenant_id: tenantId, p_from: body.from, p_to: body.to, p_production_code: code };
  const label = `${body.from}${body.from === body.to ? '' : ` to ${body.to}`}${code ? ` ${code}` : ''}`;
  const name = `${report}-${body.from}${body.from === body.to ? '' : `-to-${body.to}`}.pdf`;

  if (report === 'bakers') {
    const { data, error } = await supabase.rpc('om_report_bakers_get', args);
    if (error) return fail(error.message);
    const d = data as BakersData;
    if (!d.runs.length) return fail('No production runs found for these dates.');
    const bytes = await bakersPdf(d, label);
    await supabase.rpc('om_production_runs_mark_printed', { ...args, p_report: 'BAKER' });
    return pdfResponse(bytes, name);
  }
  if (report === 'labels') {
    const { data, error } = await supabase.rpc('om_report_labels_get', { ...args, p_customer_ids: ids });
    if (error) return fail(error.message);
    const d = data as LabelsData;
    if (!d.labels.length) return fail('No order lines found for the selected customers.');
    const bytes = await labelsPdf(d);
    await supabase.rpc('om_production_runs_mark_printed', { ...args, p_report: 'LABELS' });
    return pdfResponse(bytes, name);
  }
  if (report === 'packaging') {
    const { data, error } = await supabase.rpc('om_report_packaging_issue', { ...args, p_customer_ids: ids });
    if (error) return fail(error.message);
    return pdfResponse(await packagingPdf(data as PackagingData, label), name);
  }
  const { data, error } = await supabase.rpc('om_report_delivery_get', args);
  if (error) return fail(error.message);
  const d = data as DeliveryData;
  if (!d.stops.length) return fail('No deliveries found. Process the run first.');
  const bytes = await deliveryPdf(d, label);
  await supabase.rpc('om_production_runs_mark_printed', { ...args, p_report: 'DELIVERY' });
  return pdfResponse(bytes, name);
}
