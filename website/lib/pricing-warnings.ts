export interface AssignmentLike {
  _key: string;
  assignment_type: string;
  status: string;
  is_active: boolean;
  effective_start_date: string;
  effective_end_date: string;
}

const inForce = (r: AssignmentLike) => r.is_active && r.status !== 'Archived';
const overlap = (a: AssignmentLike, b: AssignmentLike) =>
  (!a.effective_end_date || !b.effective_start_date || b.effective_start_date <= a.effective_end_date) &&
  (!b.effective_end_date || !a.effective_start_date || a.effective_start_date <= b.effective_end_date);

/**
 * Rows (in table order) that a Default book above them can beat: precedence is strictly the table order, so a Seasonal,
 * Promotional or Introductory book sitting below a Default whose dates overlap loses to it for every item the Default holds.
 * Returns row key -> the key of the Default row that shadows it.
 */
export function shadowedRows(rows: AssignmentLike[]): Map<string, string> {
  const out = new Map<string, string>();
  rows.forEach((row, i) => {
    if (row.assignment_type === 'Default' || !inForce(row)) return;
    const above = rows.slice(0, i).find((r) => r.assignment_type === 'Default' && inForce(r) && overlap(r, row));
    if (above) out.set(row._key, above._key);
  });
  return out;
}
