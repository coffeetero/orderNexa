import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from 'pdf-lib';

/**
 * Invoices in the old BPS layout (Letter, portrait), one or more pages per invoice. Positions are in points, measured
 * from the old invoice. Every value comes from ar_invoices_print_get; this only draws them.
 */
export interface InvoiceLine { item_number: string | null; description: string | null; quantity: number; unit: string | null; unit_price: number; amount: number }
export interface InvoiceGroup { department_event: string | null; department_number: string | null; subtotal: number; lines: InvoiceLine[] }
export interface PrintInvoice {
  document_number: string; production_date: string; weekday: string; production_code_label: string;
  account_type: string | null; customer_name: string; customer_number: string | null; address_lines: string[]; phone: string | null;
  item_quantity: number; item_amount: number; delivery_amount: number; amount: number; groups: InvoiceGroup[];
}
export interface InvoicesData { company_name: string; footer_note: string | null; tagline: string | null; invoices: PrintInvoice[] }

const BLACK = rgb(0, 0, 0);
const GREY = rgb(0.86, 0.86, 0.86);
const LINE = rgb(0.6, 0.6, 0.6);
const PAGE: [number, number] = [612, 792];
const L = 31;           // left margin
const R = 574;          // right edge
const ROW = 15;
const BOTTOM = 92;      // the footer starts below this

// header box: [label, x from, x to]
const BOX = [['Acct. Type', 270, 323], ['Cstmr No', 323, 379], ['Date', 379, 432], ['Delivery Time', 432, 505], ['Invoice No.', 505, R]] as const;
// footer totals: [label, x from, x to]
const FOOT = [['Ttl Items', 224, 270], ['Ttl Item Amt', 270, 319], ['Dlvry chrg', 319, 365], ['', 365, 415]] as const;
const FOOT_TOTAL = [501, R] as const;

const safe = (s: string) => s.replace(/[–—]/g, '-').replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/[^\x20-\x7e\xa0-\xff]/g, '?');
const money = (v: unknown) => Number(v ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const qty = (v: unknown) => Number(v ?? 0).toLocaleString('en-US', { maximumFractionDigits: 3 });
/** 2026-11-20 → 11.20.26 */
const shortDate = (v: string) => (v ? `${v.slice(5, 7)}.${v.slice(8, 10)}.${v.slice(2, 4)}` : '');

export async function invoicesPdf(data: InvoicesData): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);

  for (const inv of data.invoices) {
    const pages: PDFPage[] = [];
    let page!: PDFPage;
    let y = 0;   // baseline of the current row, from the bottom

    const text = (t: string, x: number, size: number, f: PDFFont = font) => page.drawText(safe(t), { x, y, size, font: f, color: BLACK });
    const right = (t: string, xr: number, size: number, f: PDFFont = font) => text(t, xr - f.widthOfTextAtSize(safe(t), size), size, f);
    const center = (t: string, a: number, b: number, size: number, f: PDFFont = font) => text(t, a + (b - a - f.widthOfTextAtSize(safe(t), size)) / 2, size, f);
    const cell = (a: number, b: number, top: number, h: number, fill?: typeof GREY) =>
      page.drawRectangle({ x: a, y: top - h, width: b - a, height: h, borderColor: LINE, borderWidth: 0.6, ...(fill ? { color: fill } : {}) });

    const newPage = () => {
      page = pdf.addPage(PAGE);
      pages.push(page);
      // customer, top left
      y = 792 - 162; text(inv.customer_name, L, 9.5, bold);
      const addr = [...inv.address_lines];
      y -= 16; if (addr[0]) text(addr[0], L, 7.5);
      y -= 11;   // the old invoice leaves a blank line after the street
      for (const a of addr.slice(1)) { y -= 11; text(a, L, 7.5); }
      if (inv.phone) { y -= 11; text(inv.phone, L, 7.5); }
      // header box, top right
      const top = 792 - 153;
      for (const [label, a, b] of BOX) { cell(a, b, top, 9, GREY); y = top - 7; center(label, a, b, 6.5, bold); }
      const values = [inv.account_type ?? '', inv.customer_number ?? '', shortDate(inv.production_date), inv.production_code_label ?? '', inv.document_number];
      BOX.forEach(([, a, b], i) => { cell(a, b, top - 9, 13); y = top - 19; center(values[i], a, b, 8.5); });
      // company and weekday
      y = 792 - 240; text(data.company_name.toUpperCase(), L, 9);
      right(inv.weekday, R, 9, bold);
      // column bar
      const bar = 792 - 248;
      page.drawRectangle({ x: L, y: bar - 10, width: R - L, height: 10, color: GREY, borderColor: LINE, borderWidth: 0.6 });
      y = bar - 7.5;
      center('Item No', L, 80, 6.5, bold); center('Description', 86, 318, 6.5, bold);
      right('QTY', 340, 6.5, bold); text('Unit', 345, 6.5, bold);
      right('Price', 522, 6.5, bold); right('Total', R - 2, 6.5, bold);
      y = bar - 10 - 12;
    };
    const room = (rows: number) => { if (y - rows * ROW < BOTTOM) newPage(); };

    newPage();
    for (const g of inv.groups) {
      room(3);
      const heading = [g.department_event ?? 'Other', g.department_number ? `(${g.department_number})` : ''].filter(Boolean).join(' ');
      text(heading, L, 8.5, bold);
      y -= ROW;
      for (const ln of g.lines) {
        room(1);
        right(ln.item_number ?? '', 72, 8.5);
        text(ln.description ?? '', 86, 8.5);
        right(qty(ln.quantity), 340, 8.5, bold);
        text(ln.unit ?? '', 345, 6);
        right(money(ln.unit_price), 522, 8.5);
        right(money(ln.amount), R - 2, 8.5);
        y -= ROW;
      }
      y += 3;
      right(money(g.subtotal), R - 2, 8.5, bold);
      y -= ROW + 3;
    }

    // footer on every page: allergen note, totals, tagline; then "Page x of y"
    pages.forEach((p, i) => {
      page = p;
      y = 792 - 742; if (data.footer_note) center(data.footer_note, L, R, 5.5);
      const top = 792 - 746;
      for (const [label, a, b] of FOOT) { cell(a, b, top, 9, GREY); y = top - 7; if (label) center(label, a, b, 6, font); }
      cell(FOOT_TOTAL[0], FOOT_TOTAL[1], top, 9, GREY); y = top - 7; center('Ttl Invc Amt', FOOT_TOTAL[0], FOOT_TOTAL[1], 6);
      const vals = [qty(inv.item_quantity), money(inv.item_amount), money(inv.delivery_amount), ''];
      FOOT.forEach(([, a, b], k) => { cell(a, b, top - 9, 13); y = top - 19; center(vals[k], a, b, 8.5); });
      cell(L, 224, top - 9, 13);
      cell(FOOT_TOTAL[0], FOOT_TOTAL[1], top - 9, 13); y = top - 19; center(`$${money(inv.amount)}`, FOOT_TOTAL[0], FOOT_TOTAL[1], 9, bold);
      y = 792 - 785; if (data.tagline) center(`'${data.tagline}'`, L, R, 9, bold);
      y = 792 - 143; right(`Page ${i + 1} of ${pages.length}`, R, 7.5);
    });
  }
  return pdf.save();
}
