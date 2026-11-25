import type ExcelJS from 'exceljs';
import { parseCsv } from '@/lib/orders/import-csv';

/**
 * Export Customers / Import Customers file layout: one row per customer (ACCOUNT, SITE, DEPARTMENT) with its parent's
 * customer number, as CSV or Excel (.xlsx). Keys are the database's (fnd_customer_export_get / fnd_customer_import_upload);
 * the database checks every value.
 */
export const CUSTOMER_COLUMNS = [
  { key: 'customer_number', header: 'Customer no', width: 12 },
  { key: 'customer_name', header: 'Name', width: 32 },
  { key: 'customer_type', header: 'Type', width: 12 },
  { key: 'parent_number', header: 'Parent no', width: 12 },
  { key: 'is_active', header: 'Active', width: 8 },
  { key: 'billing_type', header: 'Billing type', width: 12 },
  { key: 'billing_period', header: 'Billing period', width: 14 },
  { key: 'credit_limit', header: 'Credit limit', width: 12 },
  { key: 'delivery_method', header: 'Delivery method', width: 16 },
  { key: 'cutoff_extra_minutes', header: 'Cutoff extra minutes', width: 12 },
  { key: 'invoice_copy_count', header: 'Invoice copies', width: 10 },
  { key: 'is_standing_order', header: 'Standing order', width: 10 },
  { key: 'is_signature_required', header: 'Signature required', width: 10 },
  { key: 'is_label_required', header: 'Label required', width: 10 },
  { key: 'is_invoice_required', header: 'Invoice required', width: 10 },
  { key: 'is_cost_on_invoice', header: 'Cost on invoice', width: 10 },
  { key: 'is_cost_on_bill_of_lading', header: 'Cost on bill of lading', width: 10 },
  { key: 'is_returns_allowed', header: 'Returns allowed', width: 10 },
  { key: 'billing_address', header: 'Billing address', width: 36 },
  { key: 'shipping_address', header: 'Shipping address', width: 36 },
  { key: 'phone', header: 'Phone', width: 16 },
  { key: 'email', header: 'Email', width: 28 },
  { key: 'pricebook', header: 'Pricing book', width: 24 },
] as const;

export type CustomerFileRow = Record<string, string>;
export type CustomerExportRow = Record<string, string | null>;

/** Columns the file may leave out: Pricing book is exported for reference only and never imported. */
const OPTIONAL = new Set(['pricebook']);
const norm = (h: string) => h.trim().toLowerCase().replace(/\s+/g, ' ');
export const columnLabel = (key: string) => CUSTOMER_COLUMNS.find((c) => c.key === key)?.header ?? key;

/** Header row + data rows (cells as text) → import rows keyed by column. Columns are found by header name, in any order. */
export function toCustomerRows(cells: string[][]): CustomerFileRow[] {
  if (cells.length === 0) throw new Error('The file is empty');
  const header = cells[0].map(norm);
  const index = new Map(CUSTOMER_COLUMNS.map((c) => [c.key, header.indexOf(norm(c.header))]));
  const missing = CUSTOMER_COLUMNS.filter((c) => !OPTIONAL.has(c.key) && index.get(c.key)! < 0).map((c) => c.header);
  if (missing.length > 0) {
    throw new Error(`The first row must be the Export Customers header. Missing: ${missing.join(', ')}.`);
  }
  return cells.slice(1)
    .filter((r) => r.some((v) => (v ?? '').trim() !== ''))
    .map((r) => {
      const row: CustomerFileRow = {};
      for (const c of CUSTOMER_COLUMNS) {
        const i = index.get(c.key)!;
        if (i >= 0) row[c.key] = r[i] ?? '';
      }
      return row;
    });
}

/** CSV text → import rows. */
export function parseCustomerCsv(text: string): CustomerFileRow[] {
  return toCustomerRows(parseCsv(text));
}

/** Export rows → CSV text (header row; cells with commas, quotes or line breaks quoted). */
export function toCustomerCsv(rows: CustomerExportRow[]): string {
  const cell = (v: string) => (/[",\r\n]|^\s|\s$/.test(v) ? `"${v.replace(/"/g, '""')}"` : v);
  const lines = [CUSTOMER_COLUMNS.map((c) => c.header), ...rows.map((r) => CUSTOMER_COLUMNS.map((c) => r[c.key] ?? ''))];
  return lines.map((l) => l.map((v) => cell(v)).join(',')).join('\r\n') + '\r\n';
}

/** An Excel cell as the text the file means (numbers without float noise, rich text joined, formulas as their result). */
function cellText(v: ExcelJS.CellValue): string {
  if (v === null || v === undefined) return '';
  if (typeof v === 'string') return v;
  if (typeof v === 'number') return String(v);
  if (typeof v === 'boolean') return v ? 'Y' : 'N';
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  if ('richText' in v) return v.richText.map((p) => p.text).join('');
  if ('text' in v) return String(v.text);
  if ('result' in v) return cellText((v.result ?? null) as ExcelJS.CellValue);
  return '';
}

/** First worksheet of an .xlsx workbook → import rows. */
export function readCustomerSheet(wb: ExcelJS.Workbook): CustomerFileRow[] {
  const ws = wb.worksheets[0];
  if (!ws) throw new Error('The workbook has no sheets');
  const cells: string[][] = [];
  ws.eachRow({ includeEmpty: true }, (row, n) => {
    const out: string[] = [];
    for (let c = 1; c <= ws.columnCount; c++) out.push(cellText(row.getCell(c).value));
    cells[n - 1] = out;
  });
  return toCustomerRows(Array.from(cells, (r) => r ?? []));
}

/** Export rows → a workbook with one sheet; every value is written as text so customer numbers keep their form. */
export function writeCustomerSheet(wb: ExcelJS.Workbook, rows: CustomerExportRow[]): void {
  const ws = wb.addWorksheet('Customers', { views: [{ state: 'frozen', ySplit: 1 }] });
  ws.columns = CUSTOMER_COLUMNS.map((c) => ({ header: c.header, key: c.key, width: c.width, style: { numFmt: '@' } }));
  ws.getRow(1).font = { bold: true };
  for (const r of rows) ws.addRow(Object.fromEntries(CUSTOMER_COLUMNS.map((c) => [c.key, r[c.key] ?? ''])));
  for (const key of ['billing_address', 'shipping_address']) ws.getColumn(key).alignment = { wrapText: true, vertical: 'top' };
}
