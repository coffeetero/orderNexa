import { OrderEntryForm } from '@/components/features/tenant/order-entry/OrderEntryForm';

export const metadata = {
  title: 'New Order — Order Entry',
};

export default function NewOrderPage() {
  return (
    <div className="h-full overflow-hidden -mx-[10px] -my-[1px]">
      <OrderEntryForm mode="new" />
    </div>
  );
}
