import { redirect } from 'next/navigation';

/** Legacy URL; order entry lives at /orders. */
export default function LegacyNewOrderRedirect() {
  redirect('/orders');
}
