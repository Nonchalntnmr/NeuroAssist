import Link from 'next/link';
import { REPO_URL } from '@/lib/site';

export function SiteFooter() {
  return (
    <footer className="mt-24 border-t border-rule">
      <div className="mx-auto grid max-w-[1240px] gap-8 px-4 py-10 sm:px-6 md:grid-cols-[1.4fr_1fr_1fr]">
        <div className="space-y-3">
          <p className="font-semibold">NeuroAssist × CI</p>
          <p className="t-small max-w-[46ch]">
            Research prototype built for MIT ScienceClaw 2026. It measures eye movement and reasons about measurement
            quality. It does not diagnose any condition and is not a medical device. Data on this site is synthetic unless it is labelled otherwise.
          </p>
        </div>
        <div className="t-small space-y-2">
          <p className="text-fg">Platform</p>
          <ul className="space-y-1.5">
            <li><Link className="hover:text-fg" href="/demo">Guided demo</Link></li>
            <li><Link className="hover:text-fg" href="/benchmark">Benchmark results</Link></li>
            <li><Link className="hover:text-fg" href="/auditor">Evidence Auditor (reusable)</Link></li>
            <li><a className="hover:text-fg" href="/api/py/docs">API reference</a></li>
          </ul>
        </div>
        <div className="t-small space-y-2">
          <p className="text-fg">Source</p>
          <ul className="space-y-1.5">
            <li><a className="hover:text-fg" href={REPO_URL}>GitHub repository</a></li>
            <li><Link className="hover:text-fg" href="/research#limitations">Limitations</Link></li>
            <li><Link className="hover:text-fg" href="/team">Team</Link></li>
          </ul>
        </div>
      </div>
    </footer>
  );
}
