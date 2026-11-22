import { cell, createWriter, ensure, footerPageNumbers, LETTER, money, newPage, qty, rule, text, wrap, type Writer } from './kit';

export interface PackagingData {
  invoices: {
    document_number: string;
    customer_name: string;
    customer_number: string | null;
    production_date: string;
    production_code: string;
    delivery_date: string;
    amount: number;
    copies: number;
    orders: {
      order_number: string | null;
      department_event: string | null;
      po_number: string | null;
      order_total: number;
      lines: { line_number: number; source_type: string; item_description: string | null; quantity: number; unit_price: number; amount: number }[];
    }[];
  }[];
}

const X = { qty: 40, desc: 90, priceRight: 480, amountRight: 572 };

function invoiceHeader(w: Writer, inv: PackagingData['invoices'][number], copy: number, copies: number): void {
  text(w, 'INVOICE / PACKING LIST', { size: 16, bold: true }, 20);
  const top = w.y;
  cell(w, inv.document_number, X.qty, top, { size: 14, bold: true });
  cell(w, `Deliver ${inv.delivery_date}`, X.amountRight, top, { size: 10, bold: true, align: 'right', right: X.amountRight });
  w.y -= 20;
  text(w, `${inv.customer_name}${inv.customer_number ? `  (${inv.customer_number})` : ''}`, { size: 12, bold: true }, 16);
  text(w, `Production ${inv.production_date}  -  ${inv.production_code}${copies > 1 ? `   Copy ${copy} of ${copies}` : ''}`, { size: 9, muted: true }, 14);
  rule(w, 6);
}

/** Packaging list = the invoice that goes in the bag: lines grouped by order and department/event. */
export async function packagingPdf(data: PackagingData, generatedLabel: string): Promise<Uint8Array> {
  const w = await createWriter(LETTER);
  let first = true;
  for (const inv of data.invoices) {
    const copies = Math.max(1, inv.copies || 1);
    for (let copy = 1; copy <= copies; copy++) {
      if (!first) {
        w.page = w.doc.addPage([w.size.width, w.size.height]);
        w.y = w.size.height - w.margin;
      }
      first = false;
      w.onNewPage = (ww) => invoiceHeader(ww, inv, copy, copies);
      invoiceHeader(w, inv, copy, copies);

      inv.orders.forEach((order) => {
        ensure(w, 60);
        const label = [`Order ${order.order_number ?? ''}`, order.department_event ?? '', order.po_number ? `PO ${order.po_number}` : '']
          .filter(Boolean).join('  -  ');
        text(w, label, { size: 10, bold: true }, 14);
        order.lines.forEach((line) => {
          const desc = wrap(line.item_description ?? '', w.font, 9, X.priceRight - X.desc - 50);
          ensure(w, desc.length * 12 + 2);
          const y = w.y;
          cell(w, qty(line.quantity), X.qty, y, { size: 9 });
          desc.forEach((d, i) => cell(w, d, X.desc, y - i * 12, { size: 9 }));
          cell(w, money(line.unit_price), X.priceRight, y, { size: 9, muted: true, align: 'right', right: X.priceRight });
          cell(w, money(line.amount), X.amountRight, y, { size: 9, align: 'right', right: X.amountRight });
          w.y -= desc.length * 12 + 1;
        });
        const y = w.y;
        cell(w, 'Order total', X.priceRight, y, { size: 9, bold: true, align: 'right', right: X.priceRight });
        cell(w, money(order.order_total), X.amountRight, y, { size: 9, bold: true, align: 'right', right: X.amountRight });
        w.y -= 18;
      });

      ensure(w, 30);
      rule(w, 6);
      const y = w.y;
      cell(w, 'Invoice total', X.priceRight, y, { size: 12, bold: true, align: 'right', right: X.priceRight });
      cell(w, `$${money(inv.amount)}`, X.amountRight, y, { size: 12, bold: true, align: 'right', right: X.amountRight });
      w.y -= 20;
    }
  }
  w.onNewPage = undefined;
  footerPageNumbers(w.doc, w.font, `Packaging List - ${generatedLabel}`);
  return w.doc.save();
}
