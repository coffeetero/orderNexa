'use client';

import { useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { LayoutDashboard, ClipboardList, ChefHat, Users, Package, DollarSign, ChevronRight, ChevronLeft, Wheat, X, FileText, TrendingUp, Receipt, ChartBar as BarChart2, Tags, Boxes, FlaskConical, Trash2, Calculator, Leaf, CreditCard, ArrowLeftRight, Scale, Banknote, ChartPie as PieChart } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';

interface NavChild {
  label: string;
  href: string;
  icon: React.ElementType;
}

interface NavSection {
  label: string;
  href?: string;
  icon: React.ElementType;
  children?: NavChild[];
}

const navSections: NavSection[] = [
  {
    label: 'Dashboard',
    href: '/tenant',
    icon: LayoutDashboard,
  },
  {
    label: 'Order Management',
    icon: ClipboardList,
    children: [
      { label: 'Post Standing Orders', href: '/tenant/orders/standing', icon: FileText },
      { label: 'Call Up List', href: '/tenant/orders/callup', icon: ClipboardList },
      { label: 'Manage Orders', href: '/tenant/orders', icon: ClipboardList },
      { label: 'Import Orders', href: '/tenant/orders/import', icon: FileText },
      { label: 'Returns & Credits', href: '/tenant/orders/returns', icon: ArrowLeftRight },
    ],
  },
  {
    label: 'Production',
    icon: ChefHat,
    children: [
      { label: 'Order Analysis', href: '/tenant/production/analysis', icon: BarChart2 },
      { label: 'Estimate Production', href: '/tenant/production/estimate', icon: Calculator },
      { label: "Baker's Report", href: '/tenant/production/report', icon: FileText },
      { label: 'Packing Labels', href: '/tenant/production/labels', icon: Tags },
      { label: 'Route Delivery Report', href: '/tenant/production/routes', icon: TrendingUp },
      { label: 'Mixing Sheets', href: '/tenant/production/mixing', icon: FlaskConical },
    ],
  },
  {
    label: 'Customers',
    icon: Users,
    children: [
      { label: 'Customer Management', href: '/tenant/customers', icon: Users },
      { label: 'Pricing Lists', href: '/tenant/customers/pricing', icon: Tags },
      { label: 'Reports', href: '/tenant/customers/reports', icon: BarChart2 },
      { label: 'Exports', href: '/tenant/customers/exports', icon: FileText },
    ],
  },
  {
    label: 'Inventory',
    icon: Package,
    children: [
      { label: 'Manage Items', href: '/tenant/inventory', icon: Boxes },
      { label: 'Pricing Lists', href: '/tenant/inventory/pricing', icon: Tags },
      { label: 'Recipes', href: '/tenant/inventory/recipes', icon: FlaskConical },
      { label: 'Waste Tracking', href: '/tenant/inventory/waste', icon: Trash2 },
      { label: 'Reports', href: '/tenant/inventory/reports', icon: BarChart2 },
      { label: 'Analysis', href: '/tenant/inventory/analysis', icon: PieChart },
      { label: 'Costing & COGS', href: '/tenant/inventory/costing', icon: Calculator },
      { label: 'Nutritional Analysis', href: '/tenant/inventory/nutrition', icon: Leaf },
      { label: 'Nutrition Labels', href: '/tenant/inventory/labels', icon: Tags },
    ],
  },
  {
    label: 'Financials',
    icon: DollarSign,
    children: [
      { label: 'Manage Payments', href: '/tenant/financials/payments', icon: CreditCard },
      { label: 'Enter Credits', href: '/tenant/financials/credits', icon: ArrowLeftRight },
      { label: 'Enter Returns', href: '/tenant/financials/returns', icon: ArrowLeftRight },
      { label: 'Customer Statements', href: '/tenant/financials/statements', icon: FileText },
      { label: 'AR Open Balances', href: '/tenant/financials/ar', icon: Scale },
      { label: 'AR Aging Report', href: '/tenant/financials/aging', icon: BarChart2 },
      { label: 'Cash Reconciliation', href: '/tenant/financials/cash', icon: Banknote },
      { label: 'Sales Reports', href: '/tenant/financials/sales', icon: TrendingUp },
      { label: 'Revenue Forecasting', href: '/tenant/financials/forecast', icon: PieChart },
    ],
  },
];

interface TenantSidebarProps {
  collapsed: boolean;
  onCollapse: (v: boolean) => void;
  mobileOpen: boolean;
  onMobileClose: () => void;
}

function NavItem({
  section,
  collapsed,
  pathname,
}: {
  section: NavSection;
  collapsed: boolean;
  pathname: string;
}) {
  const isActive =
    section.href === pathname ||
    section.children?.some((c) => pathname.startsWith(c.href));

  const [open, setOpen] = useState(isActive ?? false);

  if (!section.children) {
    return (
      <Link
        href={section.href!}
        className={cn(
          'flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors',
          isActive
            ? 'bg-primary text-primary-foreground'
            : 'text-foreground/70 hover:bg-muted hover:text-foreground'
        )}
      >
        <section.icon className={cn('h-4 w-4 shrink-0', collapsed && 'mx-auto')} />
        {!collapsed && <span>{section.label}</span>}
      </Link>
    );
  }

  return (
    <div>
      <button
        onClick={() => setOpen(!open)}
        className={cn(
          'flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors',
          isActive
            ? 'bg-primary/10 text-primary'
            : 'text-foreground/70 hover:bg-muted hover:text-foreground'
        )}
      >
        <section.icon className={cn('h-4 w-4 shrink-0', collapsed && 'mx-auto')} />
        {!collapsed && (
          <>
            <span className="flex-1 text-left">{section.label}</span>
            <ChevronRight
              className={cn('h-3.5 w-3.5 shrink-0 transition-transform', open && 'rotate-90')}
            />
          </>
        )}
      </button>
      {!collapsed && open && (
        <div className="mt-1 ml-4 pl-3 border-l border-border/60 space-y-0.5">
          {section.children.map((child) => (
            <Link
              key={child.href}
              href={child.href}
              className={cn(
                'flex items-center gap-2.5 rounded-md px-2 py-1.5 text-xs font-medium transition-colors',
                pathname === child.href
                  ? 'text-primary bg-primary/8'
                  : 'text-foreground/60 hover:text-foreground hover:bg-muted'
              )}
            >
              <child.icon className="h-3.5 w-3.5 shrink-0" />
              {child.label}
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}

export function TenantSidebar({
  collapsed,
  onCollapse,
  mobileOpen,
  onMobileClose,
}: TenantSidebarProps) {
  const pathname = usePathname();

  const sidebarContent = (
    <div className="flex h-full flex-col">
      <div className={cn('flex h-14 items-center border-b border-border px-3', collapsed ? 'justify-center' : 'justify-between')}>
        {!collapsed && (
          <Link href="/" className="flex items-center gap-2">
            <Wheat className="h-4 w-4 text-primary" />
            <span
              className="text-sm font-semibold text-foreground"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              Alpine Bakery
            </span>
          </Link>
        )}
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7 text-muted-foreground hover:text-foreground hidden lg:flex"
          onClick={() => onCollapse(!collapsed)}
        >
          {collapsed ? <ChevronRight className="h-4 w-4" /> : <ChevronLeft className="h-4 w-4" />}
        </Button>
        <Button
          variant="ghost"
          size="icon"
          className="h-7 w-7 text-muted-foreground lg:hidden"
          onClick={onMobileClose}
        >
          <X className="h-4 w-4" />
        </Button>
      </div>

      <nav className="flex-1 overflow-y-auto py-4 px-2 space-y-0.5 scrollbar-thin">
        {navSections.map((section) => (
          <NavItem
            key={section.label}
            section={section}
            collapsed={collapsed}
            pathname={pathname}
          />
        ))}
      </nav>

      <div className={cn('border-t border-border p-3', collapsed && 'flex justify-center')}>
        <Link
          href="/"
          className={cn(
            'flex items-center gap-2 text-xs text-muted-foreground hover:text-foreground transition-colors',
            collapsed && 'justify-center'
          )}
        >
          <Wheat className="h-3.5 w-3.5 shrink-0" />
          {!collapsed && <span>Back to Site</span>}
        </Link>
      </div>
    </div>
  );

  return (
    <>
      <aside
        className={cn(
          'hidden lg:flex flex-col border-r border-border bg-card transition-all duration-300 shrink-0',
          collapsed ? 'w-14' : 'w-60'
        )}
      >
        {sidebarContent}
      </aside>

      {mobileOpen && (
        <>
          <div
            className="fixed inset-0 z-40 bg-black/50 lg:hidden"
            onClick={onMobileClose}
          />
          <aside className="fixed inset-y-0 left-0 z-50 w-72 flex flex-col border-r border-border bg-card lg:hidden">
            {sidebarContent}
          </aside>
        </>
      )}
    </>
  );
}
