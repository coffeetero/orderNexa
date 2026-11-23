import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from 'pdf-lib';

export interface PdfColumn { label: string; width: number; align?: 'left' | 'right' }
export interface PdfSection { heading?: string; columns: PdfColumn[]; rows: string[][]; footer?: string[]; note?: string }
export interface PdfSpec { title: string; company: string; subtitle?: string[]; sections: PdfSection[]; landscape?: boolean }

const MARGIN = 40;
const ROW_H = 15;
const INK = rgb(0.1, 0.1, 0.12);
const MUTED = rgb(0.4, 0.4, 0.45);
const RULE = rgb(0.8, 0.8, 0.84);

export const money = (v: unknown) =>
  Number(v ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
export const qty = (v: unknown) => Number(v ?? 0).toLocaleString('en-US', { maximumFractionDigits: 3 });
export const day = (v: unknown) => (typeof v === 'string' ? v.slice(0, 10) : '');

/** WinAnsi (the built-in fonts) cannot draw every character; swap the ones that would throw. */
const safe = (s: string) => s.replace(/[–—]/g, '-').replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/[^\x20-\x7e\xa0-\xff]/g, '?');

function fit(font: PDFFont, text: string, size: number, width: number): string {
  const t = safe(text);
  if (font.widthOfTextAtSize(t, size) <= width) return t;
  let s = t;
  while (s.length > 1 && font.widthOfTextAtSize(s + '...', size) > width) s = s.slice(0, -1);
  return s + '...';
}

/** One PDF; every spec starts on a new page. Tables repeat their header row when they continue on the next page. */
export async function renderPdf(specs: PdfSpec[]): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);

  for (const spec of specs) {
    const [pw, ph] = spec.landscape ? [792, 612] : [612, 792];
    const usable = pw - MARGIN * 2;
    let page: PDFPage = pdf.addPage([pw, ph]);
    let y = ph - MARGIN;

    const newPage = () => { page = pdf.addPage([pw, ph]); y = ph - MARGIN; };
    const text = (s: string, x: number, size: number, f: PDFFont, color = INK) => page.drawText(safe(s), { x, y, size, font: f, color });

    text(spec.company, MARGIN, 9, font, MUTED); y -= 20;
    text(spec.title, MARGIN, 17, bold); y -= 18;
    for (const line of spec.subtitle ?? []) { text(line, MARGIN, 10, font, MUTED); y -= 13; }
    y -= 8;

    for (const sec of spec.sections) {
      const total = sec.columns.reduce((a, c) => a + c.width, 0);
      const widths = sec.columns.map((c) => (c.width / total) * usable);
      const xs = widths.map((_, i) => MARGIN + widths.slice(0, i).reduce((a, b) => a + b, 0));

      const cells = (vals: string[], f: PDFFont, size: number) => vals.forEach((v, i) => {
        const col = sec.columns[i];
        const t = fit(f, v ?? '', size, widths[i] - 6);
        const w = f.widthOfTextAtSize(t, size);
        page.drawText(t, { x: col.align === 'right' ? xs[i] + widths[i] - 3 - w : xs[i] + 3, y, size, font: f, color: INK });
      });
      const header = () => {
        page.drawRectangle({ x: MARGIN, y: y - 4, width: usable, height: ROW_H, color: rgb(0.94, 0.94, 0.96) });
        cells(sec.columns.map((c) => c.label), bold, 9);
        y -= ROW_H;
      };

      if (y < MARGIN + 80) newPage();
      if (sec.heading) { text(sec.heading, MARGIN, 11, bold); y -= 16; }
      if (sec.note) { text(sec.note, MARGIN, 9, font, MUTED); y -= 13; }
      header();
      for (const row of sec.rows) {
        if (y < MARGIN + ROW_H * 2) { newPage(); header(); }
        cells(row, font, 9);
        page.drawLine({ start: { x: MARGIN, y: y - 4 }, end: { x: MARGIN + usable, y: y - 4 }, thickness: 0.4, color: RULE });
        y -= ROW_H;
      }
      if (sec.rows.length === 0) { text('Nothing to show.', MARGIN + 3, 9, font, MUTED); y -= ROW_H; }
      if (sec.footer) {
        if (y < MARGIN + ROW_H * 2) newPage();
        page.drawLine({ start: { x: MARGIN, y: y + 9 }, end: { x: MARGIN + usable, y: y + 9 }, thickness: 0.8, color: INK });
        cells(sec.footer, bold, 9);
        y -= ROW_H;
      }
      y -= 14;
    }
  }

  const pages = pdf.getPages();
  pages.forEach((p, i) => {
    const label = `Page ${i + 1} of ${pages.length}`;
    p.drawText(label, { x: p.getWidth() - MARGIN - font.widthOfTextAtSize(label, 8), y: 22, size: 8, font, color: MUTED });
  });
  return pdf.save();
}
