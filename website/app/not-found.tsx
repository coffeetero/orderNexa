import Link from 'next/link';
import { Wheat } from 'lucide-react';
import { Button } from '@/components/ui/button';

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 px-6 text-center">
      <span className="flex h-12 w-12 items-center justify-center rounded-full bg-primary/10 text-primary">
        <Wheat className="h-6 w-6" />
      </span>
      <h1 className="text-3xl font-bold" style={{ fontFamily: "'Playfair Display', Georgia, serif" }}>
        Page not found
      </h1>
      <p className="max-w-sm text-sm text-muted-foreground">
        This page doesn&apos;t exist or hasn&apos;t been built yet.
      </p>
      <Button asChild>
        <Link href="/">Back to home</Link>
      </Button>
    </div>
  );
}
