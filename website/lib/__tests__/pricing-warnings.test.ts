import { describe, expect, it } from 'vitest';
import { shadowedRows, type AssignmentLike } from '../pricing-warnings';

const row = (key: string, type: string, start: string, end = '', over: Partial<AssignmentLike> = {}): AssignmentLike =>
  ({ _key: key, assignment_type: type, status: 'Approved', is_active: true, effective_start_date: start, effective_end_date: end, ...over });

describe('shadowedRows', () => {
  it('flags a seasonal book below an overlapping default', () => {
    const rows = [row('d', 'Default', '2026-01-01'), row('s', 'Seasonal', '2026-12-15', '2026-12-25')];
    expect(shadowedRows(rows).get('s')).toBe('d');
  });
  it('does not flag a seasonal book above the default', () => {
    const rows = [row('s', 'Seasonal', '2026-12-15', '2026-12-25'), row('d', 'Default', '2026-01-01')];
    expect(shadowedRows(rows).size).toBe(0);
  });
  it('ignores a default whose dates do not overlap', () => {
    const rows = [row('d', 'Default', '2026-01-01', '2026-06-30'), row('p', 'Promotional', '2026-12-01', '2026-12-31')];
    expect(shadowedRows(rows).size).toBe(0);
  });
  it('ignores inactive or archived defaults and inactive books', () => {
    expect(shadowedRows([row('d', 'Default', '2026-01-01', '', { is_active: false }), row('s', 'Seasonal', '2026-12-15')]).size).toBe(0);
    expect(shadowedRows([row('d', 'Default', '2026-01-01', '', { status: 'Archived' }), row('s', 'Seasonal', '2026-12-15')]).size).toBe(0);
    expect(shadowedRows([row('d', 'Default', '2026-01-01'), row('s', 'Seasonal', '2026-12-15', '', { is_active: false })]).size).toBe(0);
  });
  it('treats open ended ranges as overlapping', () => {
    const rows = [row('d', 'Default', '2026-01-01'), row('i', 'Introductory', '2027-03-01')];
    expect(shadowedRows(rows).get('i')).toBe('d');
  });
});
