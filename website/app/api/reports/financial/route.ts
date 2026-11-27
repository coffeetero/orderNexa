import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { requireStaff, toInt } from '@/lib/api/nav';
import { readBody } from '@/lib/api/admin-rpc';
import {
  REPORT_TYPES, agingSpec, forecastSpec, openBalancesSpec, renderSpecs, salesSpec, type ReportKind,
} from '@/lib/reports/financial';
import { statementPdf } from '@/lib/reports/statement-pdf';

export const dynamic = 'force-dynamic';

const isDate = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);
const toB64 = (b: Uint8Array) => Buffer.from(b).toString('base64');

/**
 * GET /api/reports/financial?tenant_id=n[&with_invoices=1&from=YYYY-MM-DD&to=YYYY-MM-DD] → active Accounts the caller may report on (the customer picker).
 * With with_invoices only accounts that have an issued invoice in the period (from and to are each optional).
 * With open=1&as_of=YYYY-MM-DD: only accounts with something open on that date, each with its balance (AR Open Balances).
 */
export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const tenantId = toInt(q.get('tenant_id'));
  if (tenantId === null) return NextResponse.json({ error: 'Invalid or missing tenant_id' }, { status: 400 });
  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const from = q.get('from');
  const to = q.get('to');
  if ((from && !isDate(from)) || (to && !isDate(to))) return NextResponse.json({ error: 'from and to must be YYYY-MM-DD' }, { status: 400 });
  if (q.get('open') === '1') {
    const asOf = q.get('as_of');
    if (!isDate(asOf)) return NextResponse.json({ error: 'as_of must be YYYY-MM-DD' }, { status: 400 });
    const r = await (await createClient()).rpc('ar_open_accounts_get', { p_tenant_id: tenantId, p_as_of: asOf });
    if (r.error) return NextResponse.json({ error: r.error.message }, { status: 400 });
    return NextResponse.json({ data: r.data });
  }
  const { data, error } = await (await createClient()).rpc('fnd_report_accounts_get', {
    p_tenant_id: tenantId, p_with_invoices: q.get('with_invoices') === '1', p_from: from || null, p_to: to || null,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

/**
 * POST /api/reports/financial
 *   { tenant_id, kind: ar|aging|statements|sales|forecast, customer_ids: number[], as_of, from?, to?, lookback_weeks?, horizon_weeks?, save? }
 * → { data: { title, file_name, pdf_base64, saved_ids } }. With save=true the PDF is also stored in fnd_documents; statements are stored one
 * per customer (each with its own as-of date), other reports once (with the customer when exactly one is selected).
 */
export async function POST(request: Request) {
  const body = await readBody(request);
  const tenantId = toInt(body?.tenant_id);
  const kind = body?.kind as ReportKind;
  const ids = Array.isArray(body?.customer_ids) ? (body!.customer_ids as unknown[]).map(toInt) : [];
  if (tenantId === null || !(kind in REPORT_TYPES) || ids.length === 0 || ids.length > 500 || ids.some((i) => i === null)) {
    return NextResponse.json({ error: 'tenant_id, kind and 1-500 customer_ids are required' }, { status: 400 });
  }
  const customerIds = ids as number[];
  const asOf = body?.as_of;
  const from = body?.from;
  const to = body?.to;
  if (kind === 'sales' ? !isDate(from) || !isDate(to) : !isDate(asOf)) {
    return NextResponse.json({ error: kind === 'sales' ? 'from and to dates are required' : 'as_of date is required' }, { status: 400 });
  }

  const auth = await requireStaff();
  if (!auth.ok) return auth.response;
  const supabase = await createClient();
  const fail = (m: string) => NextResponse.json({ error: m }, { status: 400 });

  const { data: tenant } = await supabase.from('fnd_tenants').select('tenant_name').eq('tenant_id', tenantId).maybeSingle();
  const company = (tenant?.tenant_name as string | undefined) ?? '';
  const base = REPORT_TYPES[kind];
  const stamp = (kind === 'sales' ? (to as string) : (asOf as string));

  type Piece = { customerId: number | null; title: string; fileName: string; bytes: Uint8Array; parameters: Record<string, unknown> };
  const pieces: Piece[] = [];
  let combined: Uint8Array;
  let title: string;

  if (kind === 'statements') {
    const includeCredits = body?.include_credits === true;
    const all = [];
    for (const id of customerIds) {
      const { data, error } = await supabase.rpc('ar_statement_get', { p_tenant_id: tenantId, p_account_id: id, p_as_of: asOf, p_include_credits: includeCredits });
      if (error) return fail(error.message);
      all.push(data);
      pieces.push({
        customerId: id, title: `Statement ${data.customer_name} - as of ${asOf}`, fileName: `statement-${data.customer_number ?? id}-${asOf}.pdf`,
        bytes: await statementPdf([data]), parameters: { kind, as_of: asOf, include_credits: includeCredits, customer_ids: [id], customer_names: [data.customer_name] },
      });
    }
    combined = await statementPdf(all);
    title = `${base.title}s - as of ${asOf}`;
  } else {
    let data;
    let spec;
    if (kind === 'ar' || kind === 'aging') {
      const fn = kind === 'ar' ? 'ar_open_balances_get' : 'ar_aging_get';
      const r = await supabase.rpc(fn, { p_tenant_id: tenantId, p_account_ids: customerIds, p_as_of: asOf });
      if (r.error) return fail(r.error.message);
      data = r.data;
      spec = kind === 'ar' ? openBalancesSpec(data, company) : agingSpec(data, company);
    } else if (kind === 'sales') {
      const r = await supabase.rpc('ar_sales_report_get', { p_tenant_id: tenantId, p_account_ids: customerIds, p_from: from, p_to: to });
      if (r.error) return fail(r.error.message);
      data = r.data;
      spec = salesSpec(data, company);
    } else {
      const lookback = toInt(body?.lookback_weeks) ?? 8;
      const horizon = toInt(body?.horizon_weeks) ?? 4;
      const r = await supabase.rpc('ar_revenue_forecast_get', { p_tenant_id: tenantId, p_account_ids: customerIds, p_as_of: asOf, p_lookback_weeks: lookback, p_horizon_weeks: horizon });
      if (r.error) return fail(r.error.message);
      data = r.data;
      spec = forecastSpec(data, company);
    }
    combined = await renderSpecs([spec]);
    title = spec.title;
    const names = (data.accounts as { customer_name: string }[]).map((a) => a.customer_name);
    pieces.push({
      customerId: customerIds.length === 1 ? customerIds[0] : null, title, fileName: `${base.title.toLowerCase().replace(/\s+/g, '-')}-${stamp}.pdf`, bytes: combined,
      parameters: { kind, as_of: asOf ?? null, from: from ?? null, to: to ?? null, lookback_weeks: body?.lookback_weeks ?? null, horizon_weeks: body?.horizon_weeks ?? null, customer_ids: customerIds, customer_names: names },
    });
  }

  const savedIds: number[] = [];
  if (body?.save === true) {
    for (const p of pieces) {
      const { data, error } = await supabase.rpc('fnd_document_save', {
        p_tenant_id: tenantId,
        p_payload: {
          document_type: base.documentType, title: p.title, as_of_date: stamp, customer_id: p.customerId, parameters: p.parameters,
          file_name: p.fileName, content_base64: toB64(p.bytes),
        },
      });
      if (error) return fail(error.message);
      savedIds.push(data as number);
    }
  }

  return NextResponse.json({ data: { title, file_name: pieces[0]?.fileName ?? 'report.pdf', pdf_base64: toB64(combined), saved_ids: savedIds } });
}
