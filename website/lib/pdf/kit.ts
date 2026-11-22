import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from 'pdf-lib';

/** Letter, in points. */
export const LETTER = { width: 612, height: 792 } as const;
/** 4" x 2" label, in points. */
export const LABEL = { width: 288, height: 144 } as const;

const INK = rgb(0.1, 0.1, 0.1);
const MUTED = rgb(0.4, 0.4, 0.4);
const RULE = rgb(0.75, 0.75, 0.75);

export interface Writer {
  doc: PDFDocument;
  font: PDFFont;
  bold: PDFFont;
  page: PDFPage;
  y: number;
  readonly margin: number;
  readonly size: { width: number; height: number };
  /** Called when a new page is started so callers can repeat a header. */
  onNewPage?: (w: Writer) => void;
}

/** Standard PDF fonts only cover WinAnsi; anything else becomes "?" so a stray character cannot break a report. */
export function clean(text: unknown): string {
  return String(text ?? '')
    .replace(/[‘’]/g, "'")
    .replace(/[“”]/g, '"')
    .replace(/[–—]/g, '-')
    .replace(/ /g, ' ')
    .replace(/[^\x20-\x7E¡-ÿ]/g, '?');
}

/** Display only: no rounding rules here, the database supplies the numbers. */
export const money = (v: unknown): string => Number(v ?? 0).toFixed(2);
export const qty = (v: unknown): string => {
  const n = Number(v ?? 0);
  return Number.isInteger(n) ? String(n) : String(Number(n.toFixed(4)));
};

export async function createWriter(size: { width: number; height: number }, margin = 40): Promise<Writer> {
  const doc = await PDFDocument.create();
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const page = doc.addPage([size.width, size.height]);
  return { doc, font, bold, page, y: size.height - margin, margin, size };
}

export function newPage(w: Writer): void {
  w.page = w.doc.addPage([w.size.width, w.size.height]);
  w.y = w.size.height - w.margin;
  w.onNewPage?.(w);
}

/** Starts a new page when fewer than `needed` points remain above the bottom margin. */
export function ensure(w: Writer, needed: number): void {
  if (w.y - needed < w.margin) newPage(w);
}

export function wrap(text: string, font: PDFFont, fontSize: number, maxWidth: number): string[] {
  const words = clean(text).split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let line = '';
  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word;
    if (font.widthOfTextAtSize(candidate, fontSize) <= maxWidth) {
      line = candidate;
    } else {
      if (line) lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines.length ? lines : [''];
}

export interface TextOpts {
  x?: number;
  size?: number;
  bold?: boolean;
  muted?: boolean;
  align?: 'left' | 'right';
  /** For right alignment: the x of the right edge. */
  right?: number;
}

/** Draws one line at the cursor and moves down by `lead`. Does not wrap. */
export function text(w: Writer, value: unknown, opts: TextOpts = {}, lead?: number): void {
  const size = opts.size ?? 10;
  const font = opts.bold ? w.bold : w.font;
  const t = clean(value);
  const x = opts.align === 'right' ? (opts.right ?? w.size.width - w.margin) - font.widthOfTextAtSize(t, size) : (opts.x ?? w.margin);
  w.page.drawText(t, { x, y: w.y - size, size, font, color: opts.muted ? MUTED : INK });
  w.y -= lead ?? size + 4;
}

/** Draws text at an explicit y without moving the cursor (for table cells on one row). */
export function cell(w: Writer, value: unknown, x: number, y: number, opts: TextOpts = {}): void {
  const size = opts.size ?? 10;
  const font = opts.bold ? w.bold : w.font;
  const t = clean(value);
  const left = opts.align === 'right' ? (opts.right ?? x) - font.widthOfTextAtSize(t, size) : x;
  w.page.drawText(t, { x: left, y: y - size, size, font, color: opts.muted ? MUTED : INK });
}

export function rule(w: Writer, gap = 4): void {
  w.page.drawLine({ start: { x: w.margin, y: w.y - 1 }, end: { x: w.size.width - w.margin, y: w.y - 1 }, thickness: 0.5, color: RULE });
  w.y -= gap + 1;
}

export function footerPageNumbers(doc: PDFDocument, font: PDFFont, label: string): void {
  const pages = doc.getPages();
  pages.forEach((p, i) => {
    const t = clean(`${label}  -  page ${i + 1} of ${pages.length}`);
    p.drawText(t, { x: p.getWidth() - 40 - font.widthOfTextAtSize(t, 8), y: 20, size: 8, font, color: MUTED });
  });
}
