import Link from 'next/link';
import { ArrowRight, Building2, ShoppingBag } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';

export function CTASection() {
  return (
    <section className="py-24 bg-background">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="mb-12 text-center">
          <div className="mb-4 flex items-center gap-2 justify-center">
            <div className="h-px w-16 bg-border" />
            <span className="text-xs font-medium uppercase tracking-widest text-primary">Get Started</span>
            <div className="h-px w-16 bg-border" />
          </div>
          <h2
            className="text-4xl font-bold text-foreground sm:text-5xl mb-4"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            Ready to Work With Us?
          </h2>
          <p className="text-muted-foreground text-lg max-w-xl mx-auto">
            Whether you manage a restaurant, hotel, or café — our platform makes ordering
            and managing your artisan bread account effortless.
          </p>
        </div>

        <div className="grid grid-cols-1 gap-6 md:grid-cols-2 max-w-4xl mx-auto">
          <Card className="border-border/60 bg-primary text-primary-foreground overflow-hidden hover:shadow-xl transition-shadow duration-300 group">
            <CardContent className="p-8">
              <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-primary-foreground/15 group-hover:bg-primary-foreground/20 transition-colors">
                <Building2 className="h-6 w-6 text-primary-foreground" />
              </div>
              <h3
                className="text-2xl font-bold mb-3"
                style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
              >
                Bakery Operators
              </h3>
              <p className="text-primary-foreground/80 mb-6 leading-relaxed text-sm">
                Manage your wholesale operation end-to-end. Production planning,
                order management, customer invoicing, and delivery routes — all in one platform.
              </p>
              <ul className="space-y-2 mb-8 text-sm text-primary-foreground/80">
                {['Production scheduling & reporting', 'Route delivery management', 'Customer AR & invoicing', 'Inventory & recipe costing'].map((item) => (
                  <li key={item} className="flex items-center gap-2">
                    <div className="h-1.5 w-1.5 rounded-full bg-primary-foreground/60" />
                    {item}
                  </li>
                ))}
              </ul>
              <Button asChild variant="secondary" className="w-full group/btn">
                <Link href="/login?role=tenant">
                  Access Bakery Dashboard
                  <ArrowRight className="ml-2 h-4 w-4 transition-transform group-hover/btn:translate-x-1" />
                </Link>
              </Button>
            </CardContent>
          </Card>

          <Card className="border-border/60 bg-card overflow-hidden hover:shadow-xl transition-shadow duration-300 group">
            <CardContent className="p-8">
              <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10 group-hover:bg-primary/15 transition-colors">
                <ShoppingBag className="h-6 w-6 text-primary" />
              </div>
              <h3
                className="text-2xl font-bold text-foreground mb-3"
                style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
              >
                Restaurant & Café Buyers
              </h3>
              <p className="text-muted-foreground mb-6 leading-relaxed text-sm">
                Place and manage your standing orders, view delivery schedules, access invoices,
                and track payment history — without a phone call.
              </p>
              <ul className="space-y-2 mb-8 text-sm text-muted-foreground">
                {['Online ordering 24/7', 'Standing order management', 'Invoice & statement access', 'Payment history & tracking'].map((item) => (
                  <li key={item} className="flex items-center gap-2">
                    <div className="h-1.5 w-1.5 rounded-full bg-primary/50" />
                    {item}
                  </li>
                ))}
              </ul>
              <Button asChild className="w-full group/btn">
                <Link href="/login?role=customer">
                  Access Customer Portal
                  <ArrowRight className="ml-2 h-4 w-4 transition-transform group-hover/btn:translate-x-1" />
                </Link>
              </Button>
            </CardContent>
          </Card>
        </div>

        <div className="mt-12 text-center">
          <p className="text-muted-foreground text-sm">
            Interested in partnering with us?{' '}
            <a href="mailto:wholesale@maisonboulange.com" className="text-primary hover:underline font-medium">
              Contact our wholesale team
            </a>
          </p>
        </div>
      </div>
    </section>
  );
}
