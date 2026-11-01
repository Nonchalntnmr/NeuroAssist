/** Run NeuroAssist's TypeScript engine on every held-out target trace, exactly as stored (rounded),
 *  and save full-precision outputs. tests/test_neurocore_parity.py checks the Python port against it. */
import { readFileSync, writeFileSync } from 'node:fs';
import { analyze } from '../lib/neuroassist/analyze';

const suite = JSON.parse(readFileSync('benchmark/cases/heldout.json', 'utf8'));
const out = suite.cases.map((c: any) => {
  const tr = c.target.trace;
  const a = analyze(tr.t, tr.x.map((v: number | null) => (v === null ? NaN : v)));
  const num = (v: number) => (Number.isFinite(v) ? v : null);
  return {
    case_id: c.case_id, n: a.n, fps: a.fps, sigma: num(a.sigma), est: num(a.est), residualRms: num(a.residualRms),
    chunks: a.chunks.length, fastPhases: a.fastPhases, pass: a.pass,
    checks: a.checks.map((k) => ({ id: k.id, value: num(k.value), ok: k.ok })),
  };
});
writeFileSync('benchmark/cases/parity-ts.json', JSON.stringify(out));
console.log('parity outputs', out.length);
