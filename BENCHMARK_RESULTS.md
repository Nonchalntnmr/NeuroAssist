# Benchmark Results — NeuroAssist × CI

**Status: preliminary, synthetic data only.** No human participants, no clinical labels, no language models.

## Question

Does a collective of specialised agents, with CI memory, reach better-supported conclusions about a
noisy eye-movement measurement than simpler systems given the same input?

## Method

- **Data:** 270 held-out synthetic cases (9 case types × 30) produced by NeuroAssist's own simulator
  plus injected corruptions, with known ground truth. Thresholds were frozen before the run
  (`neuroassist-ci/benchmark/FREEZE.sha256`). Protocol: `neuroassist-ci/docs/BENCHMARK.md`.
- **Systems, all on identical inputs:**
  | system | what it is |
  |---|---|
  | Deterministic (gate + previous visit) | device quality gate, compare to the last visit only |
  | Single agent, one pass | one deterministic analyst: reads the device verdict and full history in one pass, z-score vs all prior sessions; no independent trace inspection, no challenge, no memory trust semantics (`naci/baselines.py`). **Not an LLM.** |
  | Collective, raw history | 5 agents, history passed as a plain list |
  | **Collective + CI** | 5 agents; only the memory agent can read CI (trust-ranked, bitemporal) |
  | Ablation | the collective's checks in one function, with CI |
- **Statistics:** 95% Wilson intervals; exact two-sided McNemar on paired cases. Reproduce with
  `python3 docs/benchmark/stats.py` → `docs/benchmark/benchmark_stats.json` (machine-readable).
- "Unsupported conclusion" = the system reported CHANGE/NO_CHANGE when ground truth required abstention
  or the opposite conclusion.

## Headline (n = 270 each)

| system | correct | unsupported conclusions | harmful artifacts caught (n = 91) |
|---|---|---|---|
| Deterministic | 158 (58.5%, 52.6–64.2) | 112 (41.5%, 35.8–47.4) | 74 (81.3%, 72.1–88.0) |
| Single agent | 248 (91.9%, 88.0–94.6) | 22 (8.1%, 5.4–12.0) | 74 (81.3%, 72.1–88.0) |
| Collective, raw history | 265 (98.1%, 95.7–99.2) | 5 (1.9%, 0.8–4.3) | 91 (100%, 96.0–100) |
| **Collective + CI** | **267 (98.9%, 96.8–99.6)** | **3 (1.1%, 0.4–3.2)** | **91 (100%, 96.0–100)** |
| Ablation (one function + CI) | 267 (98.9%, 96.8–99.6) | 3 (1.1%, 0.4–3.2) | 91 (100%, 96.0–100) |

Abstention when abstention was correct: collective systems 123/123; single agent 106/123.
False-flag rate on clean cases: 2/150 for every system.

## Paired comparisons (exact McNemar, Collective + CI vs …)

| vs | only collective right | only other right | p |
|---|---|---|---|
| Single agent | 20 | 1 | 2.1 × 10⁻⁵ |
| Collective, raw history | 3 | 1 | 0.625 (not significant) |
| Ablation | 0 | 0 | 1.0 (identical on all 270) |

17 of the 20 cases only the collective gets right are `tracking_artifact`: the single agent trusts
the device gate; the collective's Signal Quality agent recomputes from raw frames and vetoes.

## Fault isolation (one component corrupted)

| fault | collective: unsupported | single function: unsupported |
|---|---|---|
| memory byzantine | 0/270 | 91/270 (33.7%) |
| physiology/analysis byzantine | 3/270 (1.1%) | 88/270 (32.6%) |
| skeptic/robustness byzantine | 3/270 (1.1%) | 20/270 (7.4%) |

The trade-off: under 6 of 10 collective fault modes, the collective stays safe by **abstaining**
(accuracy falls to 34–56%, over-abstention 58–100%). The single function keeps answering (66–93% correct)
but a third of its answers become unsupported. Only 4 fault modes have a like-for-like counterpart.

## Cost and latency (per case)

| system | median ms | p95 ms | LLM tokens |
|---|---|---|---|
| Deterministic / single agent | 0.01 | 0.01 | 0 |
| Collective + CI | 9.6 | 15.0 | 0 |
| Ablation | 7.2 | 9.3 | 0 |

Live iPhone → server round trips measured in the simulator: 12–21 ms server time.

## What this shows and does not show

- **Shown (synthetic):** independent recomputation from raw frames + a head-motion counterfactual +
  trust-aware memory reduce unsupported conclusions from 8.1% (single agent) to 1.1%, significant on
  paired cases.
- **Not shown:** that *organising* the checks as agents improves accuracy — the single-function
  ablation matches it exactly. What the agent organisation adds is **fault isolation**: a corrupted
  component causes abstention rather than confident wrong answers.
- **Not shown:** that CI beats raw history overall (p = 0.625); it helps only on conflicting history
  (29/30 vs 27/30).
- **Not tested:** LLM agents (none are used); real people; real iPhone recordings at scale; any clinical
  outcome. A known engine blind spot exists below 2.6 deg/s (`neuroassist-ci/docs/ENGINE_BLINDSPOT.md`).
