import type { Metadata } from 'next';
import { Container, PageHead } from '@/components/ui';
import { RESULTS, SYS_ORDER, TYPE_LABEL, pct } from '@/lib/results';
import { REPO_URL } from '@/lib/site';

export const metadata: Metadata = { title: 'Benchmark' };

const AGENT = { signal_quality: 'Signal quality', contextual_memory: 'Memory (CI)', physiology: 'Physiology', skeptic: 'Skeptic', auditor: 'Auditor' } as const;

export default function Benchmark() {
  const S = RESULTS.systems;
  const types = Object.keys(RESULTS.per_type.collective_ci);
  const metric = (k: keyof (typeof S)['collective_ci'], f: (v: any) => string = (v) => pct(v)) => SYS_ORDER.map((s) => f(S[s][k]));
  return (
    <>
      <PageHead title="Single agent versus collective" lede={<>
        {RESULTS.n_cases} held-out synthetic cases, run once after thresholds were frozen in git. Same inputs for every system. No system uses a language model, so every
        result below is reproducible to the decision.
      </>} />
      <Container className="space-y-16 pb-10">
        <div>
          <div className="overflow-x-auto rounded-xl border border-rule">
            <table className="tbl min-w-[900px]">
              <thead>
                <tr><th>Metric</th>{SYS_ORDER.map((s) => <th key={s} className={`num whitespace-normal ${s === 'collective_ci' ? 'text-signal' : ''}`}>{S[s].label}</th>)}</tr>
              </thead>
              <tbody>
                {[
                  ['Correct decision', metric('accuracy')],
                  ['Unsupported conclusions (of all cases)', metric('unsupported_conclusion_rate')],
                  ['Abstained when it should', metric('appropriate_abstention')],
                  ['Abstained when it should not', metric('over_abstention')],
                  ['Harmful artifacts caught', metric('harmful_artifact_caught')],
                  ['Any artifact flagged', metric('artifact_detection_recall')],
                  ['Clean recordings wrongly flagged', metric('artifact_false_flag_rate')],
                  ['Baseline retrieval (Jaccard)', metric('baseline_retrieval_jaccard', (v) => (v === null ? 'n/a' : v.toFixed(2)))],
                  ['Evidence traceability', metric('evidence_traceability')],
                  ['Median latency per case', metric('latency_ms_median', (v) => `${v} ms`)],
                  ['Language-model tokens', metric('llm_tokens', (v) => String(v))],
                ].map(([name, vals]) => (
                  <tr key={name as string}><td>{name}</td>{(vals as string[]).map((v, i) => <td key={i} className={`num ${SYS_ORDER[i] === 'collective_ci' ? 'bg-signal/[0.05] text-fg' : ''}`}>{v}</td>)}</tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="t-small mt-3 max-w-[90ch]">
            Suite sha256 <span className="readout">{RESULTS.cases_sha256.slice(0, 16)}…</span>. Traceability is zero by construction for systems without an evidence ledger.
            Latency was measured on the build machine, not the deployed server.
          </p>
        </div>

        <div>
          <h2 className="t-h2">By situation</h2>
          <p className="t-body mt-2 max-w-prose">Share decided correctly; the number after the slash counts unsupported conclusions (out of 30).</p>
          <div className="mt-5 overflow-x-auto rounded-xl border border-rule">
            <table className="tbl min-w-[900px]">
              <thead><tr><th>Situation</th>{SYS_ORDER.map((s) => <th key={s} className="num whitespace-normal">{S[s].label}</th>)}</tr></thead>
              <tbody>
                {types.map((t) => (
                  <tr key={t}><td>{TYPE_LABEL[t] ?? t}</td>
                    {SYS_ORDER.map((s) => { const r = RESULTS.per_type[s][t]!; return <td key={s} className={`num ${s === 'collective_ci' ? 'bg-signal/[0.05] text-fg' : ''}`}>{pct(r.accuracy, 0)} <span className="text-faint">/ {r.unsupported}</span></td>; })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="grid gap-10 lg:grid-cols-[minmax(0,380px)_1fr]">
          <div>
            <h2 className="t-h2">Break one component</h2>
            <p className="t-body mt-3">
              The ablation that runs every check in one program matches the collective’s accuracy, so the checks, not the agents, explain accuracy.
              What the organisation adds shows when something fails. Each row corrupts one component in both designs.
            </p>
            <p className="t-small mt-3">Silent: the agent never acts. Faulty: it acts wrongly (accepts everything, returns only the last record, always claims a change, never challenges, certifies everything). A program has no silent mode; a crashed stage stops it.</p>
          </div>
          <div className="min-w-0 overflow-x-auto rounded-xl border border-rule">
            <table className="tbl min-w-[620px]">
              <thead><tr><th>Corrupted component</th><th className="num">Collective, silent</th><th className="num">Collective, faulty</th><th className="num">One program, faulty</th></tr></thead>
              <tbody>
                {(Object.keys(AGENT) as (keyof typeof AGENT)[]).map((a) => {
                  const sil = RESULTS.faults[`${a}:silent`]!, byz = RESULTS.faults[`${a}:byzantine`]!, mono = RESULTS.monolith_faults[`${a}:byzantine`];
                  return (
                    <tr key={a}><td>{AGENT[a]}</td>
                      <td className="num">{pct(sil.unsupported_conclusion_rate)} <span className="text-faint">· {pct(sil.accuracy, 0)}</span></td>
                      <td className="num">{pct(byz.unsupported_conclusion_rate)} <span className="text-faint">· {pct(byz.accuracy, 0)}</span></td>
                      <td className={`num ${mono && mono.unsupported_conclusion_rate > 0.02 ? 'text-veto' : ''}`}>{mono ? <>{pct(mono.unsupported_conclusion_rate)} <span className="text-faint">· {pct(mono.accuracy, 0)}</span></> : <span className="text-faint">no equivalent stage</span>}</td>
                    </tr>
                  );
                })}
                <tr><td className="text-muted">No fault</td><td className="num" colSpan={2}>{pct(S.collective_ci.unsupported_conclusion_rate)} <span className="text-faint">· {pct(S.collective_ci.accuracy, 0)}</span></td><td className="num">{pct(S.monolith_ci.unsupported_conclusion_rate)} <span className="text-faint">· {pct(S.monolith_ci.accuracy, 0)}</span></td></tr>
              </tbody>
            </table>
            <p className="t-small px-3 py-2">Each cell: unsupported conclusions · correct decisions. Failing silent usually means abstaining more, which is the safe direction.</p>
          </div>
        </div>

        <div className="grid gap-10 lg:grid-cols-[minmax(0,380px)_1fr]">
          <h2 className="t-h2">Why the collective did not win everywhere</h2>
          <div className="prose-lab">
            <ul>
              <li>Missing frames and batched timestamps: NeuroAssist’s own gate already abstains on every one. All systems tie at 100%.</li>
              <li>Tracking slips that return slowly are also caught by the gate. Only the slips that snap back within one frame, and so look like a fast phase, pass it. Those are where the single agent fails and the collective does not.</li>
              <li>Three held-out cases defeat every system that compares against a baseline: clean or near-baseline sessions whose measurement noise pushes z past 3. These are false changes, and no check here can tell them from real ones.</li>
              <li>Raw history without CI ties CI on most situations. CI’s trust ranks matter only when unverified records are numerous enough to move a median (conflicting history: {pct(RESULTS.per_type.collective_ci.conflicting_history!.accuracy, 0)} with CI, {pct(RESULTS.per_type.collective_naive_history.conflicting_history!.accuracy, 0)} without).</li>
            </ul>
          </div>
        </div>

        <div className="grid gap-10 lg:grid-cols-[minmax(0,380px)_1fr]">
          <h2 className="t-h2">Reproduce it</h2>
          <div className="min-w-0">
            <pre className="readout overflow-x-auto rounded-xl border border-rule bg-panel p-4 text-[0.82rem] leading-relaxed text-fg/90">{`git clone ${REPO_URL}
cd neuroassist-ci && npm ci && pip install -r requirements.txt pytest
npx tsx scripts/gen-cases.ts            # cases from NeuroAssist's simulator
python3 -m pytest -q                    # parity, access control, faults, auditor
python3 -m naci.benchmark --split heldout --faults`}</pre>
            <p className="t-small mt-3">Protocol, deviations and thresholds: <a className="underline" href={`${REPO_URL}/blob/main/docs/BENCHMARK.md`}>docs/BENCHMARK.md</a>.</p>
          </div>
        </div>
      </Container>
    </>
  );
}
