'use client';
import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';
import { scenario } from '@/lib/demo';
import { useRun, type Msg } from '@/lib/api';
import { BaselineChart, TraceChart } from '@/components/Charts';
import { Lanes } from '@/components/Lanes';
import { Container, DataLabel, Decision, Notice, Num } from '@/components/ui';
import { RESULTS, pct } from '@/lib/results';

const ACTS = ['The problem', 'The investigation', 'The challenge', 'The revision', 'The result', 'The proof'];

export default function DemoPage() {
  const { c } = useMemo(() => scenario('artifact'), []);
  const { data, error, loading, rerun } = useRun(c.target, c.history);
  const [act, setAct] = useState(0);
  const col = data?.collective;
  const msgs = col?.messages ?? [];
  const roundOf = (pred: (m: Msg) => boolean) => msgs.find(pred)?.round ?? 0;
  const rCf = roundOf((m) => m.kind === 'EVIDENCE' && m.topic === 'counterfactual');
  const rRev = roundOf((m) => m.kind === 'REVISION');
  const upTo = [-1, 0, rCf, rRev, 99, 99][act];
  const base = col?.evidence.find((e) => e.type === 'baseline')?.content;
  const cf = msgs.find((m) => m.kind === 'EVIDENCE' && m.topic === 'counterfactual');
  const verdict = msgs.find((m) => m.kind === 'VERDICT');
  const v = c.target.measurement.value;

  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement)?.tagName === 'INPUT') return;
      if (e.key === 'ArrowRight') setAct((a) => Math.min(5, a + 1));
      if (e.key === 'ArrowLeft') setAct((a) => Math.max(0, a - 1));
    };
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, []);

  return (
    <Container className="pb-10 pt-10 sm:pt-14">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="t-h1">Guided demo</h1>
          <p className="t-lede mt-3 max-w-[60ch]">One new session for one subject. Six steps, about ninety seconds. Use the arrow keys or the buttons.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <DataLabel label="SYNTHETIC" />
          {data && <span className="text-muted">Computed live on the server in <span className="readout text-fg">{data.server_ms.toFixed(0)} ms</span>; shown step by step.</span>}
          {loading && <span className="text-muted" role="status">Running the collective…</span>}
        </div>
      </div>

      <ol className="mt-8 grid grid-cols-3 gap-1 sm:grid-cols-6" aria-label="Steps">
        {ACTS.map((a, i) => (
          <li key={a}>
            <button onClick={() => setAct(i)} aria-current={i === act ? 'step' : undefined}
              className={`w-full border-t-2 pt-2 text-left text-sm transition-colors ${i <= act ? 'border-signal text-fg' : 'border-rule2 text-muted hover:text-fg'}`}>
              <span className="readout mr-1.5 text-faint">{i + 1}</span>{a}
            </button>
          </li>
        ))}
      </ol>

      {error && (
        <div className="mt-8 space-y-3">
          <Notice tone="error">{error}</Notice>
          <button className="btn btn-ghost" onClick={() => void rerun()}>Run again</button>
        </div>
      )}

      <div className="mt-10 grid gap-10 lg:grid-cols-[minmax(0,380px)_1fr]">
        <div className="space-y-4" aria-live="polite">
          {act === 0 && (<>
            <h2 className="t-h2">A new session looks like a change</h2>
            <p className="t-body">
              This subject has a stable nystagmus, measured six times. The new session reads <Num v={v} unit="deg/s" />.
              Every one of NeuroAssist’s six quality checks passed.
            </p>
            <ul className="space-y-1 text-sm">
              {c.target.quality.checks.map((k) => (
                <li key={k.id} className="flex justify-between gap-4 border-b border-rule py-1.5">
                  <span>{k.label}</span><span className="readout text-muted">{k.show} <span className={k.ok ? 'text-ok' : 'text-veto'}>{k.ok ? 'pass' : 'fail'}</span></span>
                </li>
              ))}
            </ul>
            {data?.compare && <p className="t-body">Compared with the last visit, the shipped pipeline says: <Decision d={data.compare.deterministic.decision} />.</p>}
          </>)}
          {act === 1 && (<>
            <h2 className="t-h2">Three agents look, each at what only it may see</h2>
            <p className="t-body">Signal quality recomputes the number from raw frames. Memory asks CI for the baseline as it stood before this session. The skeptic reads only the head channel.</p>
            {base && <p className="t-body">CI’s baseline: <Num v={base.median} unit="deg/s" /> from {base.n} trusted sessions, spread <Num v={base.spread} sign={false} />.</p>}
          </>)}
          {act === 2 && (<>
            <h2 className="t-h2">The skeptic names another explanation</h2>
            <p className="t-body">The head moved, by under two degrees and below NeuroAssist’s head gate. Gaze estimated from the iris shifts with the head. The skeptic asks signal quality to re-estimate with head yaw removed.</p>
            {cf && <p className="t-body">Head-corrected estimate: <Num v={cf.body.est} unit="deg/s" />, against <Num v={v} unit="deg/s" /> reported.</p>}
          </>)}
          {act === 3 && (<>
            <h2 className="t-h2">The claim does not survive</h2>
            <p className="t-body">The skeptic vetoes the measurement and challenges the claim built on it. The physiology agent withdraws its claim. No agent overruled another: the evidence did.</p>
          </>)}
          {act === 4 && (<>
            <h2 className="t-h2">An abstention, with reasons</h2>
            {col && <div><Decision d={col.decision} size="lg" /></div>}
            {verdict && <p className="t-body">{verdict.text}</p>}
            {data?.compare && (
              <table className="tbl mt-2">
                <tbody>
                  <tr><td>NeuroAssist + last visit</td><td><Decision d={data.compare.deterministic.decision} /></td></tr>
                  <tr><td>Single agent, all inputs</td><td><Decision d={data.compare.single_agent.decision} /></td></tr>
                  <tr className="hl"><td>The collective</td><td>{col && <Decision d={col.decision} />}</td></tr>
                  <tr><td className="text-muted">What the generator did</td><td className="text-muted">Head-coupled tracking slip; the eye did not change</td></tr>
                </tbody>
              </table>
            )}
            <Link className="text-signal underline" href="/evidence">Inspect the evidence and verify its hashes</Link>
          </>)}
          {act === 5 && (<>
            <h2 className="t-h2">One case is a story. Here are {RESULTS.n_cases}.</h2>
            <p className="t-body">Held-out synthetic cases, nine situations, thresholds frozen before the run.</p>
            <table className="tbl">
              <thead><tr><th>System</th><th className="num">Correct</th><th className="num">Unsupported</th></tr></thead>
              <tbody>
                {(['deterministic', 'single_agent', 'collective_ci'] as const).map((k) => (
                  <tr key={k} className={k === 'collective_ci' ? 'hl' : ''}><td>{RESULTS.systems[k].label}</td><td className="num">{pct(RESULTS.systems[k].accuracy)}</td><td className="num">{pct(RESULTS.systems[k].unsupported_conclusion_rate)}</td></tr>
                ))}
              </tbody>
            </table>
            <p className="t-small">The same checks in one program score the same accuracy. The collective keeps its error rate when one agent fails; the program does not. <Link href="/benchmark" className="underline">See the fault results</Link>.</p>
            <Link href="/collective" className="btn btn-ghost">Try other cases, or break an agent</Link>
          </>)}
          <div className="flex gap-2 pt-4">
            <button className="btn btn-ghost" onClick={() => setAct(Math.max(0, act - 1))} disabled={act === 0}>Back</button>
            <button className="btn btn-primary" onClick={() => setAct(Math.min(5, act + 1))} disabled={act === 5}>Next step</button>
          </div>
        </div>

        <div className="min-w-0 space-y-6">
          {(act === 0 || act === 1) && (
            <div className="rounded-xl border border-rule bg-panel p-4">
              <p className="mb-3 text-sm font-medium">Slow-phase velocity by session, deg/s</p>
              <BaselineChart history={c.history} target={c.target} baseline={act >= 1 ? base : null} />
            </div>
          )}
          {(act === 1 || act === 2) && (
            <div className="rounded-xl border border-rule bg-panel p-4">
              <p className="mb-3 text-sm font-medium">The new session’s raw trace</p>
              <TraceChart trace={c.target.trace!} />
            </div>
          )}
          {act >= 1 && act <= 4 && col && (
            <Lanes messages={msgs} upTo={upTo} highlight={(m) => (act === 2 && (m.topic === 'counterfactual')) || (act === 3 && ['VETO', 'CHALLENGE', 'REVISION'].includes(m.kind))} />
          )}
          {act === 5 && (
            <div className="rounded-xl border border-rule bg-panel p-5">
              <p className="text-sm font-medium">Tracking artifacts that pass NeuroAssist’s own gate</p>
              <p className="t-small mt-1">Held-out cases of type tracking artifact (n = {RESULTS.per_type.collective_ci.tracking_artifact!.n}), share decided correctly.</p>
              <div className="mt-5 space-y-3">
                {(['deterministic', 'single_agent', 'collective_ci'] as const).map((k) => {
                  const a = RESULTS.per_type[k].tracking_artifact!.accuracy;
                  return (
                    <div key={k}>
                      <div className="flex justify-between text-sm"><span>{RESULTS.systems[k].label}</span><span className="readout">{pct(a, 0)}</span></div>
                      <div className="mt-1 h-2 rounded-full bg-rule"><div className="h-2 rounded-full" style={{ width: `${a * 100}%`, background: k === 'collective_ci' ? '#3ED6C5' : '#5A6976' }} /></div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>
      </div>
    </Container>
  );
}
