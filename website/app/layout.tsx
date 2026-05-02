import './globals.css';
import type { Metadata } from 'next';
import { ThemeProvider } from '@/lib/theme-provider';
import { TenantProvider } from '@/lib/tenant-context';
import { Navbar } from '@/components/layout/Navbar';
import { createClient } from '@/lib/supabase/server';

export const metadata: Metadata = {
  title: 'Alpine Bakery — Artisan Bread Platform',
  description: 'Premium European artisan bakery management platform for wholesale and retail.',
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,500;0,600;0,700;1,400;1,500&family=Inter:wght@300;400;500;600&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="min-h-screen antialiased">
        <ThemeProvider attribute="class" defaultTheme="light" enableSystem={false} disableTransitionOnChange>
          <TenantProvider>
            {!user && <Navbar />}
            <main>{children}</main>
          </TenantProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
