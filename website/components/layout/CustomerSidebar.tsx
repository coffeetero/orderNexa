'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useState } from 'react';
import {
  LayoutDashboard,
  ClipboardList,
  FileText,
  CreditCard,
  History,
  ShoppingBag,
  ChevronDown,
} from 'lucide-react';
import { cn } from '@/lib/utils';

const navItems = [
  {
    label: 'Dashboard',
    href: '/customer',
    icon: LayoutDashboard,
  },
  {
    label: 'Orders',
    icon: ClipboardList,
    children: [
      { label: 'Manage Orders', href: '/customer/orders', icon: ShoppingBag },
      { label: 'Order History', href: '/customer/orders/history', icon: History },
    ],
  },
  {
    label: 'Invoicing',
    icon: FileText,
    children: [
      { label: 'Statements', href: '/customer/invoicing', icon: FileText },
      { label: 'Invoice History', href: '/customer/invoicing/history', icon: History },
    ],
  },
  {
    label: 'Payments',
    icon: CreditCard,
    children: [
      { label: 'Manage Payments', href: '/customer/payments', icon: CreditCard },
      { label: 'Payment History', href: '/customer/payments/history', icon: History },
    ],
  },
];

interface CustomerSidebarProps {
  mobileOpen: boolean;
  onMobileClose: () => void;
  collapsed?: boolean;
}

export function CustomerSidebar({ mobileOpen, onMobileClose, collapsed = false }: CustomerSidebarProps) {
  const pathname = usePathname();
  const [ordersOpen, setOrdersOpen] = useState(true);
  const [invoicingOpen, setInvoicingOpen] = useState(true);
  const [paymentsOpen, setPaymentsOpen] = useState(true);

  const sidebarContent = (
    <div className="flex h-full flex-col">
      <nav className="flex-1 overflow-y-auto py-4 px-2 space-y-1">
        {navItems.map((item) => {
          if (!item.children) {
            const isActive = pathname === item.href;
            return (
              <Link
                key={item.label}
                href={item.href!}
                className={cn(
                  'flex items-center rounded-lg px-3 py-2.5 text-sm font-medium transition-colors',
                  collapsed ? 'justify-center' : 'gap-3',
                  isActive
                    ? 'bg-primary text-primary-foreground'
                    : 'text-foreground/70 hover:bg-muted hover:text-foreground'
                )}
              >
                <item.icon className="h-4 w-4 shrink-0" />
                {!collapsed && item.label}
              </Link>
            );
          }

          const isSectionActive = item.children.some((c) => pathname === c.href);
          const isOpen =
            item.label === 'Orders'
              ? ordersOpen
              : item.label === 'Invoicing'
                ? invoicingOpen
                : paymentsOpen;
          const toggleOpen =
            item.label === 'Orders'
              ? () => setOrdersOpen((prev) => !prev)
              : item.label === 'Invoicing'
                ? () => setInvoicingOpen((prev) => !prev)
                : () => setPaymentsOpen((prev) => !prev);

          return (
            <div key={item.label}>
              <button
                type="button"
                onClick={toggleOpen}
                className={cn(
                  'flex w-full items-center rounded-lg px-3 py-2 text-xs font-semibold uppercase tracking-wider',
                  collapsed ? 'justify-center' : 'gap-3',
                  isSectionActive ? 'text-primary' : 'text-muted-foreground'
                )}
              >
                <item.icon className="h-3.5 w-3.5 shrink-0" />
                {!collapsed && <span className="flex-1 text-left">{item.label}</span>}
                {!collapsed && (
                  <ChevronDown
                    className={cn('h-3.5 w-3.5 shrink-0 transition-transform', !isOpen && '-rotate-90')}
                  />
                )}
              </button>
              {!collapsed && isOpen && (
                <div className="ml-4 pl-3 border-l border-border/60 space-y-0.5">
                  {item.children.map((child) => (
                    <Link
                      key={child.href}
                      href={child.href}
                      className={cn(
                        'flex items-center gap-2.5 rounded-md px-2 py-1.5 text-sm font-medium transition-colors',
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
        })}
      </nav>

      <div className={cn('border-t border-border', collapsed ? 'p-2' : 'p-4')}>
        <div className="rounded-lg bg-primary/8 p-3">
          {!collapsed && (
            <>
              <p className="text-xs font-semibold text-foreground mb-0.5">Le Jardin Restaurant</p>
              <p className="text-[10px] text-muted-foreground">Account: ACC-0042</p>
            </>
          )}
        </div>
      </div>
    </div>
  );

  return (
    <>
      <aside
        className={cn(
          'hidden lg:flex shrink-0 flex-col border-r border-border bg-card transition-all',
          collapsed ? 'w-16' : 'w-56'
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
          <aside className="fixed inset-y-0 left-0 z-50 w-64 flex flex-col border-r border-border bg-card lg:hidden">
            {sidebarContent}
          </aside>
        </>
      )}
    </>
  );
}
