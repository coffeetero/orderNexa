import ExcelJS from 'exceljs';
import { describe, expect, it } from 'vitest';
import { CUSTOMER_COLUMNS, parseCustomerCsv, readCustomerSheet, toCustomerCsv, writeCustomerSheet, type CustomerExportRow } from '@/lib/customers/customer-file';

const rows: CustomerExportRow[] = [
  { customer_number: '01500', customer_name: 'SMITH, "THE" BAKERY', customer_type: 'ACCOUNT', parent_number: null, is_active: 'Y',
    credit_limit: '1500.5', billing_address: '1 Main St\nSuite 2\nHoboken, NJ 07030', pricebook: 'Standard' },
  { customer_number: '01501', customer_name: 'Kitchen', customer_type: 'DEPARTMENT', parent_number: '01500', is_active: 'N', billing_address: null },
];
const expected = rows.map((r) => Object.fromEntries(CUSTOMER_COLUMNS.map((c) => [c.key, r[c.key] ?? ''])));

describe('customer import/export file', () => {
  it('CSV round trip keeps every value (quotes, commas, line breaks, leading zeros)', () => {
    expect(parseCustomerCsv(toCustomerCsv(rows))).toEqual(expected);
  });

  it('Excel round trip keeps every value', async () => {
    const wb = new ExcelJS.Workbook();
    writeCustomerSheet(wb, rows);
    const back = new ExcelJS.Workbook();
    await back.xlsx.load(await wb.xlsx.writeBuffer());
    expect(readCustomerSheet(back)).toEqual(expected);
  });

  it('finds columns by header in any order; Pricing book may be left out', () => {
    expect(parseCustomerCsv('name,customer no,TYPE,Parent no,Active,Billing type,Billing period,Credit limit,Delivery method,Cutoff extra minutes,'
      + 'Invoice copies,Standing order,Signature required,Label required,Invoice required,Cost on invoice,Cost on bill of lading,Returns allowed,'
      + 'Billing address,Shipping address,Phone,Email\nAcme,900,ACCOUNT,,Y,,,,,,,,,,,,,,,,,\n')[0])
      .toMatchObject({ customer_number: '900', customer_name: 'Acme', customer_type: 'ACCOUNT' });
  });

  it('refuses a file without the export header', () => {
    expect(() => parseCustomerCsv('900,Acme,ACCOUNT\n')).toThrow(/Missing: Customer no/);
  });

  it('reads Excel numbers typed into cells as text', async () => {
    const wb = new ExcelJS.Workbook();
    writeCustomerSheet(wb, rows.slice(0, 1));
    wb.worksheets[0].getCell('A2').value = 1500;
    wb.worksheets[0].getCell('H2').value = 99.5;
    expect(readCustomerSheet(wb)[0]).toMatchObject({ customer_number: '1500', credit_limit: '99.5' });
  });
});
