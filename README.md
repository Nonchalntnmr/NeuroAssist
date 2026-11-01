# NeuroAssist × CI

An iPhone eye-movement measurement instrument connected to a collective of specialised scientific agents
with Contextual Intelligence (CI) memory. Built for ScienceClaw 2026 at the MIT Media Lab.

> Research prototype. Not a medical device. It measures eye movement and reasons about measurement
> quality; it does not diagnose anything or determine fitness to drive. All benchmark data is synthetic.

## Quick start

**iOS app:** open `Untitled Project.xcodeproj` in Xcode, scheme **MyApp**, run on an iPhone with a
TrueDepth camera (or the simulator, which runs labelled demo mode automatically). Tests: Product → Test
(22 tests).

**Collective server:**

```bash
cd ~/projects/contextual-intelligence/neuroassist-ci
./scripts/serve_lan.sh            # prints the LAN URL to enter in the app
../.venv/bin/python -m pytest -q  # 43 tests
```

In the app: finish a test → **Agent Collective · CI** → gear → server URL → consent → **Run Collective Review**.

**Benchmark statistics:** `python3 docs/benchmark/stats.py`

## Two honest modes

- **Live capture** — real TrueDepth data; low-quality recordings abstain.
- **Demo mode** — Ready Check → *Run in Demo Mode*. Synthetic gaze follows the on-screen stimulus so the
  real calibration and analysis code runs end to end. Results are labelled SIMULATED, sent as `SYNTHETIC`,
  and kept in a separate demo history.

## Documents

- `SUBMISSION_SUMMARY.md` — one-page summary and slide outline
- `ARCHITECTURE.md` — system, agents, contracts, five-stage workflow audit
- `BENCHMARK_RESULTS.md` — collective vs baselines, with uncertainty
- `SCIENTIFIC_VALIDATION.md` — what was and was not verified
- `DEMO_SCRIPT.md` — 90-second demo
