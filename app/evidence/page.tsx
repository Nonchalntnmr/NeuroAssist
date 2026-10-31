'use client';
import Link from 'next/link';
import { Fragment, useEffect, useMemo, useState } from 'react';
import { SCENARIOS, scenario } from '@/lib/demo';
import { agentColor, agentShort, useRun, type Ev } from '@/lib/api';
import { Container, DataLabel, Decision, Notice } from '@/components/ui';

async function sha256(text: string) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
function deepEqual(a: unknown, b: unknown): boolean {
  if (typeof a !== typeof b) return false;
  if (a === null || b === null || typeof a !== 'object') return a === b;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  const ka = Object.keys(a as object), kb = Object.keys(b as object);
  return ka.length === kb.length && ka.every((k) => deepEqual((a as any)[k], (b as any)[k]));
}

export default function EvidencePage() {
  const [key, setKey] = useState('artifact');
  const { meta, c } = useMemo(() => scenario(key), [key]);
  const { data, error, loading } = useRun(c.target, c.history, { canonical: true });
  const col = data?.collective;
  const [checks, setChecks] = useState<Record<string, boolean>>({});
  const [open, setOpen] = useState<string | null>(null);

  useEffect(() => {
    setChecks({});
    if (!col) return;
    (async () => {
      const out: Record<string, boolean> = {};
      for (const e of col.evidence) {
        out[e.id] = !!e.canonical && (await sha256(e.canonical)) === e.sha256 && deepEqual(JSON.parse(e.canonical), e.content);
      }
      setChecks(out);
    })();
  }, [col]);

  const verified = col ? Object.values(checks).filter(Boolean).length : 0;
  const cites = (id: string) => col?.messages.filter((m) => m.refs.includes(id)).map((m) => `${agentShort(m.sender)}: ${m.kind.toLowerCase().replace('_', ' ')}`) ?? [];

  return (
    <Container className="pb-10 pt-14 sm:pt-20">
      <h1 className="t-h1">Evidence and provenance</h1>
      <p className="t-lede mt-5 max-w-[64ch]">
        Every number an agent relies on is an evidence item named by the SHA-256 of its content. Your browser re-hashes each item below. Each item’s
        creation is also an entry on CI’s hash-chained audit log, which the server verifies end to end.
      </p>
      <div className="mt-8 flex flex-wrap items-center gap-3">
        <label className="text-sm text-muted" htmlFor="case">Case</label>
        <select id="case" value={key} onChange={(e) => setKey(e.target.value)} className="rounded-md border border-rule2 bg-panel px-2 py-1.5 text-sm">
          {SCENARIOS.map((s) => <option key={s.key} value={s.key}>{s.title}</option>)}
        </select>
        <DataLabel label="SYNTHETIC" />
        {loading && <span className="t-small" role="status">Running the collective…</span>}
      </div>
      {error && <div className="mt-6"><Notice tone="error">{error}</Notice></div>}
      {col && (
        <>
          <div className="mt-8 grid gap-4 sm:grid-cols-3">
            <Stat label="Decision" value={<Decision d={col.decision} />} />
            <Stat label="Evidence verified in this browser" value={<span className="readout text-xl">{verified} / {col.evidence.length}</span>} />
            <Stat label="CI audit chain" value={<span className={`text-xl font-semibold ${col.audit.chain_ok ? 'text-ok' : 'text-veto'}`}>{col.audit.chain_ok ? `Intact, ${col.audit.entries} entries` : 'Broken'}</span>}
              note={<span className="readout break-all">head {col.audit.head.slice(0, 24)}…</span>} />
          </div>
          <div className="mt-8 overflow-x-auto rounded-xl border border-rule">
            <table className="tbl min-w-[820px]">
              <thead><tr><th>Evidence</th><th>Type</th><th>Produced by</th><th>Quality</th><th>Derived from</th><th>Cited by</th><th className="text-right">Hash check</th></tr></thead>
              <tbody>
                {col.evidence.map((e: Ev) => (
                  <Fragment key={e.id}>
                    <tr className="cursor-pointer hover:bg-raised/60" onClick={() => setOpen(open === e.id ? null : e.id)}>
                      <td><button className="readout text-left text-[0.82rem] underline decoration-rule2" aria-expanded={open === e.id}>{e.id}</button></td>
                      <td>{e.type.replace('_', ' ')}</td>
                      <td><span className="mr-1.5 inline-block h-2 w-2 rounded-sm" style={{ background: agentColor(e.producer) }} aria-hidden />{e.producer === 'neuroassist' ? 'NeuroAssist device' : agentShort(e.producer)}</td>
                      <td className={e.quality === 'fail' ? 'text-veto' : e.quality === 'concern' ? 'text-challenge' : 'text-muted'}>{e.quality}</td>
                      <td className="readout text-[0.78rem] text-muted">{e.derived_from.join(' ') || '—'}</td>
                      <td className="text-sm text-muted">{cites(e.id).join('; ') || '—'}</td>
                      <td className="text-right">{e.id in checks ? (checks[e.id] ? <span className="text-ok">sha256 matches</span> : <span className="text-veto">mismatch</span>) : <span className="text-faint">checking</span>}</td>
                    </tr>
                    {open === e.id && (
                      <tr><td colSpan={7} className="bg-ink">
                        <p className="readout break-all text-[0.75rem] text-muted">sha256 {e.sha256}</p>
                        <pre className="readout mt-2 max-h-80 overflow-auto whitespace-pre-wrap text-[0.78rem] text-fg/90">{JSON.stringify(e.content, null, 2)}</pre>
                      </td></tr>
                    )}
                  </Fragment>
                ))}
              </tbody>
            </table>
          </div>
          <div className="mt-10 grid gap-8 lg:grid-cols-2">
            <div>
              <h2 className="t-h3">Calls into CI during this run</h2>
              <ul className="mt-3 space-y-1.5 text-sm">
                {col.ci_calls.map((k, i) => <li key={i} className="readout text-[0.8rem] text-muted"><span className="text-memory">{k.op}</span> {Object.entries(k).filter(([n]) => n !== 'op').map(([n, v]) => `${n}=${v}`).join(' ')}</li>)}
              </ul>
            </div>
            <div>
              <h2 className="t-h3">Inputs each agent actually read</h2>
              <ul className="mt-3 space-y-1.5 text-sm">
                {Object.entries(col.access_log.reduce<Record<string, Set<string>>>((a, r) => { (a[r.agent] ??= new Set()).add(r.input); return a; }, {})).map(([a, s]) => (
                  <li key={a}><span className="mr-2 inline-block h-2 w-2 rounded-sm" style={{ background: agentColor(a) }} aria-hidden />{agentShort(a)}: <span className="readout text-[0.8rem] text-muted">{[...s].join(', ')}</span></li>
                ))}
              </ul>
            </div>
          </div>
          <p className="t-small mt-10 max-w-prose">
            Case: {meta.title}. Nothing sent to the server is stored; each run builds a fresh in-memory CI store with a per-run encryption key and discards it.
            The certifying logic is the open <Link href="/auditor" className="underline">Evidence Auditor</Link>.
          </p>
        </>
      )}
    </Container>
  );
}

function Stat({ label, value, note }: { label: string; value: React.ReactNode; note?: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-rule bg-panel p-4">
      <p className="t-small">{label}</p>
      <div className="mt-2">{value}</div>
      {note && <p className="t-small mt-2 text-[0.75rem]">{note}</p>}
    </div>
  );
}
