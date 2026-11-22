import { cell, createWriter, ensure, footerPageNumbers, LETTER, qty, rule, text, wrap } from './kit';

export interface DeliveryData {
  stops: {
    delivery_date: string;
    route: string | null;
    shipment_number: string;
    customer_name: string;
    customer_number: string | null;
    address: string | null;
    delivery_method: string | null;
    invoice_numbers: string[];
    items: { item_name: string | null; quantity: number }[];
  }[];
}

/** Route delivery report for the driver: stops by delivery date and route, with invoices, items and a signature line. */
export async function deliveryPdf(data: DeliveryData, generatedLabel: string): Promise<Uint8Array> {
  const w = await createWriter(LETTER);
  let current = '';
  text(w, 'Route Delivery Report', { size: 18, bold: true }, 24);
  data.stops.forEach((stop, i) => {
    const groupKey = `${stop.delivery_date}|${stop.route ?? ''}`;
    ensure(w, 110);
    if (groupKey !== current) {
      current = groupKey;
      if (i > 0) w.y -= 6;
      text(w, `Delivery ${stop.delivery_date}${stop.route ? `  -  Route ${stop.route}` : ''}`, { size: 12, bold: true }, 16);
      rule(w, 4);
    }
    text(w, `${i + 1}.  ${stop.customer_name}${stop.customer_number ? `  (${stop.customer_number})` : ''}`, { size: 11, bold: true }, 14);
    if (stop.address) wrap(stop.address, w.font, 9, 500).forEach((line) => text(w, line, { size: 9, muted: true, x: 56 }, 11));
    text(
      w,
      `Shipment ${stop.shipment_number}${stop.invoice_numbers.length ? `   Invoice ${stop.invoice_numbers.join(', ')}` : '   (invoice not printed yet)'}`,
      { size: 9, x: 56 },
      12,
    );
    stop.items.forEach((item) => {
      ensure(w, 13);
      const y = w.y;
      cell(w, qty(item.quantity), 80, y, { size: 9, bold: true, align: 'right', right: 100 });
      cell(w, item.item_name ?? '', 108, y, { size: 9 });
      w.y -= 12;
    });
    ensure(w, 24);
    w.y -= 4;
    cell(w, 'Received by: ____________________________', 56, w.y, { size: 9, muted: true });
    cell(w, 'Time: __________', 420, w.y, { size: 9, muted: true });
    w.y -= 24;
  });
  footerPageNumbers(w.doc, w.font, `Route Delivery Report - ${generatedLabel}`);
  return w.doc.save();
}
