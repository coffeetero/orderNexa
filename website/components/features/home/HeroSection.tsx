import Link from 'next/link';
import { ArrowRight, Award, Wheat } from 'lucide-react';
import { Button } from '@/components/ui/button';

export function HeroSection() {
  return (
    <section className="relative overflow-hidden">
      <div
        className="absolute inset-0 z-0"
        style={{
          // backgroundImage: `url('https://images.pexels.com/photos/1556688/pexels-photo-1556688.jpeg?auto=compress&cs=tinysrgb&w=1600')`,
          backgroundImage: `url('/images/alpineHero.webp')`,
          backgroundSize: 'cover',
          backgroundPosition: 'center 40%',
        }}
      >
        <div className="absolute inset-0 bg-gradient-to-r from-[#1a0f08]/90 via-[#1a0f08]/60 to-transparent dark:from-[#0d0806]/95 dark:via-[#0d0806]/70" />
      </div>

      <div className="relative z-10 mx-auto max-w-7xl px-4 py-32 sm:px-6 sm:py-40 lg:px-8 lg:py-48">
        <div className="max-w-2xl">
          <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-3 py-1 backdrop-blur-sm">
            <Award className="h-3.5 w-3.5 text-amber-300" />
            <span className="text-xs font-medium text-white/90 tracking-wide uppercase">
              European Artisan Tradition Since 1987
            </span>
          </div>

          <h1
            className="mb-6 text-5xl font-bold leading-tight tracking-tight text-white sm:text-6xl lg:text-7xl"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            Baked with{' '}
            <em className="not-italic text-amber-300">Patience.</em>
            <br />
            Delivered with Pride.
          </h1>

          <p className="mb-10 text-lg text-white/75 leading-relaxed max-w-lg">
            Slow-fermented sourdoughs, hand-laminated viennoiseries, and stone-baked artisan loaves.
            Crafted daily for the finest restaurants, hotels, and food service businesses.
          </p>

          <div className="flex flex-col gap-3 sm:flex-row">
            <Button asChild size="lg" className="bg-amber-600 hover:bg-amber-700 text-white border-0 font-medium group">
              <Link href="/login">
                Order Now
                <ArrowRight className="ml-2 h-4 w-4 transition-transform group-hover:translate-x-1" />
              </Link>
            </Button>
            <Button
              asChild
              size="lg"
              variant="outline"
              className="border-white/30 bg-white/10 text-white hover:bg-white/20 hover:border-white/50 backdrop-blur-sm"
            >
              <Link href="/#products">View Products</Link>
            </Button>
          </div>

          <div className="mt-12 flex items-center gap-8 border-t border-white/15 pt-8">
            {[
              { value: '200+', label: 'B2B Clients' },
              { value: '40+', label: 'Artisan Products' },
              { value: '6 days', label: 'Weekly Delivery' },
            ].map((stat) => (
              <div key={stat.label} className="text-white">
                <div
                  className="text-2xl font-bold text-amber-300"
                  style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
                >
                  {stat.value}
                </div>
                <div className="text-xs text-white/60 mt-0.5 font-medium tracking-wide">{stat.label}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="absolute bottom-0 left-0 right-0 h-24 bg-gradient-to-t from-background to-transparent z-10" />
    </section>
  );
}
