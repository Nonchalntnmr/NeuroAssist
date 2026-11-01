'use client';
import { useMemo, useState } from 'react';
import { SCENARIOS, scenario } from '@/lib/demo';
import { runCollective, type RunResponse } from '@/lib/api';
import type { SessionRecord } from '@/lib/contract';
import { Lanes } from '@/components/Lanes';
import { Container, DataLabel, Decision, Notice, Num } from '@/components/ui';

export default function SessionsPage() {
  const [key, setKey] = useState('conflict');
  const { c } = useMemo(() => scenario(key), [key]);
  const rows = [...c.history, c.target];
  const [imp, setImp] = useState<{ name: string; run?: RunResponse; error?: string; busy?: boolean } | null>(null);

  async function onFile(f: File) {
    setImp({ name: f.name, busy: true });
    try {
      if (f.size > 1_900_000) throw new Error('The file is larger than 1.9 MB.');
      const j = JSON.parse(await f.text());
      const target: SessionRecord | undefined = j.target ?? (j.schema === 'naci.session/1' ? j : undefined);
      const history: SessionRecord[] = j.history ?? [];
      if (!target) throw new Error('Expected a naci.session/1 record, or an object with "target" and "history".');
      const run = await runCollective(target, history);
      setImp({ name: f.name, run });
    } catch (e) {
      setImp({ name: f.name, error: e instanceof Error ? e.message : String(e) });
    }
  }
  function downloadSample() {
    const blob = new Blob([JSON.stringify({ target: c.target, history: c.history }, null, 1)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob); a.download = `${c.subject_id}.naci.json`; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  return (
    <Container className="pb-10 pt-10 sm:pt-14">
      <h1 className="t-h1">Sessions</h1>
      <p className="t-lede mt-3 max-w-[62ch]">Every recording for a subject, with where it came from and how it fared at NeuroAssist’s gate.</p>
      <div className="mt-6 flex flex-wrap items-center gap-3">
        <label htmlFor="subj" className="text-sm text-muted">Subject</label>
        <select id="subj" value={key} onChange={(e) => setKey(e.target.value)} className="rounded-md border border-rule2 bg-panel px-2 py-1.5 text-sm">
          {SCENARIOS.map((s) => <option key={s.key} value={s.key}>{s.title}</option>)}
        </select>
        <span className="readout text-sm text-muted">{c.subject_id}</span>
      </div>
      <div className="mt-6 overflow-x-auto rounded-xl border border-rule">
        <table className="tbl min-w-[880px]">
          <thead><tr><th>Recorded</th><th>Session</th><th>Source</th><th>Engine</th><th className="num">SPV, deg/s</th><th className="num">95% interval</th><th className="num">Valid frames</th><th className="num">Noise</th><th>Gate</th></tr></thead>
          <tbody>
            {rows.map((r) => {
              const isT = r.session_id === c.target.session_id;
              const failed = r.quality.checks.filter((k) => !k.ok).map((k) => k.label.toLowerCase());
              return (
                <tr key={r.session_id} className={isT ? 'hl' : ''}>
                  <td className="readout text-[0.85rem]">{r.recorded_at.slice(0, 10)}</td>
                  <td className="readout text-[0.8rem]">{r.session_id.split('-').slice(-1)[0]}{isT && <span className="ml-2 font-sans text-signal">latest</span>}</td>
                  <td><DataLabel label={r.provenance.label} /></td>
                  <td className="readout text-[0.8rem] text-muted">{r.provenance.engine}</td>
                  <td className="num">{r.measurement.value !== null ? <Num v={r.measurement.value} /> : <span className="text-faint">—</span>}</td>
                  <td className="num text-muted">{r.measurement.ci_low !== null ? `${r.measurement.ci_low.toFixed(2)} to ${r.measurement.ci_high!.toFixed(2)}` : '—'}</td>
                  <td className="num">{(r.quality.valid_frac * 100).toFixed(0)}%</td>
                  <td className="num">{r.quality.noise_deg?.toFixed(2) ?? '—'}°</td>
                  <td>{failed.length ? <span className="text-veto">abstained: {failed.join(', ')}</span> : <span className="text-ok">passed</span>}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <section className="mt-14 grid gap-8 lg:grid-cols-[minmax(0,380px)_1fr]">
        <div>
          <h2 className="t-h2">Import a session</h2>
          <p className="t-body mt-3">
            Analyse your own exported data: a <code className="code">naci.session/1</code> record with its trace, or an object with <code className="code">target</code> and <code className="code">history</code>.
            The file is sent to the collective, analysed, and not stored.
          </p>
          <p className="t-small mt-3">Records you import keep the label they carry. A record labelled REAL that did not come from a NeuroAssist camera session is mislabelled; the collective cannot detect that.</p>
          <div className="mt-5 flex flex-wrap gap-3">
            <label className="btn btn-primary cursor-pointer">
              Choose a JSON file
              <input type="file" accept="application/json,.json" className="sr-only" onChange={(e) => e.target.files?.[0] && void onFile(e.target.files[0])} />
            </label>
            <button className="btn btn-ghost" onClick={downloadSample}>Download this subject as a sample</button>
          </div>
        </div>
        <div className="min-w-0 space-y-4" aria-live="polite">
          {!imp && <Notice>No file imported yet. Download the sample, change it, and import it to see how the collective responds.</Notice>}
          {imp?.busy && <Notice>Analysing {imp.name}…</Notice>}
          {imp?.error && <Notice tone="error">{imp.name}: {imp.error}</Notice>}
          {imp?.run && (
            <>
              <div className="flex flex-wrap items-center gap-3">
                <Decision d={imp.run.collective.decision} size="lg" />
                {imp.run.labels.map((l) => <DataLabel key={l} label={l} />)}
                <span className="t-small">{imp.name}, {imp.run.server_ms.toFixed(0)} ms</span>
              </div>
              <Lanes messages={imp.run.collective.messages} />
            </>
          )}
        </div>
      </section>
    </Container>
  );
}
