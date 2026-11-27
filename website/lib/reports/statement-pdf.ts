import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from 'pdf-lib';
import { money } from './pdf';

/** Customer statement in the old BPS layout (Letter, portrait). Positions are in points, measured from the old PDF. */
type Json = any;

const BLACK = rgb(0, 0, 0);
const WHITE = rgb(1, 1, 1);
const PAGE: [number, number] = [612, 792];
const TOP = 792 - 146;        // the old statement leaves the top of the page for the letterhead
const BOTTOM = 60;
const ROW = 12.6;
const SIZE = 8;

// column bars: [x from, x to]
const COL = { date: [53, 98], type: [101, 143], ref: [146, 188], desc: [191, 376], amt: [396, 446], open: [489, 558] } as const;
// header box cells
const BOX = [
  { label: 'Customer No', x: [286, 349] }, { label: 'Fax No.', x: [350, 414] },
  { label: 'Statement Date', x: [416, 486] }, { label: 'Ttl Balance', x: [489, 558] },
] as const;

const safe = (s: string) => s.replace(/[–—]/g, '-').replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/[^\x20-\x7e\xa0-\xff]/g, '?');
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** 2026-11-02 → 11.02.26 */
export const shortDate = (v: string) => (v ? `${v.slice(5, 7)}.${v.slice(8, 10)}.${v.slice(2, 4)}` : '');
/** 2026-11-24 → Nov. 24, 2026 */
export const longDate = (v: string) => (v ? `${MONTHS[Number(v.slice(5, 7)) - 1]}. ${Number(v.slice(8, 10))}, ${v.slice(0, 4)}` : '');
const dollars = (v: unknown) => `$ ${money(v)}`;

export async function statementPdf(statements: Json[]): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  // Shown in the browser's PDF viewer instead of the preview's blob id.
  pdf.setTitle(statements.length === 1 ? `Statement ${statements[0].customer_name}` : 'Customer Statements', { showInWindowTitleBar: true });
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);

  for (const s of statements) {
    const pages: PDFPage[] = [];
    let page!: PDFPage;
    let y = 0;

    const text = (t: string, x: number, size: number, f: PDFFont = font, color = BLACK) => page.drawText(safe(t), { x, y, size, font: f, color });
    const right = (t: string, xr: number, size: number, f: PDFFont = font) => text(t, xr - f.widthOfTextAtSize(safe(t), size), size, f);
    const center = (t: string, [a, b]: readonly [number, number], size: number, f: PDFFont, color = BLACK) =>
      text(t, a + (b - a - f.widthOfTextAtSize(safe(t), size)) / 2, size, f, color);
    const bar = ([a, b]: readonly [number, number], label: string) => {
      page.drawRectangle({ x: a, y: y - 2.5, width: b - a, height: 10, color: BLACK });
      center(label, [a, b], 7, bold, WHITE);
    };
    const box = ([a, b]: readonly [number, number]) => page.drawRectangle({ x: a, y: y - 3, width: b - a, height: 11, borderColor: BLACK, borderWidth: 0.8 });
    const heading = `${s.customer_name}${s.customer_number ? ` (${s.customer_number})` : ''}`;

    const newPage = () => {
      page = pdf.addPage(PAGE);
      pages.push(page);
      y = TOP;
      // name and billing address, top left
      for (const line of [s.customer_name, ...(s.address_lines as string[])]) { text(line, 53, 8); y -= 10.5; }
      // title, page number and the header box, top right
      y = TOP - 16;
      text('Customer Statement', 286, 12.5, bold);   // "Page x of y" is drawn once the statement is complete
      y = TOP - 28;
      for (const c of BOX) bar(c.x, c.label);
      y -= 11;
      const values = [s.customer_number_display ?? s.customer_number ?? '', '', longDate(s.as_of), dollars(s.total_due)];
      BOX.forEach((c, i) => { box(c.x); center(values[i], c.x, 7.5, bold); });
      // column bars
      y = TOP - 66;
      bar(COL.date, 'Trn Date'); bar(COL.type, 'Trn Type'); bar(COL.ref, 'Trn Ref');
      bar(COL.desc, 'Transaction Description'); bar(COL.amt, 'Trn Amt'); bar(COL.open, 'Open Amt');
      // account heading with its total
      y -= 13;
      text(heading, 53, 8, bold);
      box(COL.open); right(dollars(s.total_due), COL.open[1] - 2, 7.5, bold);
      y -= ROW;
    };
    const room = (rows: number) => { if (y - rows * ROW < BOTTOM) newPage(); };

    newPage();
    const weeks = s.weeks as Json[];
    if (weeks.length === 0) { text('Nothing open.', 57, SIZE); y -= ROW; }
    weeks.forEach((w, wi) => {
      for (const it of w.items as Json[]) {
        room(2);
        text(shortDate(it.date), 57, SIZE);
        text(it.type, 116, SIZE);
        text(String(it.number), 146, SIZE);
        right(money(it.amount), COL.amt[1], SIZE);
        right(money(it.open), COL.open[1] - 1, SIZE);
        y -= ROW;
      }
      right(dollars(w.subtotal), COL.open[1] - 1, SIZE, bold);
      y -= ROW + (wi < weeks.length - 1 ? 4 : 0);
    });

    // aging of the items listed above (follows Include Credits, so its total equals Ttl Balance)
    room(4);
    y -= 10;
    const g = s.aging ?? {};
    const AG = [['Current', g.current_amt], ['1-30', g.d1_30], ['31-60', g.d31_60], ['61-90', g.d61_90], ['Over 90', g.d90_plus], ['Total', g.total]] as const;
    const w = (COL.open[1] - COL.date[0]) / AG.length;
    AG.forEach(([label], i) => bar([COL.date[0] + i * w + 1, COL.date[0] + (i + 1) * w - 1], label));
    y -= 11;
    AG.forEach(([, v], i) => { const c: [number, number] = [COL.date[0] + i * w + 1, COL.date[0] + (i + 1) * w - 1]; box(c); center(money(v), c, 7.5, font); });

    pages.forEach((p, i) => {
      const label = `Page ${i + 1} of ${pages.length}`;
      p.drawText(label, { x: COL.open[1] - font.widthOfTextAtSize(label, 8), y: TOP - 10, size: 8, font, color: BLACK });
    });
  }
  return pdf.save();
}
