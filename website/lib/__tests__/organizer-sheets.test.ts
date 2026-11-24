import ExcelJS from 'exceljs';
import { describe, expect, it } from 'vitest';
import { createBpsClient, serialToIsoDate, toArg } from '@/lib/organizer/bps-functions';
import { decodeRange, fromExcel, toExcel, toPrintHtml } from '@/lib/organizer/xlsx';

function sampleExcel() {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('Prices');
  ws.getCell('A1').value = 'Item';
  ws.getCell('A1').font = { bold: true };
  ws.getCell('B1').value = 'Qty';
  ws.getCell('A2').value = '00123';
  ws.getCell('B2').value = 4;
  ws.getCell('B3').value = 6;
  ws.getCell('B4').value = { formula: 'SUM(B2:B3)/2', result: 5 } as ExcelJS.CellFormulaValue;
  ws.getCell('C2').value = new Date(Date.UTC(2026, 11, 3));
  ws.getColumn(1).width = 20;
  ws.mergeCells('D1:E1');
  wb.addWorksheet('Notes').getCell('A1').value = 'second sheet';
  return wb;
}

describe('sheets: Excel conversion', () => {
  it('reads values, text with leading zeros, formulas, dates, bold, widths, merges and every sheet', () => {
    const data = fromExcel(sampleExcel(), 'Test');
    expect(data.sheetOrder).toHaveLength(2);
    const s = data.sheets[data.sheetOrder[0]];
    expect(s.name).toBe('Prices');
    expect(s.cellData[1][0]).toMatchObject({ v: '00123', t: 1 });
    expect(s.cellData[3][1]).toMatchObject({ f: '=SUM(B2:B3)/2', v: 5 });
    expect(s.cellData[1][2].v).toBe(46359); // 2026-12-03 as a date serial
    expect(data.styles[s.cellData[0][0].s as string]).toEqual({ bl: 1 });
    expect(s.columnData?.[0]?.w).toBe(145);
    expect(s.mergeData).toEqual([{ startRow: 0, endRow: 0, startColumn: 3, endColumn: 4 }]);
  });

  it('writes back to Excel; BPS functions become their last values', () => {
    const data = fromExcel(sampleExcel(), 'Test');
    const s = data.sheets[data.sheetOrder[0]];
    s.cellData[5] = { 0: { f: '=BPS.SALES(TODAY())', v: 1234.5 } };
    const ws = toExcel(data, ExcelJS).getWorksheet('Prices')!;
    expect(ws.getCell('B4').value).toEqual({ formula: 'SUM(B2:B3)/2', result: 5 });
    expect(ws.getCell('A6').value).toBe(1234.5);
    expect(ws.getCell('A2').value).toBe('00123');
    expect(ws.getCell('A1').font?.bold).toBe(true);
    expect(ws.getColumn(1).width).toBe(20);
  });

  it('prints values with dates as dates and escapes text', () => {
    const data = fromExcel(sampleExcel(), 'Test');
    data.sheets[data.sheetOrder[0]].cellData[6] = { 0: { v: '<b>x</b>', t: 1 } };
    const html = toPrintHtml(data, 'My sheet');
    expect(html).toContain('2026-12-03');
    expect(html).toContain('&lt;b&gt;x&lt;/b&gt;');
    expect(html).toContain('second sheet');
  });

  it('decodes A1 ranges', () => {
    expect(decodeRange('AA10:AB12')).toEqual({ startRow: 9, endRow: 11, startColumn: 26, endColumn: 27 });
    expect(decodeRange('bad')).toBeNull();
  });
});

describe('sheets: BPS functions', () => {
  it('turns date serials and one-cell ranges into database arguments', () => {
    expect(serialToIsoDate(46359)).toBe('2026-12-03');
    expect(toArg(46359, true)).toBe('2026-12-03');
    expect(toArg(15700, false)).toBe('15700');
    expect(toArg([[' 15700 ']], false)).toBe('15700');
    expect(toArg('', false)).toBeNull();
  });

  it('sends calls made together in one request, in order', async () => {
    const sent: unknown[] = [];
    const call = createBpsClient(async (calls) => { sent.push(calls); return calls.map((c, i) => ({ v: i })); }, 5);
    const [a, b] = await Promise.all([call({ fn: 'SALES', args: ['2026-12-01'] }), call({ fn: 'BALANCE', args: ['15700'] })]);
    expect(sent).toHaveLength(1);
    expect([a.v, b.v]).toEqual([0, 1]);
  });

  it('reports a failed request as an error on every cell', async () => {
    const call = createBpsClient(async () => { throw new Error('offline'); }, 1);
    expect(await call({ fn: 'SALES', args: [] })).toMatchObject({ e: '#ERROR', message: 'offline' });
  });
});
