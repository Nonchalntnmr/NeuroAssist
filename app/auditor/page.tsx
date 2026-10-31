'use client';
import { useState } from 'react';
import protein from '@/evidence_auditor/examples/protein_assay.json';
import { Container, Notice } from '@/components/ui';
import { REPO_URL } from '@/lib/site';

const EXAMPLE = JSON.stringify(protein, null, 2);

export default function AuditorPage() {
  const [text, setText] = useState(EXAMPLE);
  const [out, setOut] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function run() {
    setBusy(true); setErr(null); setOut(null);
    try {
      let body: unknown;
      try { body = JSON.parse(text); } catch { throw new Error('The input is not valid JSON.'); }
      const r = await fetch('/api/py/v1/auditor/audit', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      const j = await r.json();
      if (!r.ok) throw new Error(typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail ?? j));
      setOut(j);
    } catch (e) { setErr(e instanceof Error ? e.message : String(e)); } finally { setBusy(false); }
  }

  return (
    <>
      <Container className="pb-8 pt-14 sm:pt-20">
        <h1 className="t-h1 max-w-[20ch]">Scientific Evidence Auditor</h1>
        <p className="t-lede mt-5 max-w-[64ch]">
          A small, domain-neutral check for any scientific pipeline, agentic or not: is every claim you want to report backed by evidence that exists, is intact,
          is of adequate quality and provenance, and has survived every challenge? Free to use. Python standard library only.
        </p>
      </Container>
      <Container className="grid gap-10 pb-10 lg:grid-cols-[minmax(0,420px)_1fr]">
        <div className="prose-lab space-y-6">
          <div>
            <h2 className="t-h3 mb-2">Input</h2>
            <ul>
              <li><code>claims</code>: id, statement, the evidence ids it cites, and the evidence types it <code>requires</code></li>
              <li><code>evidence</code>: id, type, producer, <code>content</code>, its <code>sha256</code>, quality (ok, concern, fail), provenance label</li>
              <li><code>challenges</code>: which claim, by whom, open or resolved</li>
              <li><code>quality</code>: overall measurement status</li>
            </ul>
          </div>
          <div>
            <h2 className="t-h3 mb-2">Output</h2>
            <ul>
              <li>Supported claims, with caveats and labels to disclose</li>
              <li>Unsupported claims, each with its reasons</li>
              <li>Missing evidence, by claim and type</li>
              <li>A recommendation: report, abstain or remeasure</li>
            </ul>
          </div>
          <div>
            <h2 className="t-h3 mb-2">Use it</h2>
            <pre className="readout overflow-x-auto rounded-lg border border-rule bg-panel p-3 text-[0.8rem] text-fg/90">{`# Python: copy evidence_auditor/ into your project
from evidence_auditor import audit, content_hash
report = audit(observation)

# HTTP
curl -X POST https://<this site>/api/py/v1/auditor/audit \\
  -H 'Content-Type: application/json' -d @observation.json`}</pre>
            <p>Hash evidence with <code>content_hash()</code>: SHA-256 of JSON with sorted keys and no spaces. Schema, examples and tests are in <a className="underline" href={`${REPO_URL}/tree/main/evidence_auditor`}>the repository</a>.</p>
            <p>Building something at ScienceClaw? If your agents make claims, try it, and tell us what broke.</p>
          </div>
        </div>
        <div className="min-w-0 space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <label htmlFor="obs" className="text-sm font-medium">Observation (an invented protein-binding example from another domain)</label>
            <button className="text-sm text-muted underline" onClick={() => setText(EXAMPLE)}>Reset example</button>
          </div>
          <textarea id="obs" value={text} onChange={(e) => setText(e.target.value)} spellCheck={false}
            className="readout h-[360px] w-full rounded-xl border border-rule2 bg-panel p-3 text-[0.78rem] leading-relaxed text-fg/90" />
          <button className="btn btn-primary" onClick={() => void run()} disabled={busy}>{busy ? 'Auditing…' : 'Audit this observation'}</button>
          <div aria-live="polite">
            {err && <Notice tone="error">{err}</Notice>}
            {out && (
              <div className="space-y-4 rounded-xl border border-rule bg-panel p-5">
                <p className="t-h3">Recommendation: <span className={out.recommendation === 'REPORT' ? 'text-ok' : 'text-veto'}>{out.recommendation.toLowerCase()}</span></p>
                {out.reasons.length > 0 && <p className="t-small">{out.reasons.join(' ')}</p>}
                {out.supported.map((s: any) => <p key={s.claim_id} className="text-sm"><span className="text-ok">Supported.</span> {s.statement}{s.disclose.length ? <span className="text-challenge"> Disclose: {s.disclose.join(', ').toLowerCase()} evidence.</span> : null}</p>)}
                {out.unsupported.map((s: any) => (
                  <div key={s.claim_id} className="text-sm"><p><span className="text-veto">Unsupported.</span> {s.statement}</p>
                    <ul className="t-small mt-1 list-disc pl-5">{s.reasons.map((r: string) => <li key={r}>{r}</li>)}</ul></div>
                ))}
                <details><summary className="cursor-pointer text-sm text-muted">Raw report</summary>
                  <pre className="readout mt-2 max-h-72 overflow-auto text-[0.75rem]">{JSON.stringify(out, null, 2)}</pre></details>
              </div>
            )}
          </div>
        </div>
      </Container>
    </>
  );
}
