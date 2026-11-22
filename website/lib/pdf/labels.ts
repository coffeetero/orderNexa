import { cell, clean, createWriter, LABEL, qty, text, wrap, type Writer } from './kit';

export interface LabelsData {
  labels: {
    production_date: string;
    production_code: string;
    delivery_date: string | null;
    customer_name: string | null;
    department_event: string | null;
    order_number: string | null;
    po_number: string | null;
    item_number: string | null;
    item_name: string | null;
    quantity: number;
    unit_of_sale: string | null;
    prep_options: string;
  }[];
}

/** Packing labels, 4" x 2", one per order line. */
export async function labelsPdf(data: LabelsData): Promise<Uint8Array> {
  const w: Writer = await createWriter(LABEL, 10);
  data.labels.forEach((l, i) => {
    if (i > 0) {
      w.page = w.doc.addPage([LABEL.width, LABEL.height]);
    }
    w.y = LABEL.height - 10;
    const name = wrap(l.customer_name ?? '', w.bold, 11, LABEL.width - 20)[0];
    text(w, name, { size: 11, bold: true }, 14);
    const event = l.department_event && l.department_event !== (l.customer_name ?? '').toUpperCase() ? l.department_event : '';
    if (event) text(w, event, { size: 9, bold: true }, 12);
    text(w, `Order ${l.order_number ?? ''}${l.po_number ? `   PO ${l.po_number}` : ''}`, { size: 8, muted: true }, 12);
    const item = wrap(`${l.item_name ?? ''}`, w.bold, 13, LABEL.width - 20);
    item.slice(0, 2).forEach((line) => text(w, line, { size: 13, bold: true }, 16));
    text(w, `Qty ${qty(l.quantity)}${l.unit_of_sale ? ` ${l.unit_of_sale}` : ''}`, { size: 12, bold: true }, 15);
    if (l.prep_options) {
      wrap(l.prep_options, w.font, 9, LABEL.width - 20).slice(0, 2).forEach((line) => text(w, line, { size: 9 }, 11));
    }
    cell(w, clean(`Prod ${l.production_date} ${l.production_code}`), 10, 24, { size: 7, muted: true });
    cell(w, clean(`Deliver ${l.delivery_date ?? ''}`), LABEL.width - 10, 24, { size: 7, muted: true, align: 'right', right: LABEL.width - 10 });
  });
  return w.doc.save();
}
