import type { Metadata, Viewport } from 'next';
import '@fontsource-variable/schibsted-grotesk';
import '@fontsource/ibm-plex-mono/400.css';
import '@fontsource/ibm-plex-mono/500.css';
import './globals.css';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';

export const metadata: Metadata = {
  title: { default: 'NeuroAssist × CI — The Nervous System Interface', template: '%s — NeuroAssist × CI' },
  description:
    'A decentralized scientific collective that observes eye-movement measurements, remembers personal context through Contextual Intelligence, and challenges its own conclusions. Research prototype; not a medical device.',
  metadataBase: new URL('https://neuroassist-ci.vercel.app'),
  openGraph: { title: 'NeuroAssist × CI', description: 'AI can read language. We are teaching it to investigate neurological signals.' },
};
export const viewport: Viewport = { themeColor: '#06090C', width: 'device-width', initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-ink text-fg">
        <a href="#main" className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-50 focus:rounded focus:bg-signal focus:px-3 focus:py-2 focus:text-ink">
          Skip to content
        </a>
        <SiteHeader />
        <main id="main">{children}</main>
        <SiteFooter />
      </body>
    </html>
  );
}
