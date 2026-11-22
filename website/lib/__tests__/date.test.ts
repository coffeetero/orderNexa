import { describe, expect, it } from 'vitest';
import { isIsoDate, localDateIso } from '@/lib/date';

describe('localDateIso', () => {
  it('formats the local calendar date, not the UTC date', () => {
    // 9pm local on Nov 22: toISOString() would roll over to Nov 23 in US time zones.
    const evening = new Date(2026, 10, 22, 21, 0, 0);
    expect(localDateIso(0, evening)).toBe('2026-11-22');
  });

  it('applies day offsets across month and year boundaries', () => {
    expect(localDateIso(1, new Date(2026, 10, 30))).toBe('2026-12-01');
    expect(localDateIso(1, new Date(2026, 11, 31))).toBe('2027-01-01');
    expect(localDateIso(-14, new Date(2026, 0, 5))).toBe('2025-12-22');
  });
});

describe('isIsoDate', () => {
  it('accepts real calendar dates', () => {
    expect(isIsoDate('2026-02-28')).toBe(true);
    expect(isIsoDate('2028-02-29')).toBe(true);
  });
  it('rejects malformed or impossible dates', () => {
    expect(isIsoDate('2026-02-30')).toBe(false);
    expect(isIsoDate('2026-2-3')).toBe(false);
    expect(isIsoDate('not-a-date')).toBe(false);
    expect(isIsoDate(undefined)).toBe(false);
    expect(isIsoDate(20261122)).toBe(false);
  });
});
