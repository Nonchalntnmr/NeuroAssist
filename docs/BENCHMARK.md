# Benchmark protocol

All data in this benchmark is **SYNTHETIC**. Traces come from NeuroAssist's own simulator
(`lib/neuroassist/simulate.ts`); every measurement and quality verdict on a record comes from
NeuroAssist's own engine and gate (`lib/neuroassist/analyze.ts`). Nothing here has been
validated on people or against clinical eye-tracking equipment.

## Question

Can a decentralized collective distinguish meaningful measurement changes from tracking artifacts
and natural variability more reliably than simpler systems, given identical inputs?

## Splits

| split | salt | cases | use |
|---|---|---|---|
| `dev` | 7 | 9 types × 12 = 108 | choosing thresholds and fixing bugs |
| `heldout` | 2026 | 9 types × 30 = 270 | reported once, after the freeze commit |

`benchmark/cases/MANIFEST.json` records the sha256 of each suite file. The benchmark run records the
sha256 of the file it read.

## Case types

| type | what the generator does | ground truth |
|---|---|---|
| `clean` | normal recording, true SPV within ±1.2 τ of the subject mean μ | NO_CHANGE |
| `tracking_artifact` | head yaw (≤1.8°, under NeuroAssist's 2° head gate) leaks into gaze; half return slowly, half snap back in one frame (looks like a fast phase) | ABSTAIN when the corruption moves NeuroAssist's estimate by more than max(its 95% half-width, 0.5 deg/s), or the gate abstains |
| `missing_frames` | 28–42% of frames lost in bursts | same rule |
| `irregular_timestamps` | frames delivered in batches of 1–4 and stamped on arrival | same rule |
| `insufficient_baseline` | 1–2 prior sessions | NO_BASELINE |
| `misleading_change` | previous visit was an unusually low day (μ − 2.4 τ); target at μ + 1 τ | NO_CHANGE |
| `true_change` | target moved by max(2.8 deg/s, 6–8 τ) | CHANGE |
| `conflicting_history` | 4 measured sessions plus 2–5 newer exported files of unverified origin that disagree by ~4.5 deg/s | NO_CHANGE (relative to measured sessions) |
| `change_with_incidental_artifact` | true change plus small head motion (≤0.35°) | CHANGE unless the motion moves the estimate (same rule) |

Ground truth uses only what the generator knows: the true SPV, the subject's true μ and τ, which
corruption was applied, and NeuroAssist's estimate on the **same trace without the corruption**.
CHANGE means |true SPV − μ| ≥ 4 τ; generated no-change targets stay within 1.2 τ.

Subjects have a stable spontaneous nystagmus (|SPV| 3.4–6 deg/s, τ 0.25–0.75). Magnitudes stay at
or above 2.6 deg/s because NeuroAssist's engine is biased below that on its own simulator
(`docs/ENGINE_BLINDSPOT.md`).

## Systems

1. **deterministic**: NeuroAssist's gate, then compare with the previous visit (change if the two
   95% intervals do not overlap).
2. **single_agent**: one analyst with every input in one pass: device verdict, full history,
   z-score against all prior measured sessions. No trace inspection, no challenge, no memory semantics.
3. **collective_no_history**: the collective without the memory agent.
4. **collective_naive_history**: the collective, memory agent reads the raw history list (no CI).
5. **collective_ci**: the full collective, memory through CI.
6. **monolith_ci** (ablation): every check the collective runs, in one function, with CI, no agents.

No system uses a language model. Every number is computed by deterministic code.

## Metrics

- **accuracy**: decision equals ground truth.
- **unsupported conclusion rate**: a CHANGE or NO_CHANGE that is not the truth, over all cases.
- **appropriate abstention**: ABSTAIN or NO_BASELINE when truth is ABSTAIN or NO_BASELINE.
- **over-abstention**: ABSTAIN or NO_BASELINE when truth is CHANGE or NO_CHANGE.
- **artifact detection recall**: the system flagged a quality problem on cases with any injected
  corruption (including harmless ones). **harmful artifact caught**: ABSTAIN on cases whose corruption
  moves the estimate.
- **baseline retrieval (Jaccard)**: sessions the system compared against vs the measured, trusted,
  prior sessions; on cases whose truth is a comparison.
- **evidence traceability**: share of reported decisions whose certified verdict cites evidence items
  that exist and carry a content hash. Systems without an evidence ledger score 0 by construction.
- **latency**: wall time per case on the machine that ran it; **LLM tokens**: 0 for every system.

## Fault experiment

One agent at a time is made **silent** (never acts) or **byzantine** (Signal Quality accepts everything
and refuses re-analysis; Memory returns only the last record and calls it sufficient; Physiology always
claims CHANGE; Skeptic never challenges; Auditor certifies everything). The same component faults are
applied to the monolith's corresponding stage.

## Thresholds (chosen on dev only)

`naci/collective.py`: Z_CHANGE 3.0, HEAD_RATE 0.4 deg/s, HEAD_RANGE 1.0°, ROBUST_MIN 0.5 deg/s,
AGREE_TOL 0.05 deg/s, TIMING_TINY 0.05, MAX_GAP_S 1.0.

## Deviations and fixes before the freeze (all on dev)

- **D1** `conflicting_history` v1 used exactly 2 imports with 5 measured sessions. A robust median
  already ignores 2 of 7, so the case did not test source trust. v2: 4 measured sessions and 2–5
  imports. Changed after seeing dev results, before any held-out run.
- **D2** The Skeptic's own head check (median window slope) missed snap-back slips when Signal Quality
  was made byzantine in the dev fault run. Added HEAD_RANGE (1.0°) as a second trigger.
- **F1** Records were analysed before rounding while the stored trace was rounded, so Signal Quality's
  recomputation disagreed with the device by up to 0.05 deg/s and vetoed a valid record. Records now
  analyse exactly the stored trace.
- **F2** Physiology repeated its "no assessment" message every round. Now posts once.
- **G1** Generator bug: a negative head-rotation rate produced a negative ramp time. Fixed.
- **G2** The first scenario design put subjects at |SPV| < 1.5 deg/s, where NeuroAssist's engine
  abstains or is biased. Moved to ≥2.6 deg/s (see ENGINE_BLINDSPOT.md).

The freeze is the git commit titled "Freeze benchmark protocol and thresholds before held-out run".
