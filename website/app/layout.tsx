import './globals.css';
import type { Metadata } from 'next';
import { cookies } from 'next/headers';
import { AppearanceProvider } from '@/components/theme/AppearanceProvider';
import { htmlMode, SYSTEM_MODE_SCRIPT, themeCss } from '@/lib/theme/apply';
import { APPEARANCE_COOKIE, DEFAULT_MODE, readCookie, toLocal } from '@/lib/theme/prefs';
import { DEFAULT_THEME } from '@/lib/theme/themes';
import { TenantProvider } from '@/lib/tenant-context';
import { Navbar } from '@/components/layout/Navbar';
import { Toaster } from '@/components/ui/sonner';
import { getSessionUser } from '@/lib/supabase/server';

export const metadata: Metadata = {
  title: 'Alpine Bakery — Artisan Bread Platform',
  description: 'Premium European artisan bakery management platform for wholesale and retail.',
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const user = await getSessionUser();

  // The theme last applied on this device (cookie), painted into the first HTML so there is no flash of the default colours.
  const saved = readCookie((await cookies()).get(APPEARANCE_COOKIE)?.value);
  const initial = saved ?? { mode: DEFAULT_MODE, theme: DEFAULT_THEME };
  const mode = htmlMode(initial.theme, initial.mode);

  return (
    <html lang="en" className={mode === 'dark' ? 'dark' : undefined} data-bps-theme={initial.theme.id} suppressHydrationWarning>
      <head>
        <style id="bps-theme" dangerouslySetInnerHTML={{ __html: themeCss(initial.theme, initial.mode) }} />
        {mode === 'system' && <script dangerouslySetInnerHTML={{ __html: SYSTEM_MODE_SCRIPT }} />}
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,500;0,600;0,700;1,400;1,500&family=Inter:wght@300;400;500;600&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="min-h-screen antialiased">
        <AppearanceProvider initial={saved ? toLocal(saved) : null}>
          <TenantProvider>
            {!user && <Navbar />}
            <main>{children}</main>
            <Toaster position="top-right" duration={3000} closeButton />
          </TenantProvider>
        </AppearanceProvider>
      </body>
    </html>
  );
}
