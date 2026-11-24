/** Customer order file: cus no, item number, item desc, qty (comma or tab separated, optional header row). */
export interface ImportRow { cus_no: string; item_number: string; item_desc: string; qty: string }

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

/** A first row is a header when its quantity is not a number and its customer number has no digits ("cus no", "qty"). */
const isHeader = (r: string[]) => !/^\s*\d+(\.\d+)?\s*$/.test(r[3] ?? '') && !/\d/.test(r[0] ?? '');

/** File text → import rows (the first four columns, trimmed). The database checks each value. */
export function toImportRows(text: string): ImportRow[] {
  const rows = parseCsv(text);
  const data = rows.length > 0 && isHeader(rows[0]) ? rows.slice(1) : rows;
  return data.map((r) => ({
    cus_no: (r[0] ?? '').trim(), item_number: (r[1] ?? '').trim(), item_desc: (r[2] ?? '').trim(), qty: (r[3] ?? '').trim(),
  }));
}
