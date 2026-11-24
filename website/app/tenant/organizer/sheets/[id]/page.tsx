import { createClient } from '@/lib/supabase/server';
import { SheetEditor } from '@/components/features/organizer/SheetEditor';

export const metadata = {
  title: 'Sheet — Organizer',
};

export default async function SheetPage({ params }: { params: { id: string } }) {
  const { data } = await createClient().rpc('fnd_tenants_get');
  const tenants = Array.isArray(data) ? data : [];
  const tenantId: number | null = tenants.length > 0 ? tenants[0].tenant_id : null;
  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const sheetId = params.id === 'new' ? null : Number(params.id);
  if (sheetId !== null && !Number.isSafeInteger(sheetId)) {
    return <div className="p-6 text-sm text-muted-foreground">Sheet not found.</div>;
  }
  return <SheetEditor key={params.id} tenantId={tenantId} sheetId={sheetId} />;
}
