import type { Chunk } from './analyze';

export interface GazeRow { t: number; x: number | null; fit: number | null; target: number | null }
export interface VelocityRow { t: number; v: number | null }

const r3 = (v: number) => Math.round(v * 1000) / 1000;

/** Chart rows: gaze, the fitted slow-phase lines, and an optional target trace. */
export function gazeSeries(t: readonly number[], x: readonly number[], chunks: readonly Chunk[] = [], target?: readonly number[]): GazeRow[] {
  const fit = new Array<number | null>(t.length).fill(null);
  for (const c of chunks) for (let i = c.i0; i <= c.i1; i++) fit[i] = r3(c.slope * (t[i] as number) + c.icpt);
  return t.map((tt, i) => {
    const xi = x[i] as number;
    const ti = target?.[i];
    return { t: r3(tt), x: Number.isFinite(xi) ? r3(xi) : null, fit: fit[i] ?? null, target: ti !== undefined && Number.isFinite(ti) ? r3(ti) : null };
  });
}

/** Frame-to-frame eye velocity (deg/s); null across gaps. */
export function velocitySeries(t: readonly number[], x: readonly number[]): VelocityRow[] {
  return t.map((tt, i) => {
    if (i === 0) return { t: r3(tt), v: null };
    const a = x[i - 1] as number, b = x[i] as number;
    const dt = tt - (t[i - 1] as number);
    return { t: r3(tt), v: Number.isFinite(a) && Number.isFinite(b) && dt > 0 ? Math.round(((b - a) / dt) * 10) / 10 : null };
  });
}
