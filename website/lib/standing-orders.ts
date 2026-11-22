import { isIsoDate } from '@/lib/date';

export type StandingOrderLine = {
  item_id: number;
  item_name: string;
  quantity: number;
  prep_options?: string[] | null;
};

export type ItemPrice = { item_id: number; unit_price: number | null };

const DOW = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'] as const;

/** MON/TUE/... for an ISO date, or null when the date is not a valid YYYY-MM-DD. */
export function dowFromDate(dateStr: string): string | null {
  if (!isIsoDate(dateStr)) return null;
  return DOW[new Date(`${dateStr}T00:00:00`).getDay()];
}

/** item_id -> effective unit price from the customer's pricebook (null/missing => 0, like Enter Orders). */
export function priceMap(items: ItemPrice[] | null | undefined): Map<number, number> {
  const map = new Map<number, number>();
  for (const item of items ?? []) {
    if (typeof item?.item_id === 'number' && typeof item.unit_price === 'number' && Number.isFinite(item.unit_price)) {
      map.set(item.item_id, item.unit_price);
    }
  }
  return map;
}

/** om_orders_save payload for a posted standing order — same structure as Enter Orders. */
export function buildPostedOrderPayload(args: {
  customerId: number;
  orderDate: string;
  productionDate: string;
  productionCode: string;
  lines: StandingOrderLine[];
  prices: Map<number, number>;
}) {
  const { customerId, orderDate, productionDate, productionCode, lines, prices } = args;
  return {
    customer_id: customerId,
    order_number: null,
    order_date: orderDate,
    production_date: productionDate,
    production_code: productionCode,
    department_event: null,
    delivery_amount: 0,
    lines: lines.map((l, i) => ({
      client_temp_id: `so-${customerId}-${i}`,
      order_line_id: null,
      item_id: l.item_id,
      item_description: l.item_name,
      quantity: l.quantity,
      unit_price: prices.get(l.item_id) ?? 0,
      unit_discount: 0,
      prep_options: l.prep_options ?? [],
      is_scored: false,
    })),
  };
}
