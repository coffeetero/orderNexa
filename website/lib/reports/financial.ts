import { day, money, qty, renderPdf, type PdfSpec } from './pdf';

export type ReportKind = 'ar' | 'aging' | 'statements' | 'sales' | 'forecast';

export const REPORT_TYPES: Record<ReportKind, { documentType: string; title: string }> = {
  ar: { documentType: 'AR_OPEN_BALANCES', title: 'AR Open Balances' },
  aging: { documentType: 'AR_AGING', title: 'AR Aging Report' },
  statements: { documentType: 'STATEMENT', title: 'Customer Statement' },
  sales: { documentType: 'SALES', title: 'Sales Report' },
  forecast: { documentType: 'FORECAST', title: 'Revenue Forecast' },
};

type Json = any;
const label = (a: Json) => `${a.customer_name}${a.customer_number ? ` (${a.customer_number})` : ''}`;
const TYPE_NAME: Record<string, string> = { INV: 'Invoice', CM: 'Credit memo', PMT: 'Payment' };

export function openBalancesSpec(data: Json, company: string): PdfSpec {
  const accounts: Json[] = data.accounts;
  return {
    title: `AR Open Balances - as of ${day(data.as_of)}`, company, landscape: true,
    subtitle: [`${accounts.length} account${accounts.length === 1 ? '' : 's'} selected. Amounts in dollars.`],
    sections: [
      ...accounts.map((a) => ({
        heading: `${label(a)}  -  balance ${money(a.balance)}`,
        columns: [
          { label: 'Document', width: 14 }, { label: 'Type', width: 10 }, { label: 'Date', width: 10 }, { label: 'Due', width: 10 },
          { label: 'Amount', width: 10, align: 'right' as const }, { label: 'Paid', width: 10, align: 'right' as const }, { label: 'Open', width: 10, align: 'right' as const },
        ],
        rows: (a.items as Json[]).map((i) => [i.document_number, TYPE_NAME[i.type] ?? i.type, day(i.date), day(i.due_date), money(i.amount), money(i.paid), money(i.open)]),
        footer: ['', '', '', '', '', 'Balance', money(a.balance)],
      })),
      {
        heading: 'All selected accounts',
        columns: [{ label: 'Total open balance', width: 60 }, { label: '', width: 10, align: 'right' as const }],
        rows: [], footer: ['Total open balance', money(accounts.reduce((s, a) => s + Number(a.balance), 0))],
      },
    ],
  };
}

export function agingSpec(data: Json, company: string): PdfSpec {
  const t = data.totals;
  const accounts = (data.accounts as Json[]).filter((a) => Number(a.total) !== 0);
  return {
    title: `AR Aging Report - as of ${day(data.as_of)}`, company, landscape: true,
    subtitle: ['Days past due date (the document date when no due date is set). Accounts with nothing open are not listed.'],
    sections: [{
      columns: [
        { label: 'Customer', width: 30 }, { label: 'Current', width: 10, align: 'right' }, { label: '1-30', width: 10, align: 'right' },
        { label: '31-60', width: 10, align: 'right' }, { label: '61-90', width: 10, align: 'right' }, { label: 'Over 90', width: 10, align: 'right' }, { label: 'Total', width: 12, align: 'right' },
      ],
      rows: accounts.map((a) => [label(a), money(a.current_amt), money(a.d1_30), money(a.d31_60), money(a.d61_90), money(a.d90_plus), money(a.total)]),
      footer: ['Total', money(t.current_amt), money(t.d1_30), money(t.d31_60), money(t.d61_90), money(t.d90_plus), money(t.total)],
    }],
  };
}

export function statementSpec(data: Json, company: string): PdfSpec {
  const g = data.aging ?? {};
  return {
    title: `Statement - ${label(data)}`, company,
    subtitle: [`Statement period ${day(data.from)} to ${day(data.as_of)}  (as of ${day(data.as_of)})`],
    sections: [
      {
        columns: [
          { label: 'Date', width: 12 }, { label: 'Type', width: 14 }, { label: 'Number', width: 18 },
          { label: 'Charges', width: 14, align: 'right' }, { label: 'Credits', width: 14, align: 'right' }, { label: 'Balance', width: 14, align: 'right' },
        ],
        note: `Opening balance ${money(data.opening_balance)}`,
        rows: (data.entries as Json[]).map((e) => [day(e.date), TYPE_NAME[e.type] ?? e.type, e.number, Number(e.charge) ? money(e.charge) : '', Number(e.credit) ? money(e.credit) : '', money(e.balance)]),
        footer: ['', '', 'Amount due', '', '', money(data.closing_balance)],
      },
      {
        heading: 'Aging of open items',
        columns: [
          { label: 'Current', width: 1, align: 'right' }, { label: '1-30', width: 1, align: 'right' }, { label: '31-60', width: 1, align: 'right' },
          { label: '61-90', width: 1, align: 'right' }, { label: 'Over 90', width: 1, align: 'right' }, { label: 'Total', width: 1, align: 'right' },
        ],
        rows: [[money(g.current_amt), money(g.d1_30), money(g.d31_60), money(g.d61_90), money(g.d90_plus), money(g.total)]],
      },
    ],
  };
}

export function salesSpec(data: Json, company: string): PdfSpec {
  const t = data.totals;
  const accounts: Json[] = data.accounts;
  return {
    title: `Sales Report - ${day(data.from)} to ${day(data.to)}`, company,
    subtitle: ['Invoiced amounts are what has shipped; credits are credit memos in the period.'],
    sections: [
      {
        heading: 'By customer',
        columns: [{ label: 'Customer', width: 40 }, { label: 'Invoiced', width: 16, align: 'right' }, { label: 'Credits', width: 16, align: 'right' }, { label: 'Net', width: 16, align: 'right' }],
        rows: accounts.map((a) => [label(a), money(a.invoiced), money(a.credits), money(a.net)]),
        footer: ['Total', money(t.invoiced), money(t.credits), money(t.net)],
      },
      ...accounts.filter((a) => (a.items as Json[]).length > 0).map((a) => ({
        heading: `Items - ${label(a)}`,
        columns: [{ label: 'Item', width: 50 }, { label: 'Quantity', width: 15, align: 'right' as const }, { label: 'Amount', width: 15, align: 'right' as const }],
        rows: (a.items as Json[]).map((i) => [i.item, qty(i.quantity), money(i.amount)]),
      })),
    ],
  };
}

export function forecastSpec(data: Json, company: string): PdfSpec {
  const t = data.totals;
  const trend = (a: Json) => {
    const f = Number(a.first_half), s = Number(a.second_half);
    if (f <= 0) return s > 0 ? 'new' : '';
    return `${(((s - f) / f) * 100).toFixed(0)}%`;
  };
  return {
    title: `Revenue Forecast - next ${data.horizon_weeks} weeks from ${day(data.as_of)}`, company, landscape: true,
    subtitle: [
      `Based on net sales (invoiced less credits) from ${day(data.history_from)} to ${day(data.as_of)} (${data.lookback_weeks} weeks), projected at the weekly average.`,
      'Trend compares the second half of the history with the first half.',
    ],
    sections: [{
      columns: [
        { label: 'Customer', width: 30 }, { label: `History (${data.lookback_weeks} wk)`, width: 14, align: 'right' }, { label: 'Weekly average', width: 14, align: 'right' },
        { label: 'Trend', width: 8, align: 'right' }, { label: `Projected (${data.horizon_weeks} wk)`, width: 16, align: 'right' },
      ],
      rows: (data.accounts as Json[]).map((a) => [label(a), money(a.history_total), money(a.weekly_average), trend(a), money(a.projected_total)]),
      footer: ['Total', money(t.history_total), money(t.weekly_average), '', money(t.projected_total)],
    }],
  };
}

export function invoiceSpec(inv: Json): PdfSpec {
  return {
    title: `Invoice ${inv.document_number}`, company: inv.company_name ?? '',
    subtitle: [`Bill to: ${label(inv)}`, `Invoice date ${day(inv.transaction_date)}${inv.due_date ? `   Due ${day(inv.due_date)}` : ''}`],
    sections: [{
      columns: [{ label: 'Line', width: 6 }, { label: 'Description', width: 50 }, { label: 'Qty', width: 10, align: 'right' }, { label: 'Unit price', width: 14, align: 'right' }, { label: 'Amount', width: 14, align: 'right' }],
      rows: (inv.lines as Json[]).map((l) => [String(l.line ?? ''), l.description ?? '', qty(l.quantity), money(l.unit_price), money(l.amount)]),
      footer: ['', 'Total (shipped items and delivery)', '', '', money(inv.amount)],
    }],
  };
}

export const renderSpecs = renderPdf;
