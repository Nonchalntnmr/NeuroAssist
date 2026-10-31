# Architecture

```
NeuroAssist (parent A)            NeuroAssist × CI (child)                         CI (parent B)
camera → engine → gate  ──naci.session/1──►  Board ◄── agents ──►  Memory agent ──► TemporalMemory, ConsentLedger,
(lib/neuroassist, vendored)                   │ evidence ledger (sha256)               AuditLog, Store (pcim @ 2e50658)
                                              ▼
                                   verdict: CHANGE | NO_CHANGE | NO_BASELINE | ABSTAIN  + evidence
```

## Integration boundary: `naci.session/1`

One record per recording. Defined in `lib/contract.ts` and validated by `naci/contract.py` (pydantic,
`extra="forbid"`; unknown schema versions are rejected).

| field | meaning |
|---|---|
| `session_id`, `subject_id` | identifiers; the subject id is pseudonymous (pattern `[A-Za-z0-9._:-]+`) |
| `recorded_at` | ISO 8601; CI uses it as the episode's valid time |
| `protocol` | `FIXATION` (the only protocol in v1) |
| `provenance.label` | `REAL` (NeuroAssist camera session), `PRERECORDED` (exported file of unverified origin), `SYNTHETIC` (simulator) |
| `provenance.engine` | NeuroAssist engine version that produced the measurement |
| `measurement` | status (`MEASURED`/`ABSTAINED`), slow-phase velocity, 95% interval, window count |
| `quality` | the gate's six checks and abstain reasons |
| `trace` | per-frame `t` (s), `x` (gaze, deg, null when lost), `head` (signed yaw, deg). Required for the session under analysis |

**Gap with the parent:** NeuroAssist stores head rotation as a magnitude (`h ≥ 0`). The head-motion
counterfactual needs signed yaw. Producing it is a change in NeuroAssist's tracker; until then, real
records carry no `head` channel and the head check does not run (the collective says so).

**How real data gets in.** NeuroAssist runs in the browser (including iPhone Safari). Its sessions are
not yet posted to this service; the path is `/sessions` → *Import a session* (a `naci.session/1` file),
or `POST /api/py/v1/collective/run`. Nothing is stored server-side.

## The collective (`naci/collective.py`)

Rounds. In round *r* every agent sees messages from rounds < *r* and acts or not. Agents in one round
cannot see each other, so their order is irrelevant. The run ends after two quiet rounds.

| agent | reads (enforced by `Board.read`) | can |
|---|---|---|
| Signal quality | gaze, head, frame times, device record | recompute the measurement from frames; flag timing, gaps, head coupling, device/trace mismatch; **veto**; answer re-analysis requests |
| Contextual memory | CI only | build the as-of, trust-filtered baseline; report CI conflicts; explain them; write the session and verdict back to CI |
| Physiology | device record | make the only claims (CHANGE / NO_CHANGE / NO_BASELINE); **withdraw** them |
| Skeptic | head, frame times, device record | its own head-motion check; **request** counterfactuals; re-derive claims from their evidence; **challenge**; **veto** |
| Evidence auditor | device record + the ledger | certify claims with `evidence_auditor`; require a robustness test when quality has concerns |

All agents read the shared board: posted findings, claims and cited evidence.

**Resolution.** A claim is reported only if it stands (not withdrawn), the auditor certifies it, no veto
is active and no challenge to it is open. Vetoes and open challenges bind whatever the auditor says.
No agent decides alone; a silent auditor means no verdict, which means abstain.

**Message kinds.** FINDING, CLAIM, EVIDENCE_REQUEST, EVIDENCE, CHALLENGE, REVISION, RESOLVE, VETO,
VERDICT, MEMORY_WRITE. Format `naci.agent-message/1`; `AgentMessage.to_ci()` returns CI's
`ci.agent-message/1`.

**Evidence.** Every input or result an agent relies on is an evidence item whose id is derived from the
sha256 of its canonical JSON. Each `evidence.add` is appended to CI's hash-chained `AuditLog`;
`audit.verify()` runs on every response. CI gives memory items random ids, so evidence citing them
differs per run; decisions and numbers do not.

## API (`api/index.py`, FastAPI on a Vercel Python function)

| route | |
|---|---|
| `GET /api/py/health` | CI importable, CI commit, Python version |
| `POST /api/py/v1/collective/run` | `{target, history, variant?, faults?, compare?, canonical?}` → full run, plus the deterministic and single-agent systems |
| `POST /api/py/v1/auditor/audit` | `evidence-auditor.observation/1` → `evidence-auditor.report/1` |
| `GET /api/py/v1/benchmark` | held-out results |
| `GET /api/py/docs` | OpenAPI UI |

Limits: 2 MB body, 60 history records, 3,600 frames. Each run builds an in-memory CI store with an
ephemeral key and discards it. `Cache-Control: no-store`.

## Website

Next.js 14 (app router, static pages, client fetches to `/api/py`), Tailwind, Recharts. Locally
`/api/py/*` is proxied to uvicorn on :8000 (`next.config.mjs`); on Vercel it is rewritten to the Python
function.
