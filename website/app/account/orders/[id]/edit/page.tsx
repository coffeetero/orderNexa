import { OrderEntryForm } from '@/components/features/tenant/order-entry/OrderEntryForm';

export const metadata = {
  title: 'Edit Order — Order Entry',
};

interface EditOrderPageProps {
  params: { id: string };
}

export default function EditOrderPage({ params }: EditOrderPageProps) {
  const orderId = parseInt(params.id, 10);

  if (isNaN(orderId)) {
    return (
      <div className="p-6 text-sm text-destructive">
        Invalid order ID.
      </div>
    );
  }

  return (
    <div className="h-full overflow-hidden -mx-[10px] -my-[1px]">
      <OrderEntryForm mode="edit" orderId={orderId} />
    </div>
  );
}
