'use client';

import { useEffect, useState } from 'react';
import { DAY_SHORT, call, shortDate, type Day } from '@/components/features/delivery/routes-ui';

interface CustomerStop { day_of_week: Day; production_code: string; production_label: string; route_code: string; route_name: string; route_active: boolean; stop_no: number; inherited_from: string | null }
interface CustomerChange { exception_date: string; production_code: string; kind: 'SKIP' | 'ROUTE'; route_code: string | null; stop_no: number | null }

/** Days with the same route and stop together: "Every day", or "Mon, Tue, Fri". */
function groupDays(stops: CustomerStop[]) {
  const groups = new Map<string, { key: string; route_code: string; stop_no: number; active: boolean; list: Day[] }>();
  stops.forEach((s) => {
    const key = `${s.route_code}|${s.stop_no}`;
    const g = groups.get(key) ?? { key, route_code: s.route_code, stop_no: s.stop_no, active: s.route_active, list: [] };
    g.list.push(s.day_of_week);
    groups.set(key, g);
  });
  return Array.from(groups.values()).map((g) => ({ ...g, days: g.list.length === 7 ? 'Every day' : g.list.map((d) => DAY_SHORT[d]).join(', ') }));
}

/** Read-only "Delivery routes" lines on the customer profile; changed in Operations › Delivery › Routes Maintenance. */
export function CustomerRoutes({ tenantId, customerId }: { tenantId: number; customerId: number | null }) {
  const [data, setData] = useState<{ stops: CustomerStop[]; changes: CustomerChange[] } | null>(null);

  useEffect(() => {
    setData(null);
    if (!tenantId || customerId === null) return;
    call<{ stops: CustomerStop[]; changes: CustomerChange[] }>(`/api/customers/routes?tenant_id=${tenantId}&customer_id=${customerId}`)
      .then(setData)
      .catch(() => setData(null));
  }, [tenantId, customerId]);

  if (!data) return null;
  // one line per production time: "AM: Mon, Tue, Wed: 12 stop 3; Sat: 12 stop 2"
  const byCode = new Map<string, CustomerStop[]>();
  data.stops.forEach((s) => byCode.set(s.production_label, [...(byCode.get(s.production_label) ?? []), s]));
  const inherited = data.stops.find((s) => s.inherited_from)?.inherited_from;

  return (
    <div className="space-y-1 text-sm">
      <div className="text-xs font-semibold text-muted-foreground">Delivery routes <span className="font-normal">(read only; change them in Routes Maintenance)</span></div>
      {data.stops.length === 0 ? (
        <p className="text-muted-foreground">Not on any route.</p>
      ) : (
        <ul className="space-y-0.5">
          {Array.from(byCode.entries()).map(([label, stops]) => (
            <li key={label}>
              <span className="font-medium">{label}:</span>{' '}
              {groupDays(stops).map((g, i) => (
                <span key={g.key} className={g.active ? '' : 'text-muted-foreground'}>
                  {i > 0 ? '; ' : ''}{g.days}: {g.route_code} stop {g.stop_no}{g.active ? '' : ' (inactive route)'}
                </span>
              ))}
            </li>
          ))}
        </ul>
      )}
      {inherited && <p className="text-xs text-muted-foreground">Follows the stops of {inherited} where it has none of its own.</p>}
      {data.changes.length > 0 && (
        <p className="text-xs text-muted-foreground">
          Date changes: {data.changes.map((c) => `${shortDate(c.exception_date)} ${c.kind === 'SKIP' ? 'skipped' : `${c.route_code} stop ${c.stop_no}`}`).join(', ')}
        </p>
      )}
    </div>
  );
}
