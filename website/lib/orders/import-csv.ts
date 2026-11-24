/** Customer order file (comma or tab separated, optional header row), the same layout Export Orders writes:
 *  Cus no, Customer, Department/Event, Item no, Item description, Qty. Customer and Department/Event may be blank. */
export interface ImportRow { cus_no: string; customer_name: string; department_event: string; item_number: string; item_desc: string; qty: string }
export const IMPORT_COLUMNS = ['Cus no', 'Customer', 'Department/Event', 'Item no', 'Item description', 'Qty'];

/** Splits CSV text into rows of cells. Handles quoted cells ("a, b" and "" for a quote), CRLF and a leading BOM. */
export function parseCsv(text: string): string[][] {
  const src = text.replace(/^﻿/, '');
  const firstLine = src.split(/\r?\n/, 1)[0] ?? '';
  const sep = firstLine.includes('\t') && !firstLine.includes(',') ? '\t' : ',';
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let quoted = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (quoted) {
      if (ch === '"' && src[i + 1] === '"') { cell += '"'; i++; }
      else if (ch === '"') quoted = false;
      else cell += ch;
    } else if (ch === '"' && cell === '') quoted = true;
    else if (ch === sep) { row.push(cell); cell = ''; }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && src[i + 1] === '\n') i++;
      row.push(cell); rows.push(row); row = []; cell = '';
    } else cell += ch;
  }
  if (cell !== '' || row.length > 0) { row.push(cell); rows.push(row); }
  return rows.filter((r) => r.some((c) => c.trim() !== ''));
}

/** A first row is a header when its quantity is not a number and its customer number has no digits ("Cus no", "Qty"). */
const isHeader = (r: string[]) => !/^\s*\d+(\.\d+)?\s*$/.test(r[5] ?? '') && !/\d/.test(r[0] ?? '');

/** File text → import rows (six columns, trimmed). A row with fewer than six columns is refused (e.g. the old 4-column layout). The database checks each value. */
export function toImportRows(text: string): ImportRow[] {
  const rows = parseCsv(text);
  const data = rows.length > 0 && isHeader(rows[0]) ? rows.slice(1) : rows;
  const short = data.findIndex((r) => r.length < IMPORT_COLUMNS.length);
  if (short >= 0) {
    throw new Error(`Data row ${short + 1} has ${data[short].length} columns. The file needs ${IMPORT_COLUMNS.length}: ${IMPORT_COLUMNS.join(', ')}.`);
  }
  const c = (r: string[], i: number) => (r[i] ?? '').trim();
  return data.map((r) => ({ cus_no: c(r, 0), customer_name: c(r, 1), department_event: c(r, 2), item_number: c(r, 3), item_desc: c(r, 4), qty: c(r, 5) }));
}

/** Import rows → CSV text in the layout toImportRows reads, with a header row. */
export function toImportCsv(rows: ImportRow[]): string {
  const cell = (v: string) => (/[",\r\n]|^\s|\s$/.test(v) ? `"${v.replace(/"/g, '""')}"` : v);
  const lines = [IMPORT_COLUMNS, ...rows.map((r) => [r.cus_no, r.customer_name, r.department_event, r.item_number, r.item_desc, r.qty])];
  return lines.map((l) => l.map((v) => cell(v ?? '')).join(',')).join('\r\n') + '\r\n';
}
