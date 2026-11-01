# NeuroAssist × CI — Submission Summary (ScienceClaw 2026)

**Question.** Can a decentralized collective of specialised agents improve the reliability and
interpretability of noisy smartphone eye-movement measurements compared with a single-agent baseline?

**What we built.**
- An iPhone instrument (ARKit TrueDepth, 60 Hz) with live quality gates, 5-dot calibration, a 10 s
  optokinetic stripes test, 11-gate analysis and explicit abstention.
- A consented bridge (`naci.ingest/1`) that sends only per-frame angles to a NeuroAssist × CI server.
- A five-agent collective (Signal Quality, Contextual Memory via CI, Physiology, Skeptic, Auditor) with
  restricted information access, typed messages, vetoes and a hash-chained audit, whose full deliberation
  is shown on the phone.
- A preregistered-threshold benchmark against deterministic and single-agent baselines.

**Result (synthetic, preliminary, n = 270).** Unsupported conclusions: single agent 8.1% (5.4–12.0) →
collective + CI 1.1% (0.4–3.2); paired McNemar p = 2.1 × 10⁻⁵; harmful artifacts caught 81% → 100%.
The same checks in a single function match the collective's accuracy; the agent organisation's measured
contribution is fault isolation (one corrupted component → abstention, not confident error).

**Honest limits.** All agents are deterministic algorithms (no LLMs). Validation is synthetic. Live
TrueDepth capture after today's fixes has not been re-tested on a physical device. Not a medical device.

**Reusable capability (collaboration bonus).** `neuroassist-ci/evidence_auditor/`: a stdlib-only,
domain-neutral Scientific Evidence Auditor with a JSON schema, two example payloads (an eye-tracking
session and a protein assay), tests, and an HTTP endpoint (`POST /api/py/v1/auditor/audit`). It returns
REPORT / REMEASURE / ABSTAIN with reasons for any sensor or assay observation.

## Slide outline

1. **Scientific problem** — phone sensors make neurological measurement accessible but noisy; the risk is
   confident conclusions from artifacts. Question as above.
2. **Architecture** — iPhone → `naci.ingest/1` → five agents + CI memory → verdict + transcript back to the
   phone (diagram in `ARCHITECTURE.md`). Privacy: numbers only, consent, stateless server.
3. **Live demonstration** — Ready Check, calibration, stripes, result, collective review (demo mode
   clearly labelled as fallback).
4. **Decentralized collective** — who sees what, who can veto, a real transcript (NO_BASELINE → NO_CHANGE
   as history accumulates; a head-motion artifact vetoed).
5. **Benchmark** — headline table with Wilson CIs, McNemar, fault-isolation table, ablation caveat.
6. **Impact and limitations** — what's shown, what isn't (no people, no LLMs, engine blind spot < 2.6 deg/s),
   next steps: physical-device repeatability study, preregistered LLM-agent comparison.

## Where things are

| | location |
|---|---|
| iOS app | this repo (`MyApp/`, tests in `NeuroAssistTests/`) |
| Collective, CI adapter, benchmark, auditor | `~/projects/contextual-intelligence/neuroassist-ci/` |
| Benchmark statistics (reproducible) | `docs/benchmark/stats.py` → `docs/benchmark/benchmark_stats.json` |
| Docs | `README.md`, `ARCHITECTURE.md`, `SCIENTIFIC_VALIDATION.md`, `BENCHMARK_RESULTS.md`, `DEMO_SCRIPT.md` |
