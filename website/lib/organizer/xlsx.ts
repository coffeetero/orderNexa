import type ExcelJS from 'exceljs';

/**
 * Converts between an Excel workbook (ExcelJS) and the spreadsheet component's workbook JSON (Univer IWorkbookData).
 * Kept: sheets, values, formulas, bold/italic, number formats, column widths, merged cells.
 * Not kept: charts, images, pivot tables, conditional formatting, macros.
 * Export writes BPS functions as their last values (Excel does not know them).
 */

type Style = { bl?: number; it?: number; n?: { pattern: string } };
type Cell = { v?: string | number | boolean | null; f?: string; s?: string | Style | null; t?: number };
type Sheet = {
  id: string; name: string; rowCount: number; columnCount: number;
  cellData: Record<number, Record<number, Cell>>;
  columnData?: Record<number, { w?: number }>;
  mergeData?: { startRow: number; endRow: number; startColumn: number; endColumn: number }[];
};
export type WorkbookData = {
  id: string; name: string; sheetOrder: string[]; styles: Record<string, Style>; sheets: Record<string, Sheet>;
  [k: string]: unknown;
};

const CELL_STRING = 1;
const CELL_NUMBER = 2;
const CELL_BOOLEAN = 3;
const EXCEL_EPOCH = Date.UTC(1899, 11, 30);
const PX_PER_CHAR = 7;

/** A1-style range "B2:D4" → zero-based bounds. */
export function decodeRange(ref: string) {
  const parse = (a: string) => {
    const m = /^([A-Z]+)(\d+)$/.exec(a.replace(/\$/g, '').toUpperCase());
    if (!m) return null;
    const col = m[1].split('').reduce((n, ch) => n * 26 + ch.charCodeAt(0) - 64, 0) - 1;
    return { r: Number(m[2]) - 1, c: col };
  };
  const [a, b] = ref.split(':');
  const s = parse(a);
  const e = parse(b ?? a);
  if (!s || !e) return null;
  return { startRow: s.r, endRow: e.r, startColumn: s.c, endColumn: e.c };
}

/** An empty workbook with one sheet. */
export function emptyWorkbook(name: string): WorkbookData {
  return {
    id: `wb-${Date.now()}`, name, sheetOrder: ['sheet1'], styles: {},
    sheets: { sheet1: { id: 'sheet1', name: 'Sheet1', rowCount: 200, columnCount: 26, cellData: {} } },
  };
}

/** Excel → workbook JSON. */
export function fromExcel(wb: ExcelJS.Workbook, name: string): WorkbookData {
  const out: WorkbookData = { id: `wb-${Date.now()}`, name, sheetOrder: [], styles: {}, sheets: {} };
  const styleIds = new Map<string, string>();
  const styleId = (st: Style): string | undefined => {
    if (!st.bl && !st.it && !st.n) return undefined;
    const key = JSON.stringify(st);
    if (!styleIds.has(key)) {
      const id = `s${styleIds.size + 1}`;
      styleIds.set(key, id);
      out.styles[id] = st;
    }
    return styleIds.get(key);
  };

  wb.eachSheet((ws, i) => {
    const id = `sheet${i}`;
    const sheet: Sheet = { id, name: ws.name, rowCount: Math.max(ws.rowCount + 50, 200), columnCount: Math.max(ws.columnCount + 5, 26), cellData: {} };
    ws.eachRow({ includeEmpty: false }, (row, rowNo) => {
      row.eachCell({ includeEmpty: false }, (cell, colNo) => {
        const c: Cell = {};
        const raw = cell.value as unknown;
        let numFmt = cell.numFmt && cell.numFmt !== 'General' ? cell.numFmt : undefined;
        const setValue = (v: unknown) => {
          if (v instanceof Date) { c.v = (v.getTime() - EXCEL_EPOCH) / 86400000; c.t = CELL_NUMBER; numFmt = numFmt ?? 'yyyy-mm-dd'; }
          else if (typeof v === 'number') { c.v = v; c.t = CELL_NUMBER; }
          else if (typeof v === 'boolean') { c.v = v; c.t = CELL_BOOLEAN; }
          else if (v !== null && v !== undefined) { c.v = String(v); c.t = CELL_STRING; }
        };
        if (raw && typeof raw === 'object' && !(raw instanceof Date)) {
          const o = raw as { formula?: string; sharedFormula?: string; result?: unknown; richText?: { text: string }[]; text?: string; error?: string };
          const f = cell.formula || o.formula;
          if (f) { c.f = `=${f}`; setValue(o.result && typeof o.result === 'object' && 'error' in (o.result as object) ? null : o.result); }
          else if (o.richText) setValue(o.richText.map((r) => r.text).join(''));
          else if (o.text !== undefined) setValue(o.text);
          else if (o.error) setValue(o.error);
        } else setValue(raw);
        if (c.v === undefined && !c.f) return;
        const s = styleId({ ...(cell.font?.bold ? { bl: 1 } : {}), ...(cell.font?.italic ? { it: 1 } : {}), ...(numFmt ? { n: { pattern: numFmt } } : {}) });
        if (s) c.s = s;
        (sheet.cellData[rowNo - 1] ??= {})[colNo - 1] = c;
      });
    });
    ws.columns?.forEach((col, ci) => {
      if (col?.width) (sheet.columnData ??= {})[ci] = { w: Math.round(col.width * PX_PER_CHAR + 5) };
    });
    const merges = (ws.model as unknown as { merges?: string[] }).merges ?? [];
    const md = merges.map(decodeRange).filter((m): m is NonNullable<typeof m> => m !== null);
    if (md.length) sheet.mergeData = md;
    out.sheetOrder.push(id);
    out.sheets[id] = sheet;
  });
  if (out.sheetOrder.length === 0) return emptyWorkbook(name);
  return out;
}

const resolveStyle = (data: WorkbookData, s: Cell['s']): Style => (typeof s === 'string' ? data.styles?.[s] ?? {} : s ?? {});
const isBpsFormula = (f: string) => /\bBPS\./i.test(f);

/** Workbook JSON → Excel. BPS functions are written as their last values. */
export function toExcel(data: WorkbookData, ExcelCtor: typeof ExcelJS): ExcelJS.Workbook {
  const wb = new ExcelCtor.Workbook();
  for (const sid of data.sheetOrder) {
    const sheet = data.sheets[sid];
    if (!sheet) continue;
    const ws = wb.addWorksheet(sheet.name.slice(0, 31) || sid);
    for (const [r, cols] of Object.entries(sheet.cellData ?? {})) {
      for (const [col, c] of Object.entries(cols ?? {})) {
        if (!c) continue;
        const cell = ws.getCell(Number(r) + 1, Number(col) + 1);
        const v = c.v ?? null;
        if (c.f && !isBpsFormula(c.f)) cell.value = { formula: c.f.replace(/^=/, ''), result: v as number | string | boolean } as ExcelJS.CellFormulaValue;
        else if (v !== null && v !== '') cell.value = v as ExcelJS.CellValue;
        const st = resolveStyle(data, c.s);
        if (st.bl || st.it) cell.font = { bold: !!st.bl, italic: !!st.it };
        if (st.n?.pattern) cell.numFmt = st.n.pattern;
      }
    }
    for (const [ci, cd] of Object.entries(sheet.columnData ?? {})) {
      if (cd?.w) ws.getColumn(Number(ci) + 1).width = Math.max(1, Math.round((cd.w - 5) / PX_PER_CHAR));
    }
    for (const m of sheet.mergeData ?? []) ws.mergeCells(m.startRow + 1, m.startColumn + 1, m.endRow + 1, m.endColumn + 1);
  }
  return wb;
}

/** Printable HTML of every sheet's values (what the cells show). */
export function toPrintHtml(data: WorkbookData, title: string): string {
  const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const sheets = data.sheetOrder.map((sid) => {
    const sheet = data.sheets[sid];
    const rows = Object.keys(sheet?.cellData ?? {}).map(Number);
    if (!sheet || rows.length === 0) return '';
    const maxR = Math.max(...rows);
    const maxC = Math.max(...rows.flatMap((r) => Object.keys(sheet.cellData[r] ?? {}).map(Number)), 0);
    let html = `<h2>${esc(sheet.name)}</h2><table>`;
    for (let r = 0; r <= maxR; r++) {
      html += '<tr>';
      for (let c = 0; c <= maxC; c++) {
        const cell = sheet.cellData[r]?.[c];
        const st = resolveStyle(data, cell?.s);
        const v = cell?.v;
        const isDate = typeof v === 'number' && !!st.n?.pattern && /[dmy]/i.test(st.n.pattern) && !/[0#]/.test(st.n.pattern);
        const text = v === null || v === undefined ? ''
          : isDate ? new Date(EXCEL_EPOCH + Math.round(v as number) * 86400000).toISOString().slice(0, 10)
          : typeof v === 'number' ? v.toLocaleString(undefined, { maximumFractionDigits: 4 }) : String(v);
        const css = [typeof v === 'number' ? 'text-align:right' : '', st.bl ? 'font-weight:bold' : '', st.it ? 'font-style:italic' : ''].filter(Boolean).join(';');
        html += `<td${css ? ` style="${css}"` : ''}>${esc(text)}</td>`;
      }
      html += '</tr>';
    }
    return `${html}</table>`;
  }).join('');
  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title><style>
body{font:11px Arial,sans-serif;margin:16px}h1{font-size:14px}h2{font-size:12px;margin:12px 0 4px}
table{border-collapse:collapse}td{border:1px solid #ccc;padding:2px 6px;white-space:nowrap}
@media print{h2{page-break-before:auto}}</style></head><body><h1>${esc(title)}</h1>${sheets}</body></html>`;
}
