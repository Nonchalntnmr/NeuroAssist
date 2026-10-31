/** NeuroAssist (parent A) and CI (parent B) feed the collective (child) across one contract each. */
export function ArchitectureDiagram() {
  const box = 'rounded-xl border bg-panel p-5';
  return (
    <div className="grid items-stretch gap-4 lg:grid-cols-[1fr_auto_1.6fr_auto_1fr]">
      <div className={`${box} border-signal/40`}>
        <p className="font-semibold text-signal">NeuroAssist</p>
        <p className="t-small mt-1">Parent A. Camera measurement, signal engine <span className="readout">neurocore-0.4.0</span>, quality gate.</p>
        <ul className="t-small mt-4 space-y-1.5">
          <li>Gaze trace and head yaw</li><li>Slow-phase velocity with a 95% interval</li><li>Six gate checks, or an abstention</li>
        </ul>
      </div>
      <Arrow label="naci.session/1" color="#3ED6C5" />
      <div className={`${box} border-rule2`}>
        <p className="font-semibold">The collective</p>
        <p className="t-small mt-1">Child application. Five agents on a shared board; no planner.</p>
        <ul className="mt-4 grid gap-2 text-sm sm:grid-cols-2">
          {[
            ['#199e70', 'Signal quality', 'raw trace, device record'],
            ['#3987e5', 'Memory', 'CI only'],
            ['#d55181', 'Physiology', 'device record only'],
            ['#c98500', 'Skeptic', 'head channel, claims'],
            ['#9085e9', 'Evidence auditor', 'the evidence ledger'],
          ].map(([c, n, a]) => (
            <li key={n} className="flex items-start gap-2 rounded-lg border border-rule px-3 py-2">
              <span className="mt-1.5 h-2 w-2 shrink-0 rounded-sm" style={{ background: c }} aria-hidden />
              <span><span className="font-medium">{n}</span><span className="block text-xs text-muted">reads: {a}</span></span>
            </li>
          ))}
        </ul>
        <p className="t-small mt-4">Output: change, no change, measured without comparison, or abstain. With the evidence behind it.</p>
      </div>
      <Arrow label="ci.agent-message/1" color="#6E9BFF" reverse />
      <div className={`${box} border-memory/40`}>
        <p className="font-semibold text-memory">Contextual Intelligence</p>
        <p className="t-small mt-1">Parent B, pinned at commit <span className="readout">2e50658</span>. Used through its own classes.</p>
        <ul className="t-small mt-4 space-y-1.5">
          <li>Bitemporal memory, as-of queries</li><li>Trust ranks and a conflict ledger</li><li>Consent grants per source</li><li>Hash-chained audit log</li>
        </ul>
      </div>
    </div>
  );
}

function Arrow({ label, color, reverse }: { label: string; color: string; reverse?: boolean }) {
  return (
    <div className="flex items-center justify-center lg:flex-col" aria-hidden>
      <svg width="64" height="24" viewBox="0 0 64 24" className="rotate-90 lg:rotate-0">
        <path d={reverse ? 'M62 12 H6 M14 5 L6 12 L14 19' : 'M2 12 H58 M50 5 L58 12 L50 19'} stroke={color} strokeWidth="1.5" fill="none" />
      </svg>
      <span className="readout ml-2 text-[0.7rem] text-muted lg:ml-0 lg:mt-1">{label}</span>
    </div>
  );
}
