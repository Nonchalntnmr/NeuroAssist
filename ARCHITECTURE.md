# Architecture — NeuroAssist × Contextual Intelligence

```
iPhone (NeuroAssist, SwiftUI)                         Mac / server (neuroassist-ci, FastAPI)
┌──────────────────────────────────────┐   consent   ┌───────────────────────────────────────────┐
│ ARKit TrueDepth 60 Hz (FaceEyeTracker)│  naci.      │ /api/py/v1/collective/ingest              │
│  → Ready Check (6 live gates)        │  ingest/1   │  neurocore recomputes measurement         │
│  → 5-dot calibration (fit, RMS ≤1.5°)│ ──────────▶ │  (engine of record)                       │
│  → 10 s OKN stripes                  │  numbers    │  → 5 agents exchange naci.agent-message/1 │
│  → SignalMath: 11 gates / abstain    │  only, no   │     Signal Quality · Memory(CI) ·         │
│  → Result + Agent Collective card    │  images     │     Physiology · Skeptic · Auditor        │
│ History: per-subject JSON, file-     │ ◀────────── │  → verdict + transcript + audit chain     │
│ protected; demo subject separate     │  naci.run/1 │ Stateless: per-request in-memory CI store │
└──────────────────────────────────────┘             └───────────────────────────────────────────┘
```

## iOS app (`MyApp/`)

| file | role |
|---|---|
| `FaceEyeTracker.swift` | ARSession lifecycle, permissions, interruption recovery, 60 Hz sample ingest, demo mode, `os.Logger` diagnostics |
| `LiveCheckView.swift` | Ready Check: light ≥250 lx, distance 25–40 cm, head steady (≤1.5° over 1 s), ≥20 fps, face tracked, eyes open |
| `CalibrationView.swift` | positioning hold (0.75 s) → 5 dots; per dot 380 ms move, 300 ms settle, ≤3.5 s sampling that **pauses** (not restarts) on face loss, distance, head motion or blink; 2 attempts per dot |
| `StripesTestView.swift` | 10 s optokinetic stripes (2° period, 10°/s), live trace, adaptive early stop/abort |
| `SignalMath.swift` | calibrated slow-phase analysis, 11 quality gates, abstention, provenance (`LIVE TRUEDEPTH` / `SIMULATED` / `RECORDED SESSION`) |
| `CollectiveBridge.swift` | `naci.ingest/1` client, consent, on-device history, Agent Collective card |
| `ResultView.swift` | result, trace, quality checks, collective review |

## Five-stage workflow audit

| stage | inputs | success | timeout / recovery | failure message (user-facing) |
|---|---|---|---|---|
| 1 Ready Check | live tracker state | all 6 gates green | none; continuous feedback, "Run in Demo Mode", retry camera | first failing gate, e.g. "Move phone slightly further (~30 cm)"; camera error card with Retry |
| 2 Calibration | gaze + head + distance per frame | 5 dots fitted, RMS ≤1.5°, \|slope\| > 0.05 | per-dot sampling pauses on transient loss; 3.5 s cap; 2 attempts/dot | "Fixation was interrupted at Target N…" / "Residual fit error (x°) exceeded the 1.50° threshold…" |
| 3 Stripes | calibrated gaze, 10 s | ≥8 clean slow-phase windows | adaptive mode stops early on precision, aborts early on quality | live warning pill; result abstains with reasons |
| 4 Result | samples + calibration | 11 gates pass | Retake reuses accepted calibration (no full restart) | ABSTAIN card listing failed gates |
| 5 Collective | trace + history (consented) | verdict CHANGE / NO_CHANGE / NO_BASELINE | network failure → on-device result stands, explicit "Collective not run" | server error text shown verbatim |

## Agents (`neuroassist-ci/naci/collective.py`) — deterministic algorithms, not LLMs

| agent | sees | does | can veto |
|---|---|---|---|
| Signal Quality | raw trace | recomputes measurement; frame timing, gaps, head coupling | yes |
| Contextual Memory | CI only | trusted baseline (≥3 accepted sessions), conflicts, writes the session after verdict | no |
| Physiology | numbers only, never the trace | z-score vs personal baseline; CHANGE if \|z\| ≥ 3 | no (withdraws if challenged) |
| Skeptic | findings + head channel | head-motion counterfactual re-analysis; challenges thin/conflicting baselines | yes |
| Auditor | all evidence | Evidence Auditor; any veto or open challenge forces ABSTAIN | refuses to certify |

Information access is enforced in code and logged (`access_log` in each response).

## Data contracts

- `naci.ingest/1` (phone → server): session/subject ids (pseudonymous), `recorded_at`, provenance
  (`REAL`/`SYNTHETIC`/`PRERECORDED`, device, capture metadata incl. calibration RMS and the phone's own
  result), trace `{t, x (null = lost frame), head}`, history ≤60 records.
- `naci.session/1` (server → phone, stored as history): measurement value + 95% CI + windows, quality
  checks, abstain reasons, provenance.
- `naci.run/1`: decision, vetoes, every agent message, deterministic and single-agent comparison,
  hash-chained audit, latency.

## Privacy and safety

- No images or video leave the phone; only per-frame angles. Sending requires an explicit consent toggle
  that names the destination. The UI says processing is off-device.
- Server keeps nothing after responding (in-memory encrypted CI store per request).
- History lives on the phone (`.completeFileProtection`), per pseudonymous subject; synthetic runs use a
  separate subject; user can delete it from the card.
- No API keys or secrets in the app. Plain http is allowed only for local networking (ATS `NSAllowsLocalNetworking`).
