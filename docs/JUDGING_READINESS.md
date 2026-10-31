# ScienceClaw judging red-team

Rubric weights from scienceclawhack.ai. No scores are predicted; this lists evidence, the strongest
weakness a judge will find, and what was done about it.

## Problem significance and complexity (20%)

- **Evidence.** Camera eye-movement measurement fails in specific ways (head coupling, timing,
  gaps, individual baselines), each built into the benchmark. Prior art exists (Johns Hopkins'
  EyePhone, r = 0.98 vs VOG for horizontal slow-phase velocity in 10 healthy volunteers), which shows
  the measurement is feasible and moves the open problem to trustworthy interpretation.
- **Strongest weakness.** No real recordings: every number is synthetic.
- **Smallest improvement.** Record one real NeuroAssist session (the optokinetic stripes test has a
  known stimulus), export it as `naci.session/1`, and run it through `/sessions` → Import, live.
  **Not done:** needs a person at a camera. The import path exists and is tested.

## Scientific / technical impact (25%)

- **Evidence.** Held-out benchmark, frozen protocol, deviations logged; exact parity between the
  Python port and NeuroAssist's engine; a blind spot found in the parent engine
  (`docs/ENGINE_BLINDSPOT.md`); a reusable Evidence Auditor.
- **Strongest weakness.** The ground truth comes from our own generator, so a judge may suspect the
  cases were shaped to fit the system.
- **Done.** Truth uses only generator knowledge plus NeuroAssist's estimate on the uncorrupted twin
  trace; thresholds frozen in git before the single held-out run; the cases where NeuroAssist's own
  gate already wins are reported as ties, and the cases every system fails are listed.

## Decentralized agency (20%)

- **Evidence.** Enforced per-agent evidence access (tested), distinct authorities (veto, challenge,
  certify, claim), evidence requests and replies, no planner, emergent resolution in which no single
  agent decides.
- **Strongest weakness.** Agents are deterministic programs, not language models, so they can look
  like a scripted pipeline.
- **Done.** The `/collective` page lets a judge switch any agent off or make it lie and see the run
  change live; message order depends on what each agent observes (the conflict exchange, the
  counterfactual exchange). Deterministic agents are presented as a deliberate choice: every number is
  reproducible and no model can invent one.

## Collective capability (25%)

- **Evidence.** Collective 98.9% vs single agent 91.9%; unsupported conclusions 1.1% vs 8.1%.
- **Strongest weakness.** The single-program ablation with the same checks also scores 98.9%.
- **Done.** Measured what organisation adds: under any single-component fault the collective stays at
  ≤1.1% unsupported conclusions, while the same fault in the single program gives 33.7% (memory),
  32.6% (analysis) or 7.4% (robustness). Stated on the site, in the README and in the deck.

## Execution and validation (10%)

- **Evidence.** 29 Python tests, 6 TypeScript tests, strict typecheck, production build of 13 routes,
  a smoke test that passes locally (routes, API, live run, auditor, error handling, secret scan).
- **Strongest weakness.** Not yet deployed (the build environment cannot reach Vercel; publishing a
  public repository needs the owner's go-ahead).
- **Next.** Create the GitHub repo, import to Vercel, run `node e2e/smoke.mjs <url>` against it.

## Collaboration bonus

The Evidence Auditor is published with a schema, examples (including a non-eye domain), tests and an
HTTP endpoint. **No reuse by another team is claimed.** Claim it only with evidence (their commit,
their call to the endpoint, or their slide).
