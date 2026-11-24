/**
 * BPS functions for Sheets: =BPS.SALES(from, [to]), =BPS.BALANCE(customer_no), =BPS.AGING(customer_no, bucket),
 * =BPS.ITEM_PRICE(item_no, customer_no, [date]), =BPS.QTY_ORDERED(item_no, date, [code]).
 * The database computes every value (org_sheet_bps_eval) as the signed-in user; calls made together are sent in one request.
 */
export const BPS_FUNCTIONS: { name: string; dateArgs: number[]; help: string }[] = [
  { name: 'SALES', dateArgs: [0, 1], help: 'BPS.SALES(from, [to]): net sales (invoices less credits) dated in the range' },
  { name: 'BALANCE', dateArgs: [], help: "BPS.BALANCE(customer_no): the customer's account balance today" },
  { name: 'AGING', dateArgs: [], help: 'BPS.AGING(customer_no, bucket): current, 1-30, 31-60, 61-90, 90+ or total' },
  { name: 'ITEM_PRICE', dateArgs: [2], help: "BPS.ITEM_PRICE(item_no, customer_no, [date]): the item's price for the customer" },
  { name: 'QTY_ORDERED', dateArgs: [1], help: 'BPS.QTY_ORDERED(item_no, date, [code]): quantity ordered for a production date' },
];

export type BpsResult = { v?: number | string | null; e?: string; message?: string };
type Call = { fn: string; args: (string | null)[] };

/** Spreadsheet date serial (days since 1899-12-30) → YYYY-MM-DD. Text dates are passed through. */
export function serialToIsoDate(n: number): string {
  const d = new Date(Date.UTC(1899, 11, 30) + Math.round(n) * 86400000);
  return d.toISOString().slice(0, 10);
}

/** Cell argument → the text the database expects. Numbers in date positions are date serials. */
export function toArg(value: unknown, isDate: boolean): string | null {
  let v = value;
  while (Array.isArray(v)) v = v[0]; // a one-cell range arrives as [[value]]
  if (v && typeof v === 'object' && 'getValue' in v && typeof (v as { getValue: unknown }).getValue === 'function') {
    v = (v as { getValue: () => unknown }).getValue();
  }
  if (v === null || v === undefined || v === '') return null;
  if (typeof v === 'number') return isDate ? serialToIsoDate(v) : String(v);
  return String(v).trim();
}

/** Collects calls made in the same moment and sends them as one request. */
export function createBpsClient(send: (calls: Call[]) => Promise<BpsResult[]>, waitMs = 30) {
  let queue: { call: Call; resolve: (r: BpsResult) => void }[] = [];
  let timer: ReturnType<typeof setTimeout> | null = null;
  const flush = async () => {
    const batch = queue;
    queue = [];
    timer = null;
    try {
      const results = await send(batch.map((b) => b.call));
      batch.forEach((b, i) => b.resolve(results[i] ?? { e: '#N/A' }));
    } catch (err) {
      batch.forEach((b) => b.resolve({ e: '#ERROR', message: (err as Error).message }));
    }
  };
  return (call: Call) =>
    new Promise<BpsResult>((resolve) => {
      queue.push({ call, resolve });
      if (!timer) timer = setTimeout(flush, waitMs);
    });
}

/** The value a cell shows for a result: the number, or the error code (#ACCESS, #N/A …). */
export const resultToCell = (r: BpsResult): number | string => (r.e ? r.e : typeof r.v === 'number' ? r.v : Number(r.v ?? 0));
