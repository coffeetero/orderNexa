import { PDFDocument } from 'pdf-lib';
import { describe, expect, it } from 'vitest';
import { bakersPdf } from '../bakers';
import { deliveryPdf } from '../delivery';
import { labelsPdf } from '../labels';
import { packagingPdf } from '../packaging';
import { clean } from '../kit';

const isPdf = (bytes: Uint8Array) => new TextDecoder().decode(bytes.slice(0, 5)) === '%PDF-';

describe('pdf reports', () => {
  it('clean() keeps WinAnsi and replaces the rest', () => {
    expect(clean('Café – “quoted” ✓')).toBe('Café - "quoted" ?');
  });

  it("Baker's Report: a section per run, long lists flow onto more pages", async () => {
    const items = Array.from({ length: 80 }, (_, i) => ({
      item_number: `I${i}`, item_name: `Item ${i}`, dough_type: 'ITALIAN', unit_of_sale: 'EA', quantity: i + 1, order_count: 2,
    }));
    const bytes = await bakersPdf({
      runs: [
        { production_date: '2026-11-23', production_code: 'MORNING', delivery_date: '2026-11-24', order_count: 4, total_quantity: 100,
          last_printed_at: null, changed_since_print: true, categories: [{ category: 'Breads', total_quantity: 100, items }] },
        { production_date: '2026-11-24', production_code: 'LUNCH', delivery_date: '2026-11-25', order_count: 1, total_quantity: 3,
          last_printed_at: null, changed_since_print: false, categories: [] },
      ],
    }, 'test');
    expect(isPdf(bytes)).toBe(true);
    const doc = await PDFDocument.load(bytes);
    expect(doc.getPageCount()).toBeGreaterThanOrEqual(3);
  });

  it('labels: one 4x2 inch page per label', async () => {
    const label = {
      production_date: '2026-11-23', production_code: 'MORNING', delivery_date: '2026-11-24', customer_name: 'Chase Corp',
      department_event: 'BOARD ROOM', order_number: '1000-0001', po_number: 'PO-9', item_number: 'B1', item_name: 'Baguette ’Tradition’',
      quantity: 12, unit_of_sale: 'EA', prep_options: 'Sliced, Bagged',
    };
    const bytes = await labelsPdf({ labels: [label, { ...label, department_event: 'CHASE CORP' }, label] });
    const doc = await PDFDocument.load(bytes);
    expect(doc.getPageCount()).toBe(3);
    const { width, height } = doc.getPage(0).getSize();
    expect([width, height]).toEqual([288, 144]);
  });

  it('packaging: an invoice prints once per copy, with its number', async () => {
    const inv = {
      document_number: 'INV-001000', customer_name: 'Chase Corp', customer_number: '1100', production_date: '2026-11-23',
      production_code: 'MORNING', delivery_date: '2026-11-24', amount: 36, copies: 2,
      orders: [{ order_number: '1000-0001', department_event: 'BOARD ROOM', po_number: null, order_total: 36,
        lines: [{ line_number: 1, source_type: 'ITEM', item_description: 'Baguette', quantity: 12, unit_price: 3, amount: 36 }] }],
    };
    const bytes = await packagingPdf({ invoices: [inv] }, 'test');
    const doc = await PDFDocument.load(bytes);
    expect(doc.getPageCount()).toBe(2);
  });

  it('delivery: renders stops for a route', async () => {
    const bytes = await deliveryPdf({
      stops: [
        { delivery_date: '2026-11-24', route: 'A', shipment_number: 'SHP-001000', customer_name: 'Chase Corp', customer_number: null,
          address: '1 5th Ave, New York, NY', delivery_method: 'Own truck', invoice_numbers: ['INV-001000'], items: [{ item_name: 'Baguette', quantity: 12 }] },
        { delivery_date: '2026-11-24', route: null, shipment_number: 'SHP-001001', customer_name: 'Cafe', customer_number: null,
          address: null, delivery_method: null, invoice_numbers: [], items: [] },
      ],
    }, 'test');
    expect(isPdf(bytes)).toBe(true);
  });
});
