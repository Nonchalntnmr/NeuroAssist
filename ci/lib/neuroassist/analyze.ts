import { GATE, PROCESSING } from './constants';
import { mad, median, medianCI } from './stats';

export interface Chunk {
  i0: number;
  i1: number;
  slope: number;
  icpt: number;
}

export interface Check {
  id: string;
  label: string;
  value: number;
  show: string;
  rule: string;
  ok: boolean;
  /** Plain-language reason shown when the check fails. */
  fix: string;
}

export interface Analysis {
  n: number;
  dur: number;
  fps: number;
  validFrac: number;
  /** Robust frame-to-frame noise estimate, degrees. */
  sigma: number;
  fastPhaseThreshold: number;
  fastPhases: number;
  chunks: Chunk[];
  /** Pooled RMS of the slow-phase fit residuals, degrees. */
  residualRms: number;
  est: number;
  ci: { lo: number; hi: number; hw: number } | null;
  /** Fast phases per second. */
  beat: number;
  checks: Check[];
  pass: boolean;
}

export interface AnalyzeOptions {
  /** Set false to disable in-segment median smoothing (used by tests and the benchmark). */
  smooth?: boolean;
  /** Override gate thresholds (used only to tune and test the gate on simulated data). */
  gate?: Partial<GateConfig>;
  /**
   * Times (s) where segments must be split even without a fast phase, for example the target
   * turnarounds of a pursuit test. A guard sample is removed on each side, as for fast phases.
   */
  splitTimes?: readonly number[];
  /**
   * Time windows [start, end] (s) left out of slow-phase fitting, for example while the eyes settle
   * at the start or reverse after a pursuit turnaround. These samples still count as valid frames.
   */
  excludeTimes?: readonly (readonly [number, number])[];
}

export type GateConfig = { -readonly [K in keyof typeof GATE]: number };

/**
 * Estimate slow-phase velocity (deg/s) from a gaze trace in DEGREES.
 *
 * 1. Noise: robust sigma from second differences of the raw signal (MAD-based).
 * 2. Fast phases: frame-to-frame velocity that departs from the local median velocity by more
 *    than a noise-scaled threshold. The trace is split there and at missing samples.
 * 3. Guard band: one sample is removed at each fast-phase edge, because at webcam frame rates a
 *    sample often lands part-way through the fast phase.
 * 4. Smoothing: a 3-sample median filter inside each saccade-free segment (never across one).
 * 5. Fit: least-squares line over windows of at most 0.5 s; slope = slow-phase velocity.
 * 6. Summary: median slope with a distribution-free 95% interval (binomial order statistics),
 *    reported only with at least GATE.minChunks windows.
 * 7. Gate: every check in `checks` must pass, otherwise no number is reported.
 */
export function analyze(t: readonly number[], xRaw: readonly number[], opts: AnalyzeOptions = {}): Analysis {
  const n = t.length;
  const dts: number[] = [];
  for (let i = 1; i < n; i++) dts.push((t[i] as number) - (t[i - 1] as number));
  const fps = 1 / median(dts);
  let valid = 0;
  for (let i = 0; i < n; i++) if (Number.isFinite(xRaw[i])) valid++;
  const validFrac = n ? valid / n : 0;

  const G: GateConfig = { ...GATE, ...opts.gate };

  // 1. Noise: robust sigma of second differences. A first estimate uses every valid triplet; it is
  //    refined below using only triplets inside slow-phase segments, so fast-phase corners do not
  //    count as noise.
  const sigmaAll = robustSigma(xRaw, () => true);

  // 2. Fast phases relative to the local median velocity.
  const vel = new Array<number>(n).fill(NaN);
  for (let i = 1; i < n; i++) {
    const a = xRaw[i - 1] as number, b = xRaw[i] as number;
    if (Number.isFinite(a) && Number.isFinite(b)) vel[i] = (b - a) / ((t[i] as number) - (t[i - 1] as number));
  }
  const half = Math.max(2, Math.round((PROCESSING.localMedianSec * fps) / 2));
  const localMed = vel.map((_, i) => {
    const w: number[] = [];
    for (let j = Math.max(1, i - half); j <= Math.min(n - 1, i + half); j++) if (Number.isFinite(vel[j])) w.push(vel[j] as number);
    return median(w);
  });
  const thresholdFor = (sg: number) =>
    Math.max(PROCESSING.minFastPhaseDev, PROCESSING.fastPhaseK * Math.SQRT2 * (Number.isFinite(sg) ? sg : 0) * fps);

  // Two passes: segment with the all-sample noise estimate, re-estimate noise inside the
  // segments, then segment again with the refined (usually lower) threshold.
  const isBreak = new Array<boolean>(n).fill(false);
  for (const ts of opts.splitTimes ?? []) {
    for (let i = 1; i < n; i++) if ((t[i - 1] as number) < ts && (t[i] as number) >= ts) { isBreak[i] = true; break; }
  }
  const excluded = t.map((tt) => (opts.excludeTimes ?? []).some(([a, b]) => tt >= a && tt <= b));
  let seg = segment(t, xRaw, vel, localMed, thresholdFor(sigmaAll), isBreak, excluded);
  const inside = new Array<boolean>(n).fill(false);
  for (const [a, b] of seg.runs) for (let i = a; i <= b; i++) inside[i] = true;
  const sigmaSeg = robustSigma(xRaw, (i) => !!inside[i - 1] && !!inside[i] && !!inside[i + 1]);
  const sigma = Number.isFinite(sigmaSeg) ? sigmaSeg : sigmaAll;
  const thr = thresholdFor(sigma);
  seg = segment(t, xRaw, vel, localMed, thr, isBreak, excluded);
  const runs = seg.runs;
  const fastPhases = seg.fastPhases;

  // 4. Smoothing inside segments only.
  const win = opts.smooth === false ? 1 : PROCESSING.smoothWindow;
  const x = smoothWithinRuns(xRaw, runs, win);

  // 5. Window fits.
  const maxN = Math.max(4, Math.round(PROCESSING.maxWindowSec * fps));
  const chunks: Chunk[] = [];
  let ssRes = 0, dof = 0;
  for (const [a, b] of runs) {
    for (let s = a; s <= b; s += maxN) {
      const e = Math.min(b, s + maxN - 1);
      if (e - s + 1 < 4 || (t[e] as number) - (t[s] as number) < PROCESSING.minWindowSec) continue;
      let st = 0, sx = 0, stt = 0, stx = 0;
      const m = e - s + 1;
      for (let i = s; i <= e; i++) {
        const ti = t[i] as number, xi = x[i] as number;
        st += ti; sx += xi; stt += ti * ti; stx += ti * xi;
      }
      const slope = (m * stx - st * sx) / (m * stt - st * st);
      const icpt = (sx - slope * st) / m;
      chunks.push({ i0: s, i1: e, slope, icpt });
      for (let i = s; i <= e; i++) ssRes += ((xRaw[i] as number) - (slope * (t[i] as number) + icpt)) ** 2;
      dof += m - 2;
    }
  }
  const residualRms = dof > 0 ? Math.sqrt(ssRes / dof) : NaN;
  const residualRatio = Number.isFinite(sigma) && sigma > 0 ? residualRms / sigma : NaN;

  // 6. Summary statistic and interval.
  const slopes = chunks.map((c) => c.slope);
  const est = median(slopes);
  const ci = medianCI(slopes, G.minChunks);
  const hw = ci ? ci.hw : NaN;
  const dur = n ? (t[n - 1] as number) - (t[0] as number) : 0;

  // 7. Gate.
  const checks: Check[] = [
    { id: 'valid', label: 'Valid frames', value: validFrac, show: `${(validFrac * 100).toFixed(0)}%`, rule: `≥ ${G.minValid * 100}%`, ok: validFrac >= G.minValid,
      fix: 'Too many blinks or lost frames. Face the camera and keep your eyes open.' },
    { id: 'fps', label: 'Frame rate', value: fps, show: `${fps.toFixed(0)} fps`, rule: `≥ ${G.minFps} fps`, ok: fps >= G.minFps,
      fix: 'The frame rate is too low to separate fast phases from slow phases. Use a camera that records at 30 fps or more.' },
    { id: 'noise', label: 'Tracking noise', value: sigma, show: Number.isFinite(sigma) ? `${sigma.toFixed(2)}°` : 'n/a', rule: `≤ ${G.maxNoise.toFixed(2)}°`, ok: Number.isFinite(sigma) && sigma <= G.maxNoise,
      fix: 'Eye tracking is too noisy. Improve the lighting and keep the camera steady.' },
    { id: 'chunks', label: 'Clean slow-phase windows', value: chunks.length, show: String(chunks.length), rule: `≥ ${G.minChunks}`, ok: chunks.length >= G.minChunks,
      fix: 'There was not enough uninterrupted eye movement. Record for longer.' },
    { id: 'linearity', label: 'Slow-phase fit (residual / noise)', value: residualRatio, show: Number.isFinite(residualRatio) ? `${residualRatio.toFixed(2)}×` : 'n/a', rule: `≤ ${G.maxResidualRatio}×`, ok: Number.isFinite(residualRatio) && residualRatio <= G.maxResidualRatio,
      fix: 'The eye movement does not fit straight slow phases. Fast phases may have been missed, so no velocity is reported.' },
    { id: 'ci', label: 'Uncertainty (95% half-width)', value: hw, show: Number.isFinite(hw) ? `±${hw.toFixed(2)} deg/s` : 'n/a', rule: `≤ ${G.maxCI.toFixed(1)} deg/s`, ok: Number.isFinite(hw) && hw <= G.maxCI,
      fix: 'The estimate is too uncertain to report. Retake the recording.' },
  ];
  return {
    n, dur, fps, validFrac, sigma, fastPhaseThreshold: thr, fastPhases, chunks, residualRms, est, ci,
    beat: dur > 0 ? fastPhases / dur : 0, checks, pass: checks.every((c) => c.ok),
  };
}

/**
 * Median filter of odd width `win`, applied only where the whole window lies inside one
 * saccade-free segment; samples near segment edges stay as recorded. For a straight slow phase
 * with symmetric noise this is unbiased, so slopes are preserved while single-frame landmark
 * glitches are suppressed.
 */
export function smoothWithinRuns(x: readonly number[], runs: readonly [number, number][], win: number): number[] {
  const out = [...x];
  if (win <= 1) return out;
  const h = win >> 1;
  for (const [a, b] of runs) {
    for (let i = a + h; i <= b - h; i++) {
      const w: number[] = [];
      for (let j = i - h; j <= i + h; j++) w.push(x[j] as number);
      out[i] = median(w);
    }
  }
  return out;
}

/** Robust noise sigma (degrees) from second differences at sample indices where `use(i)` is true. */
function robustSigma(x: readonly number[], use: (i: number) => boolean): number {
  const d2: number[] = [];
  for (let i = 1; i < x.length - 1; i++) {
    const a = x[i - 1] as number, b = x[i] as number, c = x[i + 1] as number;
    if (use(i) && Number.isFinite(a) && Number.isFinite(b) && Number.isFinite(c)) d2.push(c - 2 * b + a);
  }
  return d2.length > 5 ? (1.4826 * mad(d2)) / Math.sqrt(6) : NaN;
}

/**
 * Split the trace into slow-phase segments: runs of valid samples with no fast-phase transition,
 * trimmed by the guard band at fast-phase edges.
 */
function segment(
  t: readonly number[],
  x: readonly number[],
  vel: readonly number[],
  localMed: readonly number[],
  thr: number,
  isBreak: readonly boolean[],
  excluded: readonly boolean[],
): { runs: [number, number][]; fastPhases: number } {
  const n = t.length;
  const isFast = new Array<boolean>(n).fill(false);
  let fastPhases = 0;
  for (let i = 1; i < n; i++) {
    const v = vel[i] as number;
    if (Number.isFinite(v) && Math.abs(v - (localMed[i] as number)) > thr) {
      isFast[i] = true;
      if (!isFast[i - 1]) fastPhases++;
    }
  }
  const rawRuns: [number, number][] = [];
  let rs = -1;
  for (let i = 0; i < n; i++) {
    if (!Number.isFinite(x[i]) || excluded[i]) {
      if (rs >= 0) rawRuns.push([rs, i - 1]);
      rs = -1;
      continue;
    }
    if (rs < 0) { rs = i; continue; }
    if (isFast[i] || isBreak[i]) { rawRuns.push([rs, i - 1]); rs = i; }
  }
  if (rs >= 0) rawRuns.push([rs, n - 1]);
  const g = PROCESSING.fastPhaseGuard;
  const cut = (i: number) => !!isFast[i] || !!isBreak[i];
  const runs: [number, number][] = [];
  for (const [a0, b0] of rawRuns) {
    const a = a0 > 0 && cut(a0) ? a0 + g : a0;
    const b = b0 < n - 1 && cut(b0 + 1) ? b0 - g : b0;
    if (b >= a) runs.push([a, b]);
  }
  return { runs, fastPhases };
}
