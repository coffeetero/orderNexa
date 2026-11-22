import { describe, expect, it } from 'vitest';
import { buildPostedOrderPayload, dowFromDate, priceMap } from '@/lib/standing-orders';

describe('dowFromDate', () => {
  it('maps ISO dates to MON/TUE/... codes', () => {
    expect(dowFromDate('2026-11-22')).toBe('SUN');
    expect(dowFromDate('2026-11-23')).toBe('MON');
    expect(dowFromDate('2026-11-28')).toBe('SAT');
  });
  it('returns null for invalid dates instead of "undefined"', () => {
    expect(dowFromDate('garbage')).toBeNull();
    expect(dowFromDate('2026-13-01')).toBeNull();
  });
});

describe('priceMap', () => {
  it('keeps only finite numeric prices', () => {
    const m = priceMap([
      { item_id: 1, unit_price: 2.5 },
      { item_id: 2, unit_price: null },
      { item_id: 3, unit_price: Number.NaN },
    ]);
    expect(m.get(1)).toBe(2.5);
    expect(m.has(2)).toBe(false);
    expect(m.has(3)).toBe(false);
  });
  it('tolerates null input', () => {
    expect(priceMap(null).size).toBe(0);
  });
});

describe('buildPostedOrderPayload', () => {
  const lines = [
    { item_id: 10, item_name: 'Baguette', quantity: 24, prep_options: ['SLICED'] },
    { item_id: 11, item_name: 'Rye', quantity: 6, prep_options: null },
  ];

  it('prices each line from the customer pricebook (regression: lines were posted at $0)', () => {
    const payload = buildPostedOrderPayload({
      customerId: 7,
      orderDate: '2026-11-22',
      productionDate: '2026-11-23',
      productionCode: 'AM',
      lines,
      prices: new Map([[10, 1.75]]),
    });
    expect(payload.lines[0].unit_price).toBe(1.75);
    // No pricebook price => 0, same rule as Enter Orders.
    expect(payload.lines[1].unit_price).toBe(0);
  });

  it('keeps the Enter Orders payload shape', () => {
    const payload = buildPostedOrderPayload({
      customerId: 7, orderDate: '2026-11-22', productionDate: '2026-11-23',
      productionCode: 'AM', lines, prices: new Map(),
    });
    expect(payload).toMatchObject({
      customer_id: 7, order_number: null, order_date: '2026-11-22',
      production_date: '2026-11-23', production_code: 'AM', department_event: null, delivery_amount: 0,
    });
    expect(payload.lines[0]).toMatchObject({
      client_temp_id: 'so-7-0', order_line_id: null, item_id: 10, item_description: 'Baguette',
      quantity: 24, unit_discount: 0, prep_options: ['SLICED'], is_scored: false,
    });
    expect(payload.lines[1].prep_options).toEqual([]);
  });
});
