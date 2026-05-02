export type UserRole = 'tenant' | 'customer';

export interface Customer {
  id: string;
  name: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  accountNumber: string;
  status: 'active' | 'inactive' | 'suspended';
  balance: number;
  creditLimit: number;
  joinedAt: string;
  deliveryRoute?: string;
}

export interface Item {
  id: string;
  sku: string;
  name: string;
  category: string;
  unit: string;
  unitPrice: number;
  cost: number;
  stock: number;
  description?: string;
  isActive: boolean;
}

export interface OrderLine {
  id: string;
  itemId: string;
  itemName: string;
  sku: string;
  quantity: number;
  unitPrice: number;
  total: number;
}

export type OrderStatus =
  | 'pending'
  | 'confirmed'
  | 'in_production'
  | 'packed'
  | 'dispatched'
  | 'delivered'
  | 'cancelled';

export interface Order {
  id: string;
  orderNumber: string;
  customerId: string;
  customerName: string;
  status: OrderStatus;
  lines: OrderLine[];
  total: number;
  deliveryDate: string;
  createdAt: string;
  route?: string;
  notes?: string;
}

export interface Invoice {
  id: string;
  invoiceNumber: string;
  customerId: string;
  customerName: string;
  orderId: string;
  orderNumber: string;
  amount: number;
  balance: number;
  status: 'open' | 'partial' | 'paid' | 'overdue';
  issuedAt: string;
  dueAt: string;
}

export interface Payment {
  id: string;
  paymentNumber: string;
  customerId: string;
  customerName: string;
  invoiceId?: string;
  amount: number;
  method: 'bank_transfer' | 'credit_card' | 'cash' | 'cheque';
  reference: string;
  paidAt: string;
  notes?: string;
}

export interface DashboardMetric {
  label: string;
  value: string | number;
  change?: number;
  changeLabel?: string;
  prefix?: string;
  suffix?: string;
}

export interface TenantDashboardMetrics {
  totalRevenue: DashboardMetric;
  totalOrders: DashboardMetric;
  activeCustomers: DashboardMetric;
  productionToday: DashboardMetric;
  outstandingAR: DashboardMetric;
  avgOrderValue: DashboardMetric;
}

export interface CustomerDashboardMetrics {
  totalOrders: DashboardMetric;
  openInvoices: DashboardMetric;
  lastOrderDate: DashboardMetric;
  outstandingBalance: DashboardMetric;
}

export interface Product {
  id: string;
  name: string;
  description: string;
  category: string;
  imageUrl: string;
  price: number;
  isNew: boolean;
  isFeatured: boolean;
}

export interface NavItem {
  label: string;
  href: string;
  icon?: string;
  children?: NavItem[];
}

// ─── Order Entry ────────────────────────────────────────────────────────────

export type DeliveryWindow = 'AM' | 'PM' | 'SPECIAL';

/** An item row returned by om_get_items_for_order, used in the Item combobox. */
export interface OrderEntryItem {
  item_id: number;
  item_number: string;
  item_name: string;
  category: string | null;
  unit_of_sale: string;
  /** Preparation capabilities — drive which checkboxes are enabled on the line */
  is_sliceable: boolean;
  is_wrappable: boolean;
  is_coverable: boolean;
  is_scoreable: boolean;
  /** Prep defaults copied to the order line when item is first selected */
  default_sliced: boolean;
  default_wrapped: boolean;
  default_covered: boolean;
  default_scored: boolean;
  /** Effective unit price from customer pricebook; null when no pricebook found */
  unit_price: number | null;
}

/** A single line in the in-memory order entry draft. */
export interface OrderEntryLine {
  /** Client-side unique id (crypto.randomUUID or order_line_id stringified) */
  tempId: string;
  order_line_id?: number;
  item_id: number;
  item_number: string;
  item_description: string;
  /** Preparation flags — customer's choice for this line */
  is_sliced: boolean;
  is_wrapped: boolean;
  is_covered: boolean;
  is_scored: boolean;
  /** Capabilities from bps_items — enable/disable checkboxes in the grid */
  can_slice: boolean;
  can_wrap: boolean;
  can_cover: boolean;
  can_score: boolean;
  quantity: number;
  unit_price: number;
  unit_discount: number;
  /** Calculated: quantity * (unit_price - unit_discount) */
  extended_amount: number;
}

/** The full in-memory draft held by useOrderEntryState. */
export interface OrderEntryDraft {
  order_id?: number;
  order_number: string;
  customer_id: number | null;
  customer_name: string;
  /** AR credit balance for display — stub until fnd_get_customer_credit is implemented */
  customer_credit: number;
  order_date: string;
  delivery_date: string;
  delivery_window: DeliveryWindow;
  delivery_amount: number;
  /** Calculated: sum of all line extended_amount values */
  total_amount: number;
  lines: OrderEntryLine[];
}
