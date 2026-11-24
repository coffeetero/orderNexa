import { describe, expect, it } from 'vitest';
import { agingSpec, forecastSpec, invoiceSpec, openBalancesSpec, salesSpec } from '../reports/financial';
import { money, renderPdf } from '../reports/pdf';
import { longDate, shortDate, statementPdf } from '../reports/statement-pdf';

const acct = { customer_id: 1, customer_name: 'BEL PANE – “Main”', customer_number: '11700' };
const header = (b: Uint8Array) => Buffer.from(b.slice(0, 5)).toString('latin1');

describe('financial report specs', () => {
  it('formats money with thousands and two decimals', () => {
    expect(money(1234.5)).toBe('1,234.50');
    expect(money(null)).toBe('0.00');
  });

  it('builds a valid PDF for every report kind', async () => {
    const specs = [
      openBalancesSpec({ as_of: '2026-11-23', accounts: [{ ...acct, balance: 10, items: [{ document_number: 'INV-1', type: 'INV', date: '2026-10-01', due_date: '2026-10-31', amount: 25, paid: 10, open: 15 }] }] }, 'Alpine Bakery'),
      agingSpec({ as_of: '2026-11-23', accounts: [{ ...acct, current_amt: 0, d1_30: 0, d31_60: 15, d61_90: 0, d90_plus: 0, total: 15 }], totals: { current_amt: 0, d1_30: 0, d31_60: 15, d61_90: 0, d90_plus: 0, total: 15 } }, 'Alpine Bakery'),
      salesSpec({ from: '2026-11-01', to: '2026-11-23', accounts: [{ ...acct, invoiced: 25, credits: -5, net: 20, items: [{ item: 'bread', quantity: 10, amount: 25 }] }], totals: { invoiced: 25, credits: -5, net: 20 } }, 'Alpine Bakery'),
      forecastSpec({ as_of: '2026-11-23', history_from: '2026-09-28', lookback_weeks: 8, horizon_weeks: 4, accounts: [{ ...acct, history_total: 20, weekly_average: 2.5, projected_total: 10, first_half: 5, second_half: 15 }], totals: { history_total: 20, weekly_average: 2.5, projected_total: 10 } }, 'Alpine Bakery'),
      invoiceSpec({ document_number: 'INV-1', company_name: 'Alpine Bakery', ...acct, transaction_date: '2026-10-01', due_date: null, amount: 25, lines: [{ line: 1, description: 'bread', quantity: 10, unit_price: 2.5, amount: 25 }] }),
    ];
    for (const spec of specs) {
      const bytes = await renderPdf([spec]);
      expect(header(bytes)).toBe('%PDF-');
      expect(bytes.length).toBeGreaterThan(800);
    }
  });

  it('formats statement dates like the old BPS', () => {
    expect(shortDate('2026-11-02')).toBe('11.02.26');
    expect(longDate('2026-11-24')).toBe('Nov. 24, 2026');
  });

  it('builds the old-layout statement, one or more pages per customer', async () => {
    const items = Array.from({ length: 70 }, (_, i) => ({ date: '2026-10-01', type: 'INV', number: String(545000 + i), amount: 10, open: 10 }));
    const stmt = (weeks: unknown[]) => ({ ...acct, customer_number_display: '117-00', address_lines: ['PO BOX 1', 'NEWARK, NJ 07101'], as_of: '2026-11-24',
      include_credits: false, total_due: 10, weeks, aging: { current_amt: 0, d1_30: 0, d31_60: 10, d61_90: 0, d90_plus: 0, total: 10 } });
    const short = stmt([{ week_start: '2026-09-28', subtotal: 10, items: items.slice(0, 1) }]);
    const long = stmt([{ week_start: '2026-09-28', subtotal: 700, items }]);
    const bytes = await statementPdf([short, long]);
    expect(header(bytes)).toBe('%PDF-');
    const { PDFDocument } = await import('pdf-lib');
    expect((await PDFDocument.load(bytes)).getPageCount()).toBeGreaterThanOrEqual(3);
  });

  it('continues a long table on more pages and combines several statements in one file', async () => {
    const rows = Array.from({ length: 120 }, (_, i) => [`R${i}`, 'x']);
    const one = await renderPdf([{ title: 't', company: 'c', sections: [{ columns: [{ label: 'a', width: 1 }, { label: 'b', width: 1 }], rows }] }]);
    const two = await renderPdf([{ title: 't', company: 'c', sections: [{ columns: [{ label: 'a', width: 1 }, { label: 'b', width: 1 }], rows: [] }] }, { title: 'u', company: 'c', sections: [{ columns: [{ label: 'a', width: 1 }], rows: [['z']] }] }]);
    const { PDFDocument } = await import('pdf-lib');
    expect((await PDFDocument.load(one)).getPageCount()).toBeGreaterThan(2);
    expect((await PDFDocument.load(two)).getPageCount()).toBe(2);
  });
});
