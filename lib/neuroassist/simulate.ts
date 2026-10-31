import { gauss, rng } from './stats';

export interface SimParams {
  seed: number;
  /** True slow-phase velocity, deg/s. */
  spv: number;
  fps: number;
  /** Camera noise sigma, degrees. */
  noise: number;
  /** Blinks per 10 s. */
  blinks: number;
  /** Percent of frames randomly lost. */
  lost: number;
  dur?: number;
}

export interface Trace {
  t: number[];
  /** Gaze in degrees; NaN where the frame is lost or the eye is closed. */
  x: number[];
}

/**
 * DEMO SIMULATION ONLY. Sawtooth nystagmus (slow phase at `spv`, fast reset every 0.5 s)
 * plus Gaussian camera noise, blinks and dropped frames. Values here are synthetic.
 */
export function simulate(p: SimParams): Trace {
  const r = rng(p.seed);
  const dur = p.dur ?? 8;
  const n = Math.floor(dur * p.fps);
  const per = 0.5;
  const t = new Array<number>(n);
  const x = new Array<number>(n);
  for (let i = 0; i < n; i++) {
    const tt = i / p.fps;
    const ph = (tt % per) / per;
    const pos =
      ph < 0.9 ? p.spv * (ph * per) - p.spv * 0.45 * per : p.spv * 0.45 * per - ((ph - 0.9) / 0.1) * p.spv * 0.9 * per;
    t[i] = tt;
    x[i] = pos + gauss(r) * p.noise;
  }
  const blinks = Math.round((p.blinks * dur) / 10);
  for (let b = 0; b < blinks; b++) {
    const start = r() * (dur - 0.3);
    const len = 0.18 + r() * 0.12;
    for (let i = 0; i < n; i++) if ((t[i] as number) >= start && (t[i] as number) <= start + len) x[i] = NaN;
  }
  for (let i = 0; i < n; i++) if (r() < p.lost / 100) x[i] = NaN;
  return { t, x };
}
