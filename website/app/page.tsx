import { HeroSection } from '@/components/features/home/HeroSection';
import { FeaturedProducts } from '@/components/features/home/FeaturedProducts';
import { AboutSection } from '@/components/features/home/AboutSection';
import { CTASection } from '@/components/features/home/CTASection';
import { mockProducts } from '@/lib/mock-data';

export default function HomePage() {
  return (
    <>
      <HeroSection />
      <FeaturedProducts products={mockProducts} />
      <AboutSection />
      <CTASection />
      <footer className="border-t border-border bg-muted/30 py-10">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div className="flex flex-col items-center justify-between gap-4 sm:flex-row">
            <span
              className="text-lg font-semibold text-foreground"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              Alpine<span className="text-primary"> Bakery</span>
            </span>
            <p className="text-sm text-muted-foreground">
              &copy; {new Date().getFullYear()} Alpine Bakery. All rights reserved.
            </p>
            <div className="flex gap-6 text-sm text-muted-foreground">
              <a href="#" className="hover:text-foreground transition-colors">Privacy</a>
              <a href="#" className="hover:text-foreground transition-colors">Terms</a>
              <a href="#" className="hover:text-foreground transition-colors">Contact</a>
            </div>
          </div>
        </div>
      </footer>
    </>
  );
}
