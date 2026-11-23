import { cell, createWriter, ensure, footerPageNumbers, LETTER, qty, rule, text, wrap, type Writer } from './kit';

export interface BakersData {
  runs: {
    production_date: string;
    production_code: string;
    delivery_date: string;
    order_count: number;
    total_quantity: number;
    last_printed_at: string | null;
    changed_since_print: boolean;
    /** Compound items ordered in the run. Their components are already counted in the categories below; they are not part of the totals. */
    compounds?: { item_number: string | null; item_name: string | null; quantity: number; order_count: number }[];
    categories: {
      category: string;
      total_quantity: number;
      items: { item_number: string | null; item_name: string | null; dough_type: string | null; unit_of_sale: string | null; quantity: number; in_compounds?: number; order_count: number }[];
    }[];
  }[];
}

const COLS = { num: 40, name: 100, dough: 330, unit: 420, qtyRight: 510, ordersRight: 572 };

function columnHeader(w: Writer): void {
  const y = w.y;
  cell(w, 'Item #', COLS.num, y, { size: 8, bold: true, muted: true });
  cell(w, 'Item', COLS.name, y, { size: 8, bold: true, muted: true });
  cell(w, 'Dough', COLS.dough, y, { size: 8, bold: true, muted: true });
  cell(w, 'Unit', COLS.unit, y, { size: 8, bold: true, muted: true });
  cell(w, 'Quantity', COLS.qtyRight, y, { size: 8, bold: true, muted: true, align: 'right', right: COLS.qtyRight });
  cell(w, 'Orders', COLS.ordersRight, y, { size: 8, bold: true, muted: true, align: 'right', right: COLS.ordersRight });
  w.y -= 12;
  rule(w, 3);
}

/** Baker's Report: one section per run, items grouped by category with totals. */
export async function bakersPdf(data: BakersData, generatedLabel: string): Promise<Uint8Array> {
  const w = await createWriter(LETTER);
  data.runs.forEach((run, runIndex) => {
    if (runIndex > 0) {
      w.page = w.doc.addPage([w.size.width, w.size.height]);
      w.y = w.size.height - w.margin;
    }
    text(w, "Baker's Report", { size: 18, bold: true }, 24);
    text(w, `Production ${run.production_date}  -  ${run.production_code}`, { size: 12, bold: true }, 16);
    text(w, `Delivery ${run.delivery_date}  -  ${run.order_count} orders  -  ${qty(run.total_quantity)} units`, { size: 10, muted: true }, 14);
    if (run.changed_since_print) {
      text(w, `CHANGED SINCE LAST PRINT (${run.last_printed_at ? run.last_printed_at.slice(0, 16).replace('T', ' ') : ''})`, { size: 10, bold: true }, 14);
    }
    w.y -= 4;
    run.categories.forEach((cat) => {
      ensure(w, 60);
      text(w, cat.category, { size: 11, bold: true }, 16);
      columnHeader(w);
      cat.items.forEach((item) => {
        ensure(w, 16);
        const y = w.y;
        cell(w, item.item_number ?? '', COLS.num, y, { size: 9 });
        const nameLines = wrap(item.item_name ?? '', w.font, 9, COLS.dough - COLS.name - 8);
        cell(w, nameLines[0], COLS.name, y, { size: 9 });
        if ((item.in_compounds ?? 0) > 0) {
          const x = COLS.name + w.font.widthOfTextAtSize(nameLines[0], 9) + 6;
          const note = `(${qty(item.in_compounds ?? 0)} in sets)`;
          if (x + w.font.widthOfTextAtSize(note, 7) < COLS.dough - 4) cell(w, note, x, y, { size: 7, muted: true });
        }
        cell(w, item.dough_type ?? '', COLS.dough, y, { size: 9 });
        cell(w, item.unit_of_sale ?? '', COLS.unit, y, { size: 9 });
        cell(w, qty(item.quantity), COLS.qtyRight, y, { size: 9, bold: true, align: 'right', right: COLS.qtyRight });
        cell(w, String(item.order_count), COLS.ordersRight, y, { size: 9, muted: true, align: 'right', right: COLS.ordersRight });
        w.y -= 13;
      });
      rule(w, 3);
      const y = w.y;
      cell(w, `${cat.category} total`, COLS.name, y, { size: 9, bold: true });
      cell(w, qty(cat.total_quantity), COLS.qtyRight, y, { size: 9, bold: true, align: 'right', right: COLS.qtyRight });
      w.y -= 20;
    });
    ensure(w, 24);
    text(w, `Run total: ${qty(run.total_quantity)} units`, { size: 11, bold: true });
    if (run.compounds && run.compounds.length > 0) {
      w.y -= 10;
      ensure(w, 50);
      text(w, 'Compound items to assemble', { size: 11, bold: true }, 14);
      text(w, 'Their components are already counted in the quantities above; these are not added to the totals.', { size: 8, muted: true }, 12);
      const y0 = w.y;
      cell(w, 'Item #', COLS.num, y0, { size: 8, bold: true, muted: true });
      cell(w, 'Item', COLS.name, y0, { size: 8, bold: true, muted: true });
      cell(w, 'Quantity', COLS.qtyRight, y0, { size: 8, bold: true, muted: true, align: 'right', right: COLS.qtyRight });
      cell(w, 'Orders', COLS.ordersRight, y0, { size: 8, bold: true, muted: true, align: 'right', right: COLS.ordersRight });
      w.y -= 12;
      rule(w, 3);
      run.compounds.forEach((c) => {
        ensure(w, 16);
        const y = w.y;
        cell(w, c.item_number ?? '', COLS.num, y, { size: 9 });
        cell(w, wrap(c.item_name ?? '', w.font, 9, COLS.qtyRight - COLS.name - 60)[0], COLS.name, y, { size: 9 });
        cell(w, qty(c.quantity), COLS.qtyRight, y, { size: 9, bold: true, align: 'right', right: COLS.qtyRight });
        cell(w, String(c.order_count), COLS.ordersRight, y, { size: 9, muted: true, align: 'right', right: COLS.ordersRight });
        w.y -= 13;
      });
    }
  });
  footerPageNumbers(w.doc, w.font, `Baker's Report - ${generatedLabel}`);
  return w.doc.save();
}
