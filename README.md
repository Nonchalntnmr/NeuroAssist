# NeuroAssist × CI — The Nervous System Interface

**AI can read language. We're teaching it to investigate neurological signals.**

A decentralized scientific collective for camera-based eye-movement measurement. Five agents, each with
its own evidence access and authority, inspect a new measurement, compare it with the person's history
held in Contextual Intelligence (CI), challenge each other, and return an evidence-backed observation or
an abstention. Built for MIT ScienceClaw 2026.

> Research prototype. It measures eye movement and reasons about measurement quality. It does not
> diagnose stroke, vestibular disorders or any condition, and it is not a medical device. All benchmark
> data is **synthetic** (NeuroAssist's own simulator). Nothing has been tested on people.

## Three products

| | what | how it is used here |
|---|---|---|
| **NeuroAssist** (parent A) | webcam eye-movement measurement with a quality gate (`neurocore-0.4.0`) | its signal engine is vendored unchanged into `lib/neuroassist/` (checksums in `VENDORED.sha256`); a Python port in `naci/neurocore.py` agrees with it **exactly** on all 270 held-out traces (`tests/test_collective.py`) |
| **Contextual Intelligence** (parent B) | user-owned memory: bitemporal, trust-ranked, consent-gated, hash-chained audit | installed from its public repository at commit `2e50658` (`requirements.txt`) and used through its own classes: `TemporalMemory`, `ConsentLedger`, `AuditLog`, `Store` (`naci/memory.py`) |
| **NeuroAssist × CI** (child, this repo) | the collective, the benchmark, the website, the Evidence Auditor | independently deployable; neither parent is modified |

Integration boundary: `naci.session/1` (`lib/contract.ts`, `naci/contract.py`). Agent messages:
`naci.agent-message/1`, which maps onto CI's `ci.agent-message/1`. Details: `docs/ARCHITECTURE.md`.

## Results (held-out, 270 synthetic cases, thresholds frozen in commit `dbb7baa` before the run)

| system | correct | unsupported conclusions | harmful artifacts caught |
|---|---|---|---|
| NeuroAssist gate + previous visit | 58.5% | 41.5% | 81.3% |
| Single agent, one pass, full history | 91.9% | 8.1% | 81.3% |
| Collective, raw history (no CI) | 98.1% | 1.9% | 100% |
| **Collective + CI** | **98.9%** | **1.1%** | **100%** |
| Ablation: same checks in one function + CI | 98.9% | 1.1% | 100% |

What this does and does not show:

- The accuracy gain comes from the **checks** (independent recomputation from raw frames, a
  head-motion counterfactual, trust-aware baselines), not from organising them as agents: the
  single-function ablation matches it.
- What the organisation adds is **fault isolation**. Corrupt one component: the single function's
  unsupported-conclusion rate rises to 33.7% (memory), 32.6% (analysis) or 7.4% (robustness test);
  the collective stays at or below 1.1% for every agent, silent or faulty.
- CI beats raw history only on conflicting history (97% vs 90%), where unverified records are numerous
  enough to move a median.
- **Finding about NeuroAssist itself:** between 0.2 and 0.6 deg/s its gate passes 80–100% of
  recordings while the 95% interval contains the true value only 5–38% of the time
  (`docs/ENGINE_BLINDSPOT.md`). The benchmark stays above 2.6 deg/s.

Protocol, metrics and every deviation: `docs/BENCHMARK.md`. Results: `benchmark/results/heldout.json`.

## Run it

```bash
npm ci
pip install -r requirements.txt pytest uvicorn
python3 -m uvicorn api.index:app --port 8000 &   # the collective (Python, FastAPI)
npm run dev                                       # the site, http://localhost:3000 (proxies /api/py to :8000)
```

Tests and benchmark:

```bash
python3 -m pytest -q                                 # 29 tests: parity, access control, faults, CI, auditor
npx vitest run                                       # vendored engine checksums, scenarios
npx tsx scripts/gen-cases.ts                         # regenerate cases (deterministic)
python3 -m naci.benchmark --split heldout --faults   # ~45 s
node e2e/smoke.mjs https://<deployment>              # smoke test a deployment
```

## Layout

```
lib/neuroassist/     NeuroAssist engine, vendored unchanged
lib/scenarios.ts     synthetic case generator (NeuroAssist simulator + corruptions + ground truth)
naci/                the collective: contract, CI memory adapter, agents, baselines, benchmark
evidence_auditor/    reusable, domain-neutral Scientific Evidence Auditor (stdlib only)
api/index.py         HTTP API (Vercel Python function)
app/, components/    Next.js site and dashboard
benchmark/           cases, results, freeze hashes
docs/                architecture, benchmark protocol, engine blind spot, deployment
```

## Reuse the Evidence Auditor

`evidence_auditor/` checks that every claim a pipeline wants to report cites evidence that exists, is
intact (sha256), is of adequate quality and allowed provenance, and has survived every challenge. Copy
the folder or call `POST /api/py/v1/auditor/audit`. See `evidence_auditor/README.md`.

## Team

Nishanth Revuri and Jayashabari Shankar.
