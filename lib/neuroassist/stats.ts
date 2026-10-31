export type Rand = () => number;

export function rng(seed: number): Rand {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function gauss(r: Rand): number {
  let u = 0;
  while (u === 0) u = r();
  const v = r();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

export function median(a: readonly number[]): number {
  if (!a.length) return NaN;
  const b = [...a].sort((p, q) => p - q);
  const m = b.length >> 1;
  return b.length % 2 ? (b[m] as number) : ((b[m - 1] as number) + (b[m] as number)) / 2;
}

export function percentile(a: readonly number[], q: number): number {
  if (!a.length) return NaN;
  const b = [...a].sort((p, r) => p - r);
  const pos = (b.length - 1) * q;
  const lo = Math.floor(pos);
  const hi = Math.ceil(pos);
  return (b[lo] as number) + ((b[hi] as number) - (b[lo] as number)) * (pos - lo);
}

export function mad(a: readonly number[]): number {
  const m = median(a);
  return median(a.map((v) => Math.abs(v - m)));
}

/** Running median filter. NaN samples stay NaN and are ignored inside windows. */
export function medianFilter(x: readonly number[], window: number): number[] {
  if (window <= 1) return [...x];
  const h = window >> 1;
  return x.map((v, i) => {
    if (!Number.isFinite(v)) return NaN;
    const w: number[] = [];
    for (let j = Math.max(0, i - h); j <= Math.min(x.length - 1, i + h); j++) {
      const u = x[j] as number;
      if (Number.isFinite(u)) w.push(u);
    }
    return median(w);
  });
}

/**
 * Distribution-free 95% confidence interval for a median: the order statistics
 * [x_(k), x_(n-k+1)] with the largest k such that P(Binomial(n, 1/2) < k) <= 0.025.
 * Coverage is at least 95% for independent samples from any continuous distribution.
 * Returns null below `minN` samples (and always for n < 6, where no such k exists).
 */
export function medianCI(values: readonly number[], minN: number): { lo: number; hi: number; hw: number } | null {
  const n = values.length;
  if (n < Math.max(minN, 6)) return null;
  const b = [...values].sort((p, q) => p - q);
  // Cumulative binomial(n, 0.5) probabilities.
  let k = 0;
  let cdf = 0;
  let pmf = Math.pow(0.5, n); // P(X = 0)
  for (let j = 0; j < n; j++) {
    if (cdf + pmf > 0.025) break;
    cdf += pmf;
    k = j + 1; // P(X < k) = cdf <= 0.025
    pmf = (pmf * (n - j)) / (j + 1);
  }
  if (k < 1) return null;
  const lo = b[k - 1] as number;
  const hi = b[n - k] as number;
  return { lo, hi, hw: (hi - lo) / 2 };
}
