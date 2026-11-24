import { describe, expect, it } from 'vitest';
import { parseCsv, toImportCsv, toImportRows } from '@/lib/orders/import-csv';

const row = (cus_no: string, customer_name: string, department_event: string, item_number: string, item_desc: string, qty: string) =>
  ({ cus_no, customer_name, department_event, item_number, item_desc, qty });

describe('order import CSV', () => {
  it('reads the six columns and skips a header row', () => {
    const text = 'Cus no,Customer,Department/Event,Item no,Item description,Qty\n15702,BEO,,10100,FRENCH BAGUETTE,3\n15700,,FS-1234,10200,ROLL,12\n';
    expect(toImportRows(text)).toEqual([
      row('15702', 'BEO', '', '10100', 'FRENCH BAGUETTE', '3'),
      row('15700', '', 'FS-1234', '10200', 'ROLL', '12'),
    ]);
  });

  it('keeps the first row when it is data', () => {
    expect(toImportRows('15702,,,10100,BAGUETTE,3')).toHaveLength(1);
  });

  it('handles quotes, commas inside quotes, CRLF, a BOM and blank lines', () => {
    const text = '﻿15702,,,10100,"BAGUETTE, FRENCH ""LONG""",2\r\n\r\n15703,,,10200,ROLL,1\r\n';
    expect(toImportRows(text)).toEqual([
      row('15702', '', '', '10100', 'BAGUETTE, FRENCH "LONG"', '2'),
      row('15703', '', '', '10200', 'ROLL', '1'),
    ]);
  });

  it('reads tab-separated files and trims cells', () => {
    expect(toImportRows(' 15702 \t \t BEO \t 10100 \t BAGUETTE \t 4 ')).toEqual([row('15702', '', 'BEO', '10100', 'BAGUETTE', '4')]);
  });

  it('passes bad values through for the database to report', () => {
    expect(toImportRows('15702,,,10100,BAGUETTE,abc\n15702,,,,X,2')).toEqual([
      row('15702', '', '', '10100', 'BAGUETTE', 'abc'),
      row('15702', '', '', '', 'X', '2'),
    ]);
    expect(parseCsv('')).toEqual([]);
  });

  it('refuses the old four-column layout and says which columns are needed', () => {
    expect(() => toImportRows('15702,10100,BAGUETTE,3')).toThrow(/needs 6: Cus no, Customer, Department\/Event, Item no, Item description, Qty/);
  });

  it('writes a file that reads back to the same rows (export → import)', () => {
    const rows = [
      row('15700', 'FEATHERSTONE BAKING, INC.', 'LUNCH, 2ND FLOOR', '00100', 'BAGUETTE, FRENCH "LONG"', '1.5'),
      row('15702', '', '', '10200', 'ROLL', '4'),
    ];
    const csv = toImportCsv(rows);
    expect(csv.split('\r\n')[0]).toBe('Cus no,Customer,Department/Event,Item no,Item description,Qty');
    expect(toImportRows(csv)).toEqual(rows);
  });
});
