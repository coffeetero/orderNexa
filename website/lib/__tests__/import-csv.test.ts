import { describe, expect, it } from 'vitest';
import { parseCsv, toImportRows } from '@/lib/orders/import-csv';

describe('order import CSV', () => {
  it('reads plain rows and skips a header row', () => {
    const text = 'cus no,item number,item desc,qty\n15702,10100,FRENCH BAGUETTE,3\n15703,10200,ROLL,12\n';
    expect(toImportRows(text)).toEqual([
      { cus_no: '15702', item_number: '10100', item_desc: 'FRENCH BAGUETTE', qty: '3' },
      { cus_no: '15703', item_number: '10200', item_desc: 'ROLL', qty: '12' },
    ]);
  });

  it('keeps the first row when it is data', () => {
    expect(toImportRows('15702,10100,BAGUETTE,3')).toHaveLength(1);
  });

  it('handles quotes, commas inside quotes, CRLF, a BOM and blank lines', () => {
    const text = '﻿15702,10100,"BAGUETTE, FRENCH ""LONG""",2\r\n\r\n15703,10200,ROLL,1\r\n';
    expect(toImportRows(text)).toEqual([
      { cus_no: '15702', item_number: '10100', item_desc: 'BAGUETTE, FRENCH "LONG"', qty: '2' },
      { cus_no: '15703', item_number: '10200', item_desc: 'ROLL', qty: '1' },
    ]);
  });

  it('reads tab-separated files and trims cells', () => {
    expect(toImportRows(' 15702 \t 10100 \t BAGUETTE \t 4 ')).toEqual([{ cus_no: '15702', item_number: '10100', item_desc: 'BAGUETTE', qty: '4' }]);
  });

  it('passes bad values through for the database to report', () => {
    expect(toImportRows('15702,10100,BAGUETTE,abc\n15702,,X,2')).toEqual([
      { cus_no: '15702', item_number: '10100', item_desc: 'BAGUETTE', qty: 'abc' },
      { cus_no: '15702', item_number: '', item_desc: 'X', qty: '2' },
    ]);
    expect(parseCsv('')).toEqual([]);
  });
});
