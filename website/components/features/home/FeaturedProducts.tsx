import { Badge } from '@/components/ui/badge';
import { Card, CardContent } from '@/components/ui/card';
import type { Product } from '@/lib/types';

interface FeaturedProductsProps {
  products: Product[];
}

function ProductCard({ product }: { product: Product }) {
  return (
    <Card className="overflow-hidden group border-border/60 bg-card hover:shadow-xl hover:-translate-y-1 transition-all duration-300">
      <div className="relative h-56 overflow-hidden">
        <img
          src={product.imageUrl}
          alt={product.name}
          className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-105"
        />
        <div className="absolute inset-0 bg-gradient-to-t from-black/30 to-transparent" />
        <div className="absolute top-3 left-3 flex gap-1.5">
          {product.isNew && (
            <Badge className="bg-amber-500 text-white border-0 text-xs font-medium">New</Badge>
          )}
          {product.isFeatured && (
            <Badge variant="secondary" className="bg-background/90 text-foreground text-xs">Featured</Badge>
          )}
        </div>
        <div className="absolute bottom-3 right-3">
          <span className="rounded-full bg-background/90 px-3 py-1 text-sm font-semibold text-foreground backdrop-blur-sm">
            ${product.price.toFixed(2)}
          </span>
        </div>
      </div>
      <CardContent className="p-5">
        <div className="mb-1.5">
          <span className="text-xs font-medium uppercase tracking-widest text-primary/70">
            {product.category}
          </span>
        </div>
        <h3
          className="text-lg font-semibold text-foreground mb-2 leading-tight"
          style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
        >
          {product.name}
        </h3>
        <p className="text-sm text-muted-foreground leading-relaxed line-clamp-2">
          {product.description}
        </p>
      </CardContent>
    </Card>
  );
}

export function FeaturedProducts({ products }: FeaturedProductsProps) {
  const featured = products.filter((p) => p.isFeatured).slice(0, 4);
  const newProducts = products.filter((p) => p.isNew).slice(0, 2);

  return (
    <section id="products" className="py-24 bg-background">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="mb-4 flex items-center gap-2">
          <div className="h-px flex-1 bg-border" />
          <span className="text-xs font-medium uppercase tracking-widest text-primary">Our Offering</span>
          <div className="h-px flex-1 bg-border" />
        </div>
        <div className="mb-12 text-center">
          <h2
            className="text-4xl font-bold text-foreground sm:text-5xl mb-4"
            style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
          >
            Featured Products
          </h2>
          <p className="text-muted-foreground text-lg max-w-2xl mx-auto leading-relaxed">
            Each product is crafted using traditional European methods — slow fermentation,
            quality ingredients, and skilled hands.
          </p>
        </div>

        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {featured.map((product) => (
            <ProductCard key={product.id} product={product} />
          ))}
        </div>

        {newProducts.length > 0 && (
          <div className="mt-16">
            <div className="mb-8 flex items-center gap-3">
              <h3
                className="text-2xl font-semibold text-foreground"
                style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
              >
                New Arrivals
              </h3>
              <Badge className="bg-amber-500/15 text-amber-700 dark:text-amber-400 border-amber-500/30">
                Just Launched
              </Badge>
            </div>
            <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
              {newProducts.map((product) => (
                <ProductCard key={product.id} product={product} />
              ))}
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
