# Scientific Validation — what has and has not been verified

NeuroAssist is an experimental measurement and decision-support prototype. It is **not** a clinically
validated device. It does not detect intoxication, diagnose neurological disease, or determine fitness to drive.

## Verified (2026-11-01), with how

| claim | evidence |
|---|---|
| iOS app builds | Xcode build, scheme MyApp, iOS 27.1 SDK |
| iOS unit tests pass: 22/22 | `RunAllTests`: 14 signal tests (constant-velocity recovery, sinusoidal pursuit, rapid motion rejection, irregular timestamps/jitter, missing frames, blink blanking, angular wraparound, head motion, noise gate, calibration failure, CI contract) + 8 bridge payload tests |
| CI tests pass: 43/43 | `pytest` in `neuroassist-ci` (29 existing + 14 for the new `/ingest` endpoint: validation, non-finite rejection, subject isolation, motion-artifact veto) |
| End-to-end phone → CI → phone | iPhone 17 simulator, demo mode, 4 consecutive runs: NO_BASELINE at n = 0–2, NO_CHANGE at n = 3 (z = −0.08); phone and server engines agreed within 0.05 deg/s (8.04 vs 8.06) |
| Server rejects bad artifacts on iPhone-like traces | synthetic 60 Hz OKN: clean → MEASURED 7.98 deg/s; head-motion artifact → ABSTAIN (Signal Quality veto, HEAD_COUPLING); 40% tracking loss → ABSTAIN (MISSING_FRAMES) |
| Collective benchmark | 270 synthetic held-out cases; see `BENCHMARK_RESULTS.md` |
| Calibration timing bug fixed | dots were windowed with `CFAbsoluteTime` (since 2001) against uptime-based sample timestamps, so no sample could ever fall inside a dot window; now uses `systemUptime` |

## Not verified

- **Live TrueDepth capture on a physical iPhone after today's fixes.** The last on-device screenshot
  (older build) showed 0 fps / no ARFrames. Diagnostics (`os.Logger`, subsystem `neuroassist`) were added
  to locate the stall; no device was connected for the re-test.
- Camera interruption and background/foreground recovery on device (code paths exist; not exercised).
- Any measurement on real people; repeatability; agreement with a reference eye tracker.
- Whether OKN slow-phase velocity from a phone at ~30 cm is physiologically informative for any condition.
- LLM-based agents or an LLM single-agent baseline (none are used anywhere).

## Measurement integrity rules in the pipeline

- Lost, blink, or non-finite frames are sent as `null`, never interpolated into the evidence.
- Time is relative to the first frame and forced non-decreasing; the server rejects zero median interval,
  non-finite values, and traces outside 30–3600 frames.
- Batched/irregular timestamps trigger a Signal Quality veto (>5% of intervals under ¼ of the median).
- Gate thresholds (server engine): valid frames ≥75%, fps ≥20, noise ≤0.45°, ≥8 slow-phase windows,
  residual ratio ≤1.25, 95% half-width ≤1.5 deg/s. They were not changed to make demos pass.
- Every result carries provenance; demo/synthetic runs are labelled SIMULATED on screen, sent as
  `SYNTHETIC`, and kept out of the personal baseline.

## Known limitations

- The engine is blind below ~2.6 deg/s: its gate passes recordings whose 95% interval rarely contains the
  truth (`neuroassist-ci/docs/ENGINE_BLINDSPOT.md`).
- The protocol field is `FIXATION` because the server contract allows only that value; the iPhone records
  OKN stripes analysed by the same slow-phase engine. This is a contract limitation, documented in code.
- Two engines exist (phone `SignalMath`, server `neurocore`); the server is the engine of record for the
  collective and both values are shown side by side.
