/**
 * SYNTHETIC scenario generator. Every trace comes from NeuroAssist's own simulator
 * (lib/neuroassist/simulate.ts) and every measurement from NeuroAssist's own engine and gate
 * (lib/neuroassist/analyze.ts). Corruptions are added on top and recorded in the generator
 * parameters. Ground truth comes from what the generator knows (true slow-phase velocity, the
 * subject's true day-to-day spread, which corruption was applied), never from any system under
 * test.
 */
import { simulate } from './neuroassist/simulate';
import { analyze } from './neuroassist/analyze';
import { gauss, rng, type Rand } from './neuroassist/stats';
import { toRecord } from './records';
import type { SessionRecord } from './contract';

export const CASE_TYPES = [
  'clean',
  'tracking_artifact',
  'missing_frames',
  'irregular_timestamps',
  'insufficient_baseline',
  'misleading_change',
  'true_change',
  'conflicting_history',
  'change_with_incidental_artifact',
] as const;
export type CaseType = (typeof CASE_TYPES)[number];
export type Decision = 'CHANGE' | 'NO_CHANGE' | 'NO_BASELINE' | 'ABSTAIN';

export interface Corruption {
  head?: { rate: number; amp: number; back?: number }; // head yaw sawtooth (deg/s, deg, return s) that leaks into gaze
  burstLoss?: { frac: number }; // contiguous lost-frame bursts
  timing?: { maxGroup: number }; // frames delivered in batches and stamped on delivery
}

export interface Truth {
  decision: Decision;
  artifact: boolean;
  baseline_ids: string[];
  true_spv: number;
  subject_mu: number;
  subject_tau: number;
  /** NeuroAssist estimate on the same trace without corruption (corrupted cases only). */
  est_clean?: number | null;
  est_corrupted?: number | null;
  corruption_moves_estimate?: boolean;
  note: string;
}

export interface Case {
  case_id: string;
  type: CaseType;
  split: string;
  subject_id: string;
  history: SessionRecord[];
  target: SessionRecord;
  truth: Truth;
}

const DAY = 86400e3;
const iso = (ms: number) => new Date(ms).toISOString();
const uni = (r: Rand, a: number, b: number) => a + (b - a) * r();

/** One fixation recording: NeuroAssist simulator, then optional corruptions. */
export function makeTrace(seed: number, spv: number, noise: number, c: Corruption = {}) {
  const tr = simulate({ seed, spv, fps: 30, noise, blinks: 2, lost: 2, dur: 10 });
  const r = rng(seed ^ 0x5bd1e995);
  const n = tr.t.length;
  const t = [...tr.t];
  const x = [...tr.x];
  // Signed head-yaw channel, degrees. NeuroAssist live frames record rotation magnitude (`h`); the
  // contract asks for signed yaw so a head-coupled bias can be corrected (docs/CONTRACT.md).
  const head = t.map(() => gauss(r) * 0.05);
  if (c.head) {
    const { rate, amp } = c.head;
    const back = c.head.back ?? 0.12;
    const dir = Math.sign(rate) || 1;
    const ramp = amp / Math.abs(rate);
    const per = ramp + back;
    const phase0 = r() * per;
    for (let i = 0; i < n; i++) {
      const ph = ((t[i] as number) + phase0) % per;
      // Yaw ramps from 0 to amp (in direction `dir`), then returns quickly.
      const yaw = dir * (ph < ramp ? Math.abs(rate) * ph : amp * (1 - (ph - ramp) / back));
      head[i] = yaw + gauss(r) * 0.05;
      if (Number.isFinite(x[i])) x[i] = (x[i] as number) + yaw; // apparent gaze shifts with the head
    }
  }
  if (c.burstLoss) {
    let lost = x.filter((v) => !Number.isFinite(v)).length;
    const want = Math.round(c.burstLoss.frac * n);
    let guard = 0;
    while (lost < want && guard++ < 200) {
      const s = Math.floor(r() * n);
      const len = 8 + Math.floor(r() * 25);
      for (let i = s; i < Math.min(n, s + len); i++) if (Number.isFinite(x[i])) { x[i] = NaN; lost++; }
    }
  }
  if (c.timing) {
    // Frames reach the page in batches of 1..maxGroup and are stamped when the batch arrives.
    let i = 0;
    while (i < n) {
      const g = 1 + Math.floor(r() * c.timing.maxGroup);
      const last = Math.min(n - 1, i + g - 1);
      const arrive = (tr.t[last] as number) + 0.004;
      for (let k = i; k <= last; k++) t[k] = arrive + (k - i) * 0.001;
      i = last + 1;
    }
    for (let k = 1; k < n; k++) if ((t[k] as number) <= (t[k - 1] as number)) t[k] = (t[k - 1] as number) + 0.001;
  }
  return { t, x, head, clean: tr };
}

function session(
  r: Rand, seed: number, subject: string, id: string, whenMs: number, spv: number,
  opts: { label?: 'SYNTHETIC' | 'PRERECORDED'; source?: string; engine?: string; c?: Corruption; withTrace?: boolean; noise?: number } = {},
) {
  const noise = opts.noise ?? uni(r, 0.08, 0.16);
  const tr = makeTrace(seed, spv, noise, opts.c);
  const { record, analysis } = toRecord(tr.t, tr.x, tr.head, {
    session_id: id, subject_id: subject, recorded_at: iso(whenMs),
    label: opts.label ?? 'SYNTHETIC', source: opts.source ?? 'neuroassist-simulator', engine: opts.engine,
    generator: { seed, true_spv: Math.round(spv * 1e4) / 1e4, noise: Math.round(noise * 1e4) / 1e4, corruption: opts.c ?? {} },
  }, opts.withTrace ?? false);
  return { record, analysis, tr };
}

/** Deterministic: the same (type, index, split salt) always yields the same case. */
export function makeCase(type: CaseType, index: number, split: string, salt: number): Case {
  const seed0 = (salt * 1_000_003 + CASE_TYPES.indexOf(type) * 10_007 + index * 101) >>> 0;
  const r = rng(seed0);
  const subject = `subj-${split}-${CASE_TYPES.indexOf(type)}-${index}`;
  // Subjects with a known, stable spontaneous nystagmus being monitored over time. Magnitudes are kept
  // at |SPV| >= 2.6 deg/s, where NeuroAssist's engine is accurate on its own simulator (below that its
  // fast-phase detector misses the resets; see docs/ENGINE_BLINDSPOT.md).
  const sign = r() < 0.5 ? -1 : 1;
  const mu = sign * (type === 'misleading_change' ? uni(r, 4.6, 6) : uni(r, 3.4, 6));
  const tau = type === 'misleading_change' ? uni(r, 0.5, 0.75) : uni(r, 0.25, 0.55);
  const keep = (v: number) => sign * Math.max(2.6, sign * v);
  const start = Date.parse('2026-08-03T15:00:00Z') + Math.floor(r() * 10) * DAY;
  const nHist = type === 'insufficient_baseline' ? 1 + Math.floor(r() * 2) : type === 'conflicting_history' ? 4 : 6;

  const history: SessionRecord[] = [];
  const trusted: string[] = [];
  for (let i = 0; i < nHist; i++) {
    let spv = mu + tau * gauss(r);
    if (type === 'misleading_change' && i === nHist - 1) spv = mu - sign * 2.4 * tau; // the last visit was an unusually low day
    spv = keep(Math.max(mu - 2.6 * tau, Math.min(mu + 2.6 * tau, spv)));
    const id = `${subject}-s${i + 1}`;
    const s = session(r, seed0 + 17 + i * 7919, subject, id, start + i * 6 * DAY, spv, { noise: uni(r, 0.07, 0.12) });
    history.push(s.record);
    if (s.record.measurement.status === 'MEASURED') trusted.push(id);
  }
  if (type === 'conflicting_history') {
    // 2-5 exported files of unknown origin, most recent, that disagree with everything measured.
    // (v1 used exactly 2 of 7; a robust median already handled that. Changed on the dev split only,
    // before any held-out run: docs/BENCHMARK.md, deviation D1.)
    const nImports = 2 + Math.floor(r() * 4);
    for (let k = 0; k < nImports; k++) {
      const id = `${subject}-import${k + 1}`;
      const s = session(r, seed0 + 333 + k * 31, subject, id, start + (nHist + k) * 6 * DAY, mu + sign * (4.5 + 0.4 * gauss(r)), {
        label: 'PRERECORDED', source: 'export:unverified', engine: 'neurocore-0.3.2', noise: 0.09,
      });
      history.push(s.record);
    }
  }

  const when = start + (history.length + 1) * 6 * DAY;
  let trueSpv = keep(mu + tau * uni(r, -1.2, 1.2));
  let c: Corruption = {};
  let artifact = false;
  let note = 'Clean recording, within the subject’s usual range.';
  switch (type) {
    case 'tracking_artifact':
      // Even index: slow return (NeuroAssist's linearity check usually catches it). Odd index: the
      // estimate snaps back within one frame, which looks like a fast phase and can pass the gate.
      c = { head: { rate: (r() < 0.5 ? -1 : 1) * uni(r, 2.6, 3.6), amp: uni(r, 1.5, 1.8), back: index % 2 ? 0.02 : 0.12 } };
      artifact = true;
      note = index % 2
        ? 'Tracking slip: the gaze estimate slides with a head micro-rotation (below the 2° head gate) and snaps back within one frame, like a fast phase.'
        : 'Head micro-rotation (below NeuroAssist’s 2° head gate) leaks into the gaze estimate and returns slowly.';
      break;
    case 'missing_frames':
      c = { burstLoss: { frac: uni(r, 0.28, 0.42) } };
      artifact = true; note = 'Long bursts of lost frames.';
      break;
    case 'irregular_timestamps':
      c = { timing: { maxGroup: 3 + Math.floor(r() * 2) } };
      artifact = true; note = 'Frames delivered in batches and stamped on arrival instead of capture.';
      break;
    case 'insufficient_baseline':
      note = 'Fewer than three prior measured sessions.';
      break;
    case 'misleading_change':
      trueSpv = keep(mu + sign * tau * uni(r, 0.8, 1.2));
      note = 'Far from the previous visit (an unusually low day) but inside the subject’s usual range.';
      break;
    case 'true_change':
      trueSpv = mu + sign * Math.max(2.8, tau * uni(r, 6, 8));
      note = 'True synthetic change in slow-phase velocity.';
      break;
    case 'conflicting_history':
      note = 'History contains unverified imports that contradict the measured sessions.';
      break;
    case 'change_with_incidental_artifact':
      trueSpv = mu + sign * Math.max(2.8, tau * uni(r, 6, 8));
      c = { head: { rate: (r() < 0.5 ? -1 : 1) * uni(r, 0.1, 0.25), amp: uni(r, 0.2, 0.35) } };
      artifact = true; note = 'True change, plus a small head movement that does not explain it.';
      break;
    default:
      break;
  }
  const tSeed = seed0 + 9001;
  const tgt = session(r, tSeed, subject, `${subject}-target`, when, trueSpv, { c, withTrace: true });

  // Ground truth.
  const underlying: Decision =
    trusted.length < 3 ? 'NO_BASELINE' : Math.abs(trueSpv - mu) / tau >= 4 ? 'CHANGE' : 'NO_CHANGE';
  let decision: Decision = underlying;
  const truth: Truth = { decision, artifact, baseline_ids: trusted, true_spv: trueSpv, subject_mu: mu, subject_tau: tau, note };
  if (artifact) {
    const clean = analyze(tgt.tr.clean.t, tgt.tr.clean.x);
    const a = tgt.analysis;
    truth.est_clean = clean.pass ? clean.est : null;
    truth.est_corrupted = a.pass ? a.est : null;
    if (!a.pass) {
      decision = 'ABSTAIN';
      truth.corruption_moves_estimate = true;
    } else {
      const hw = a.ci ? a.ci.hw : 0;
      const moved = clean.pass ? Math.abs(a.est - clean.est) > Math.max(hw, 0.5) : true;
      truth.corruption_moves_estimate = moved;
      if (moved) decision = 'ABSTAIN';
    }
  }
  if (!artifact && tgt.record.measurement.status === 'ABSTAINED') decision = 'ABSTAIN';
  truth.decision = decision;
  return { case_id: `${split}-${type}-${index}`, type, split, subject_id: subject, history, target: tgt.record, truth };
}

export function makeSuite(split: string, salt: number, perType: number): Case[] {
  const out: Case[] = [];
  for (const type of CASE_TYPES) for (let i = 0; i < perType; i++) out.push(makeCase(type, i, split, salt));
  return out;
}
