import { createClient } from '@/lib/supabase/server';
import { requireArea } from '@/lib/supabase/guard';
import { ProductionSettings, type ProductionSection } from '@/components/features/admin/ProductionSettings';

export const metadata = {
  title: 'Application Settings — Admin',
};

const SECTIONS: ProductionSection[] = ['codes', 'methods', 'numbering', 'pricing', 'runs'];

export default async function AdminProductionPage({ searchParams }: { searchParams: { section?: string } }) {
  await requireArea('admin.production');
  // Resolve the tenant on the server (same pattern as Enter Orders); the browser session has no tenant_id claim.
  const { data } = await createClient().rpc('fnd_tenants_get');
  const tenants = Array.isArray(data) ? data : [];
  const tenantId: number | null = tenants.length > 0 ? tenants[0].tenant_id : null;

  if (tenantId === null) {
    return <div className="p-6 text-sm text-muted-foreground">No company found for this user.</div>;
  }
  const section = SECTIONS.find((s) => s === searchParams.section) ?? 'codes';
  return <ProductionSettings tenantId={tenantId} section={section} />;
}
