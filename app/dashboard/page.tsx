'use client';
import Link from 'next/link';
import { useMemo, useState } from 'react';
import { SCENARIOS, scenario } from '@/lib/demo';
import { DECISION_TEXT, agentColor, agentShort, useRun } from '@/lib/api';
import { BaselineChart, TraceChart } from '@/components/Charts';
import { Container, DataLabel, Decision, Notice, Num } from '@/components/ui';

export default function Dashboard() {
  const [key, setKey] = useState('change');
  const { meta, c } = useMemo(() => scenario(key), [key]);
  const { data, error, loading, rerun } = useRun(c.target, c.history);
  const col = data?.collective;
  const base = col?.evidence.find((e) => e.type === 'baseline')?.content;
  const q = col?.evidence.find((e) => e.type === 'quality_report')?.content;
  const verdict = col?.messages.find((m) => m.kind === 'VERDICT');
  const m = c.target.measurement;

  return (
    <Container className="pb-10 pt-10 sm:pt-14">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="t-h1">Dashboard</h1>
          <p className="t-lede mt-3">Latest session for one subject, as the collective sees it.</p>
        </div>
        <div className="flex items-center gap-3">
          <label htmlFor="subj" className="text-sm text-muted">Subject</label>
          <select id="subj" value={key} onChange={(e) => setKey(e.target.value)} className="rounded-md border border-rule2 bg-panel px-2 py-1.5 text-sm">
            {SCENARIOS.map((s) => <option key={s.key} value={s.key}>{s.title}</option>)}
          </select>
        </div>
      </div>
      <div className="mt-4 flex flex-wrap items-center gap-2 text-sm text-muted">
        <span className="readout text-fg">{c.subject_id}</span><DataLabel label="SYNTHETIC" />
        <span>{c.history.length} prior records; latest {new Date(c.target.recorded_at).toISOString().slice(0, 10)}</span>
      </div>
      {error && <div className="mt-6 space-y-3"><Notice tone="error">{error}</Notice><button className="btn btn-ghost" onClick={() => void rerun()}>Run again</button></div>}

      <div className="mt-8 grid gap-4 md:grid-cols-4">
        <Tile label="Slow-phase velocity" value={m.value !== null ? <Num v={m.value} unit="deg/s" /> : <span className="text-veto">No value</span>}
          note={m.value !== null ? <>95% interval <Num v={m.ci_low} /> to <Num v={m.ci_high} /></> : 'NeuroAssist’s gate abstained'} />
        <Tile label="Personal baseline (CI)" value={base?.median != null ? <Num v={base.median} unit="deg/s" /> : <span className="text-muted">{loading ? '…' : 'Not enough history'}</span>}
          note={base ? `${base.n} trusted sessions${base.excluded.length ? `, ${base.excluded.length} left out` : ''}` : ''} />
        <Tile label="Signal quality" value={q ? <span className={`text-xl font-semibold ${q.verdict === 'ACCEPT' ? 'text-ok' : q.verdict === 'CONCERN' ? 'text-challenge' : 'text-veto'}`}>{q.verdict === 'ACCEPT' ? 'Accepted' : q.verdict === 'CONCERN' ? 'Concerns' : 'Rejected'}</span> : '…'}
          note={q ? (q.flags.length ? q.flags.map((f: any) => f.code.toLowerCase().replaceAll('_', ' ')).join(', ') : 'all trace checks pass') : ''} />
        <Tile label="Collective decision" value={col ? <Decision d={col.decision} size="lg" /> : <span className="text-muted">{loading ? 'Running…' : '—'}</span>}
          note={col ? DECISION_TEXT[col.decision]?.plain : ''} />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1.2fr_1fr]">
        <div className="rounded-xl border border-rule bg-panel p-4">
          <p className="mb-3 text-sm font-medium">Sessions over time, deg/s</p>
          <BaselineChart history={c.history} target={c.target} baseline={base} />
        </div>
        <div className="rounded-xl border border-rule bg-panel p-4">
          <p className="mb-3 text-sm font-medium">Latest raw trace</p>
          <TraceChart trace={c.target.trace!} height={250} />
        </div>
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1.2fr_1fr]">
        <div className="rounded-xl border border-rule bg-panel p-5">
          <h2 className="t-h3">What each agent concluded</h2>
          <ul className="mt-4 space-y-3">
            {col?.messages.filter((x) => ['FINDING', 'CLAIM', 'VETO', 'VERDICT', 'RESOLVE'].includes(x.kind)).map((x) => (
              <li key={x.id} className="flex gap-3 text-sm">
                <span className="mt-1.5 h-2 w-2 shrink-0 rounded-sm" style={{ background: agentColor(x.sender) }} aria-hidden />
                <span><span className="font-medium">{agentShort(x.sender)}.</span> <span className="text-fg/85">{x.text}</span></span>
              </li>
            ))}
          </ul>
          <div className="mt-5 flex gap-4 text-sm"><Link href="/collective" className="text-signal underline">Full exchange</Link><Link href="/evidence" className="text-signal underline">Evidence</Link></div>
        </div>
        <div className="rounded-xl border border-rule bg-panel p-5">
          <h2 className="t-h3">NeuroAssist gate</h2>
          <table className="tbl mt-3 text-sm">
            <tbody>
              {c.target.quality.checks.map((k) => (
                <tr key={k.id}><td>{k.label}</td><td className="num text-muted">{k.show}</td><td className="text-right"><span className={k.ok ? 'text-ok' : 'text-veto'}>{k.ok ? 'pass' : 'fail'}</span></td></tr>
              ))}
            </tbody>
          </table>
          {verdict && <p className="t-small mt-4">Auditor: {verdict.text}</p>}
          <p className="t-small mt-4">Case: {meta.title}. {c.truth.note}</p>
        </div>
      </div>
    </Container>
  );
}

function Tile({ label, value, note }: { label: string; value: React.ReactNode; note?: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-rule bg-panel p-4">
      <p className="t-small">{label}</p>
      <div className="mt-2 text-xl">{value}</div>
      {note && <p className="t-small mt-2">{note}</p>}
    </div>
  );
}
