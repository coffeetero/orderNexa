'use client';

import { useMemo } from 'react';
import { EntityComboBox } from '@/components/bps/EntityComboBox';
import type { CustomerOption } from '@/components/features/account/order-entry/OrderHeaderRow';

const label = (c: CustomerOption) => (c.customer_number ? `${c.customer_number} - ${c.customer_name}` : c.customer_name);

/** The Enter Orders customer search limited to customer accounts (no sites or departments), for screens that work per account. `customers` null = still loading. */
export function AccountPicker({ customers, value, onChange, id }: {
  customers: CustomerOption[] | null; value: CustomerOption | null; onChange: (account: CustomerOption | null) => void; id: string;
}) {
  const accounts = useMemo(() => (customers ?? []).filter((c) => (c.customer_type ?? '').trim().toUpperCase() === 'ACCOUNT'), [customers]);

  return (
    <EntityComboBox<CustomerOption>
      items={accounts}
      value={value?.customer_id ?? null}
      onChange={onChange}
      getId={(c) => c.customer_id}
      getLabel={label}
      getSearchText={(c) => `${c.customer_number ?? ''} ${c.customer_name}`}
      getParentId={() => null}
      getSortKey={(c) => c.sort_path}
      placeholder="Search number or name…"
      disabled={customers === null}
      loading={customers === null}
      emptyText="No customer accounts found."
      clearable
      alwaysOpen
      collapseOnSelect
      clearSearchOnFocus
      triggerId={id}
    />
  );
}
