'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useState } from 'react';

const SITE = [
  { href: '/science', label: 'Science' },
  { href: '/collective', label: 'Collective' },
  { href: '/research', label: 'Research' },
  { href: '/team', label: 'Team' },
];
const APP = [
  { href: '/dashboard', label: 'Dashboard' },
  { href: '/sessions', label: 'Sessions' },
  { href: '/evidence', label: 'Evidence' },
  { href: '/benchmark', label: 'Benchmark' },
  { href: '/auditor', label: 'Auditor' },
];

export function SiteHeader() {
  const path = usePathname();
  const [open, setOpen] = useState(false);
  const item = (l: { href: string; label: string }) => (
    <Link key={l.href} href={l.href} onClick={() => setOpen(false)}
      className={`rounded px-2 py-1 transition-colors ${path === l.href ? 'text-fg' : 'text-muted hover:text-fg'}`}
      aria-current={path === l.href ? 'page' : undefined}>
      {l.label}
    </Link>
  );
  return (
    <header className="sticky top-0 z-40 border-b border-rule/80 bg-ink/85 backdrop-blur">
      <div className="mx-auto flex h-14 max-w-[1240px] items-center gap-6 px-4 sm:px-6">
        <Link href="/" className="flex items-center gap-2.5 font-semibold tracking-tight" aria-label="NeuroAssist × CI home">
          <Mark />
          <span className="whitespace-nowrap">NeuroAssist <span className="text-muted">×</span> CI</span>
        </Link>
        <nav className="hidden items-center gap-1 text-[0.94rem] lg:flex" aria-label="Site">{SITE.map(item)}</nav>
        <span className="hidden h-5 w-px bg-rule2 lg:block" aria-hidden />
        <nav className="hidden items-center gap-1 text-[0.94rem] lg:flex" aria-label="Application">{APP.map(item)}</nav>
        <div className="ml-auto flex items-center gap-2">
          <Link href="/demo" className="btn btn-primary whitespace-nowrap !py-1.5 !text-[0.9rem]"><span className="hidden sm:inline">Explore live demo</span><span className="sm:hidden">Live demo</span></Link>
          <button className="rounded p-2 text-muted hover:text-fg lg:hidden" aria-expanded={open} aria-controls="mnav" onClick={() => setOpen(!open)}>
            <span className="sr-only">Menu</span>
            <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden><path d="M3 6h14M3 10h14M3 14h14" stroke="currentColor" strokeWidth="1.6" /></svg>
          </button>
        </div>
      </div>
      {open && (
        <nav id="mnav" className="grid grid-cols-2 gap-1 border-t border-rule px-4 py-3 text-base lg:hidden" aria-label="Menu">
          {[...SITE, ...APP, { href: '/demo', label: 'Live demo' }].map(item)}
        </nav>
      )}
    </header>
  );
}

function Mark() {
  return (
    <svg width="22" height="22" viewBox="0 0 22 22" aria-hidden>
      <circle cx="11" cy="11" r="10" fill="none" stroke="#243341" />
      <path d="M2.5 13 L6 13 L8.2 6.5 L11 16 L13.4 9.5 L15 13 L19.5 13" fill="none" stroke="#3ED6C5" strokeWidth="1.6" strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  );
}
