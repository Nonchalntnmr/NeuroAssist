# Demo Script — 90 seconds

## Setup (before going on stage)

1. Mac and iPhone on the same Wi-Fi.
2. Start the collective: `cd ~/projects/contextual-intelligence/neuroassist-ci && ./scripts/serve_lan.sh`
   (prints the Mac's LAN IP; check `http://<ip>:8000/api/py/health` returns `"ok":true`).
3. In the app: run one test, scroll to **Agent Collective · CI**, tap the gear, enter `http://<ip>:8000`,
   turn on consent. Accept the Local Network prompt.
4. Seed history: run the test 3 times so the 4th run shows a personal comparison (NO CHANGE).
5. Fallback if the camera misbehaves: Ready Check → **Run in Demo Mode** (every screen says SIMULATED).
   Fallback if Wi-Fi fails: run the simulator on the Mac with the server at `127.0.0.1`.

## Script

| time | on screen | say |
|---|---|---|
| 0–15 s | Home | "A phone can measure eye movements, but the signal is noisy. Our question: can a collective of specialised agents make those measurements more reliable and better-supported than a single agent? We built an experiment to test that." |
| 15–35 s | Ready Check → calibration → stripes | "TrueDepth at 60 Hz. Six live quality gates, five-dot calibration that pauses instead of restarting when you blink or move, then 10 seconds of moving stripes." (If demo mode: "This is labelled synthetic data driving the same pipeline.") |
| 35–55 s | Result → Agent Collective card → Run Collective Review | "Only numbers leave the phone, with consent. Five agents: Signal Quality recomputes from raw frames, Memory reads my history in CI, Physiology never sees the trace, the Skeptic tests a head-motion explanation, the Auditor certifies. Quality and Skeptic can veto. Here's the full deliberation." |
| 55–75 s | Comparison pills; `BENCHMARK_RESULTS.md` table | "On 270 synthetic cases with known ground truth, unsupported conclusions drop from 8.1% for a single-pass agent to 1.1%, p = 2×10⁻⁵. Honest caveat: the same checks in one function match it. What agents add is fault isolation — corrupt one component and the collective abstains instead of answering wrong." |
| 75–90 s | Report / limitations | "No LLMs, no diagnosis, synthetic validation only. Next: real-device repeatability and a preregistered LLM-agent comparison. The Evidence Auditor is reusable by any team today." |

Every number above is in `BENCHMARK_RESULTS.md` or `SCIENTIFIC_VALIDATION.md`.
