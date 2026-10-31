// Smoke test against a running deployment.  node e2e/smoke.mjs https://<host>
// Checks every route, the API (health, a live collective run, the auditor, bad input), security
// headers, that no obvious secret leaks into HTML, and the run's contents.
import { readFileSync } from 'node:fs';

const base = (process.argv[2] || 'http://localhost:3000').replace(/\/$/, '');
const ROUTES = ['/', '/science', '/collective', '/research', '/team', '/dashboard', '/sessions', '/evidence', '/benchmark', '/demo', '/auditor'];
let fail = 0;
const ok = (c, msg) => { console.log(`${c ? 'PASS' : 'FAIL'}  ${msg}`); if (!c) fail++; };

for (const r of ROUTES) {
  const res = await fetch(base + r);
  const html = await res.text();
  ok(res.status === 200, `${r} -> ${res.status}`);
  ok(!/sk-ant-|ANTHROPIC_API_KEY=|DATABASE_URL=|BEGIN (RSA )?PRIVATE KEY/.test(html), `${r} has no secret-looking strings`);
  if (r === '/') ok(res.headers.get('x-content-type-options') === 'nosniff', '/ sends X-Content-Type-Options');
}
const nf = await fetch(base + '/no-such-page');
ok(nf.status === 404, `unknown route -> ${nf.status}`);

const h = await (await fetch(base + '/api/py/health')).json();
ok(h.ok === true && h.ci_importable === true, `API health: CI importable (commit ${String(h.ci_commit).slice(0, 7)}, python ${h.python})`);

const cases = JSON.parse(readFileSync(new URL('../benchmark/cases/dev.json', import.meta.url)));
const c = cases.cases.find((x) => x.case_id === 'dev-tracking_artifact-1');
const t0 = Date.now();
const run = await fetch(base + '/api/py/v1/collective/run', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ target: c.target, history: c.history, canonical: true }) });
const j = await run.json();
ok(run.status === 200 && j.collective?.decision === 'ABSTAIN', `live run on a gate-passing tracking slip -> ${j.collective?.decision} (${Date.now() - t0} ms round trip, ${j.server_ms} ms server)`);
ok(['CHANGE', 'NO_CHANGE'].includes(j.compare?.single_agent?.decision), `single agent on the same case draws an unsupported conclusion -> ${j.compare?.single_agent?.decision}`);
ok(j.collective?.audit?.chain_ok === true, `CI audit chain verifies (${j.collective?.audit?.entries} entries)`);
ok((j.collective?.messages || []).some((m) => m.kind === 'VETO' && m.sender === 'skeptic'), 'skeptic vetoed');
ok((j.collective?.evidence || []).every((e) => typeof e.canonical === 'string'), 'evidence carries canonical bytes for client re-hashing');

const bad = await fetch(base + '/api/py/v1/collective/run', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{"target":{}}' });
ok(bad.status === 422, `invalid record -> ${bad.status}`);

const ex = JSON.parse(readFileSync(new URL('../evidence_auditor/examples/protein_assay.json', import.meta.url)));
const au = await (await fetch(base + '/api/py/v1/auditor/audit', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(ex) })).json();
ok(au.recommendation === ex._expect, `auditor example -> ${au.recommendation}`);

const bm = await (await fetch(base + '/api/py/v1/benchmark')).json();
ok(bm.n_cases === 270 && bm.systems?.collective_ci, `benchmark endpoint (${bm.n_cases} cases)`);

console.log(fail ? `\n${fail} check(s) failed` : '\nAll checks passed');
process.exit(fail ? 1 : 0);
