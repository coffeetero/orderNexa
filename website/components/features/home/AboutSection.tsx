import { Clock, Leaf, Flame, Award } from 'lucide-react';

const pillars = [
  {
    icon: Clock,
    title: 'Slow Fermentation',
    description: 'All our sourdoughs and levains are fermented for a minimum of 18 hours, developing complex flavour and superior digestibility.',
  },
  {
    icon: Leaf,
    title: 'Premium Ingredients',
    description: 'Sourced from certified mills and farms across France, Italy, and the UK. Organic heritage wheats, stone-ground flours, and AOC butters.',
  },
  {
    icon: Flame,
    title: 'Stone-Baked Daily',
    description: 'Our deck ovens reach 280°C — replicating the conditions of traditional European artisan bakeries for the perfect crust and crumb.',
  },
  {
    icon: Award,
    title: 'Certified Artisans',
    description: 'Our bakers hold accreditations from the Ecole Nationale Supérieure de la Boulangerie, ensuring craft and consistency.',
  },
];

export function AboutSection() {
  return (
    <section id="about" className="py-24 bg-muted/30">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="grid grid-cols-1 gap-16 lg:grid-cols-2 items-center">
          <div>
            <div className="mb-4">
              <span className="text-xs font-medium uppercase tracking-widest text-primary">Our Philosophy</span>
            </div>
            <h2
              className="text-4xl font-bold text-foreground sm:text-5xl mb-6 leading-tight"
              style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
            >
              Where European Craft<br />
              <em className="not-italic text-primary">Meets Modern Precision</em>
            </h2>
            <p className="text-muted-foreground text-lg leading-relaxed mb-6">
              Founded in Lyon in 1987 by master baker Jacques Moreaux, Alpine Bakery has grown
              from a single atelier to a leading artisan bakery serving premium food service
              clients across North America and Europe.
            </p>
            <p className="text-muted-foreground leading-relaxed mb-8">
              We believe that the best bread cannot be rushed. Every loaf is a result of careful
              timing, skilled hands, and unwavering commitment to the craft. Our bakehouse operates
              24 hours a day so that our clients receive the freshest product at delivery.
            </p>

            <div className="grid grid-cols-2 gap-4">
              {[
                { value: '37', label: 'Years of craft' },
                { value: '6', label: 'Production sites' },
                { value: '200+', label: 'Active clients' },
                { value: '40+', label: 'Artisan SKUs' },
              ].map((item) => (
                <div
                  key={item.label}
                  className="rounded-xl border border-border/60 bg-card p-4 text-center"
                >
                  <div
                    className="text-3xl font-bold text-primary mb-1"
                    style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
                  >
                    {item.value}
                  </div>
                  <div className="text-xs text-muted-foreground font-medium tracking-wide">
                    {item.label}
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="space-y-4">
            <div className="relative rounded-2xl overflow-hidden h-64">
              <img
                src="https://images.pexels.com/photos/5765/bakery-bread-baking-flour.jpg?auto=compress&cs=tinysrgb&w=800"
                alt="Baker at work"
                className="h-full w-full object-cover"
              />
              <div className="absolute inset-0 bg-gradient-to-tr from-primary/30 to-transparent" />
            </div>

            <div className="grid grid-cols-2 gap-4">
              {pillars.slice(0, 2).map((pillar) => (
                <div
                  key={pillar.title}
                  className="rounded-xl border border-border/60 bg-card p-4"
                >
                  <pillar.icon className="h-5 w-5 text-primary mb-2" />
                  <h4 className="font-semibold text-foreground text-sm mb-1">{pillar.title}</h4>
                  <p className="text-xs text-muted-foreground leading-relaxed line-clamp-3">
                    {pillar.description}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="mt-16 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {pillars.map((pillar) => (
            <div
              key={pillar.title}
              className="rounded-xl border border-border/60 bg-card p-6 hover:shadow-md hover:border-primary/30 transition-all duration-300"
            >
              <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                <pillar.icon className="h-5 w-5 text-primary" />
              </div>
              <h3 className="font-semibold text-foreground mb-2">{pillar.title}</h3>
              <p className="text-sm text-muted-foreground leading-relaxed">{pillar.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
