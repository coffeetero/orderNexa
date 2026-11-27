import { describe, expect, it } from 'vitest';
import { builtActions, tenantNav } from '@/lib/nav-config';
import { DEFAULT_QUICK_BUTTONS, selectQuickButtons } from '@/lib/quick-access';

const allowed = builtActions(tenantNav);

describe('selectQuickButtons', () => {
  it('defaults are real, built screens', () => {
    expect(selectQuickButtons([], allowed)).toEqual(DEFAULT_QUICK_BUTTONS);
  });
  it('pinned actions come first, defaults fill the rest without duplicates', () => {
    expect(selectQuickButtons(['/manage-orders', '/customers'], allowed)).toEqual([
      '/manage-orders', '/customers', '/orders', '/financials/enter-payments',
    ]);
  });
  it('drops actions the user may not open', () => {
    const limited = allowed.filter((a) => a.href !== '/financials/enter-payments');
    expect(selectQuickButtons(['/nope'], limited)).toEqual(['/orders', '/customers', '/inventory/item-profile']);
  });
});
