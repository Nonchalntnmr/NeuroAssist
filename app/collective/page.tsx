'use client';
import { useMemo, useState } from 'react';
import { SCENARIOS, scenario } from '@/lib/demo';
import { AGENTS, useRun } from '@/lib/api';
import { Lanes } from '@/components/Lanes';
import { Container, DataLabel, Decision, Notice } from '@/components/ui';

const INPUTS = [
  ['trace.gaze', 'Gaze trace'], ['trace.head', 'Head yaw'], ['trace.time', 'Frame times'], ['device_record', 'Device record'], ['ci_memory', 'CI memory'],
] as const;
const ACCESS: Record<string, string[]> = {
  signal_quality: ['trace.time', 'trace.gaze', 'trace.head', 'device_record'],
  contextual_memory: ['ci_memory'],
  physiology: ['device_record'],
  skeptic: ['trace.time', 'trace.head', 'device_record'],
  auditor: ['device_record'],
};
const AUTHORITY: Record<string, string> = {
  signal_quality: 'Veto the measurement. Answer re-analysis requests.',
  contextual_memory: 'Sole reader and writer of CI. Explain conflicts.',
  physiology: 'The only agent that makes claims. Withdraw them.',
  skeptic: 'Request counterfactuals. Challenge claims. Veto the measurement.',
  auditor: 'Certify, or refuse to certify, each claim.',
};
const FAULT_TEXT: Record<string, string> = {
  '': 'Working', silent: 'Silent (never acts)', byzantine: 'Faulty (acts wrongly)',
};

export default function CollectivePage() {
  const [key, setKey] = useState('artifact');
  const [faults, setFaults] = useState<Record<string, string>>({});
  const [variant, setVariant] = useState('ci');
  const { meta, c } = useMemo(() => scenario(key), [key]);
  const active = Object.fromEntries(Object.entries(faults).filter(([, v]) => v));
  const { data, error, loading, rerun } = useRun(c.target, c.history, { faults: active, variant });
  const col = data?.collective;

  return (
    <>
      <Container className="pb-6 pt-14 sm:pt-20">
        <h1 className="t-h1 max-w-[20ch]">Five agents, no planner</h1>
        <p className="t-lede mt-5 max-w-[64ch]">
          Each round, every agent reads what was posted before and decides for itself whether to act. A conclusion is reported only if no agent with veto
          authority blocks it. Pick a case, switch an agent off or make it lie, and run the collective again. Every run is computed live.
        </p>
      </Container>

      <Container className="grid gap-8 pb-10 lg:grid-cols-[minmax(0,340px)_1fr]">
        <aside className="space-y-8">
          <fieldset>
            <legend className="t-h3 mb-3">Case</legend>
            <div className="space-y-1.5">
              {SCENARIOS.map((s) => (
                <label key={s.key} className={`block cursor-pointer rounded-lg border px-3 py-2.5 ${key === s.key ? 'border-signal/60 bg-signal/[0.05]' : 'border-rule hover:border-rule2'}`}>
                  <input type="radio" name="case" className="sr-only" checked={key === s.key} onChange={() => setKey(s.key)} />
                  <span className="block text-[0.95rem] font-medium">{s.title}</span>
                  <span className="t-small block">{s.blurb}</span>
                </label>
              ))}
            </div>
          </fieldset>
          <fieldset>
            <legend className="t-h3 mb-3">Break an agent</legend>
            <div className="space-y-2">
              {AGENTS.map((a) => (
                <label key={a.key} className="flex items-center justify-between gap-3 text-sm">
                  <span className="flex items-center gap-2"><span className="h-2.5 w-2.5 rounded-sm" style={{ background: a.color }} aria-hidden />{a.short}</span>
                  <select value={faults[a.key] ?? ''} onChange={(e) => setFaults({ ...faults, [a.key]: e.target.value })}
                    className="rounded-md border border-rule2 bg-panel px-2 py-1 text-sm">
                    {Object.entries(FAULT_TEXT).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                  </select>
                </label>
              ))}
            </div>
          </fieldset>
          <fieldset>
            <legend className="t-h3 mb-3">Memory</legend>
            <select value={variant} onChange={(e) => setVariant(e.target.value)} className="w-full rounded-md border border-rule2 bg-panel px-2 py-2 text-sm">
              <option value="ci">Through CI (trust, as-of, conflicts)</option>
              <option value="naive">Raw history list, no CI</option>
              <option value="none">No history at all</option>
            </select>
          </fieldset>
        </aside>

        <div className="min-w-0 space-y-5">
          <div className="flex flex-wrap items-center gap-3">
            <h2 className="t-h2 mr-2">{meta.title}</h2>
            <DataLabel label="SYNTHETIC" />
            {c.history.some((h) => h.provenance.label === 'PRERECORDED') && <DataLabel label="PRERECORDED" note="in history" />}
          </div>
          {error && <><Notice tone="error">{error}</Notice><button className="btn btn-ghost" onClick={() => void rerun()}>Run again</button></>}
          <div className="flex flex-wrap items-center gap-x-6 gap-y-3 rounded-xl border border-rule bg-panel px-5 py-4" aria-live="polite">
            <div><p className="t-small">Collective</p>{col ? <Decision d={col.decision} size="lg" /> : <span className="text-muted">{loading ? 'Running…' : '—'}</span>}</div>
            {data?.compare && <>
              <div><p className="t-small">Single agent</p><Decision d={data.compare.single_agent.decision} /></div>
              <div><p className="t-small">NeuroAssist + last visit</p><Decision d={data.compare.deterministic.decision} /></div>
            </>}
            <div><p className="t-small">Generator truth</p><Decision d={c.truth.decision} /></div>
            {data && <p className="t-small ml-auto">{col!.messages.length} messages, {col!.rounds} rounds, <span className="readout">{data.server_ms.toFixed(0)} ms</span> on the server</p>}
          </div>
          {col && <Lanes messages={col.messages} highlight={(m) => ['VETO', 'CHALLENGE'].includes(m.kind)} />}
        </div>
      </Container>

      <section className="border-t border-rule">
        <Container className="py-14">
          <h2 className="t-h2">Who may see what</h2>
          <p className="t-body mt-3 max-w-prose">The board enforces this table. An agent that asks for an input it was not granted gets an access error, and a test checks it.</p>
          <div className="mt-6 overflow-x-auto">
            <table className="tbl min-w-[860px]">
              <thead><tr><th>Agent</th>{INPUTS.map(([, l]) => <th key={l} className="text-center">{l}</th>)}<th>Authority</th></tr></thead>
              <tbody>
                {AGENTS.map((a) => (
                  <tr key={a.key}>
                    <td><span className="mr-2 inline-block h-2.5 w-2.5 rounded-sm align-middle" style={{ background: a.color }} aria-hidden />{a.short}</td>
                    {INPUTS.map(([k]) => <td key={k} className="text-center">{ACCESS[a.key]!.includes(k) ? <span aria-label="yes">●</span> : <span className="text-faint" aria-label="no">·</span>}</td>)}
                    <td className="text-muted">{AUTHORITY[a.key]}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="t-small mt-4 max-w-prose">Every agent also reads the shared board: posted findings, claims and the evidence they cite. Messages use <code className="code">naci.agent-message/1</code>, which maps onto CI’s own <code className="code">ci.agent-message/1</code>.</p>
        </Container>
      </section>
    </>
  );
}
