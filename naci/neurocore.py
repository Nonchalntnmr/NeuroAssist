"""Python port of NeuroAssist's signal engine (lib/neuroassist/analyze.ts, stats.ts, constants.ts).

Why a port: the collective must be able to recompute a measurement from the raw trace on the
server (NeuroAssist's own rule: never trust a number the client sends) and to run
counterfactuals (re-estimate with suspect frames removed). The TypeScript engine stays the
source of truth. tests/test_neurocore_parity.py checks this port against outputs of the
TypeScript engine on every held-out trace (scripts/gen-parity.ts) to 1e-9.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

GATE = {
    "minValid": 0.75,
    "minFps": 20.0,
    "maxNoise": 0.45,
    "minChunks": 8,
    "maxCI": 1.5,
    "maxResidualRatio": 1.25,
}
PROCESSING = {
    "smoothWindow": 3,
    "minFastPhaseDev": 15.0,
    "fastPhaseK": 3.0,
    "localMedianSec": 0.5,
    "fastPhaseGuard": 1,
    "maxWindowSec": 0.5,
    "minWindowSec": 0.12,
}
NAN = float("nan")


def _fin(v) -> bool:
    return v is not None and isinstance(v, (int, float)) and math.isfinite(v)


def median(a: list[float]) -> float:
    if not a:
        return NAN
    b = sorted(a)
    m = len(b) >> 1
    return b[m] if len(b) % 2 else (b[m - 1] + b[m]) / 2


def mad(a: list[float]) -> float:
    m = median(a)
    return median([abs(v - m) for v in a])


def median_ci(values: list[float], min_n: int):
    n = len(values)
    if n < max(min_n, 6):
        return None
    b = sorted(values)
    k, cdf, pmf = 0, 0.0, 0.5**n
    for j in range(n):
        if cdf + pmf > 0.025:
            break
        cdf += pmf
        k = j + 1
        pmf = pmf * (n - j) / (j + 1)
    if k < 1:
        return None
    lo, hi = b[k - 1], b[n - k]
    return {"lo": lo, "hi": hi, "hw": (hi - lo) / 2}


@dataclass
class Chunk:
    i0: int
    i1: int
    slope: float
    icpt: float


@dataclass
class Check:
    id: str
    label: str
    value: float
    ok: bool


@dataclass
class Analysis:
    n: int
    dur: float
    fps: float
    valid_frac: float
    sigma: float
    fast_phase_threshold: float
    fast_phases: int
    chunks: list[Chunk]
    residual_rms: float
    est: float
    ci: dict | None
    checks: list[Check] = field(default_factory=list)
    passed: bool = False

    def check(self, cid: str) -> Check:
        return next(c for c in self.checks if c.id == cid)


def _robust_sigma(x: list[float], use) -> float:
    d2 = []
    for i in range(1, len(x) - 1):
        a, b, c = x[i - 1], x[i], x[i + 1]
        if use(i) and math.isfinite(a) and math.isfinite(b) and math.isfinite(c):
            d2.append(c - 2 * b + a)
    return (1.4826 * mad(d2)) / math.sqrt(6) if len(d2) > 5 else NAN


def _segment(t, x, vel, local_med, thr, is_break, excluded):
    n = len(t)
    is_fast = [False] * n
    fast_phases = 0
    for i in range(1, n):
        v = vel[i]
        if math.isfinite(v) and abs(v - local_med[i]) > thr:
            is_fast[i] = True
            if not is_fast[i - 1]:
                fast_phases += 1
    raw_runs = []
    rs = -1
    for i in range(n):
        if not math.isfinite(x[i]) or excluded[i]:
            if rs >= 0:
                raw_runs.append((rs, i - 1))
            rs = -1
            continue
        if rs < 0:
            rs = i
            continue
        if is_fast[i] or is_break[i]:
            raw_runs.append((rs, i - 1))
            rs = i
    if rs >= 0:
        raw_runs.append((rs, n - 1))
    g = PROCESSING["fastPhaseGuard"]

    def cut(i):
        return is_fast[i] or is_break[i]

    runs = []
    for a0, b0 in raw_runs:
        a = a0 + g if a0 > 0 and cut(a0) else a0
        b = b0 - g if b0 < n - 1 and cut(b0 + 1) else b0
        if b >= a:
            runs.append((a, b))
    return runs, fast_phases


def _smooth_within_runs(x, runs, win):
    out = list(x)
    if win <= 1:
        return out
    h = win >> 1
    for a, b in runs:
        for i in range(a + h, b - h + 1):
            out[i] = median([x[j] for j in range(i - h, i + h + 1)])
    return out


def analyze(t: list[float], x_raw: list[float | None], smooth: bool = True, gate: dict | None = None) -> Analysis:
    """Same algorithm, same order of floating-point operations as analyze.ts."""
    x_raw = [float(v) if _fin(v) else NAN for v in x_raw]
    t = [float(v) for v in t]
    n = len(t)
    dts = [t[i] - t[i - 1] for i in range(1, n)]
    fps = 1 / median(dts) if dts else NAN
    valid = sum(1 for v in x_raw if math.isfinite(v))
    valid_frac = valid / n if n else 0.0
    G = {**GATE, **(gate or {})}

    sigma_all = _robust_sigma(x_raw, lambda i: True)
    vel = [NAN] * n
    for i in range(1, n):
        a, b = x_raw[i - 1], x_raw[i]
        if math.isfinite(a) and math.isfinite(b):
            vel[i] = (b - a) / (t[i] - t[i - 1])
    half = max(2, round_half_up(PROCESSING["localMedianSec"] * fps / 2))
    local_med = []
    for i in range(n):
        w = [vel[j] for j in range(max(1, i - half), min(n - 1, i + half) + 1) if math.isfinite(vel[j])]
        local_med.append(median(w))

    def threshold_for(sg):
        return max(PROCESSING["minFastPhaseDev"], PROCESSING["fastPhaseK"] * math.sqrt(2) * (sg if math.isfinite(sg) else 0) * fps)

    is_break = [False] * n
    excluded = [False] * n
    runs, _ = _segment(t, x_raw, vel, local_med, threshold_for(sigma_all), is_break, excluded)
    inside = [False] * n
    for a, b in runs:
        for i in range(a, b + 1):
            inside[i] = True
    sigma_seg = _robust_sigma(x_raw, lambda i: inside[i - 1] and inside[i] and inside[i + 1])
    sigma = sigma_seg if math.isfinite(sigma_seg) else sigma_all
    thr = threshold_for(sigma)
    runs, fast_phases = _segment(t, x_raw, vel, local_med, thr, is_break, excluded)

    win = 1 if not smooth else PROCESSING["smoothWindow"]
    x = _smooth_within_runs(x_raw, runs, win)

    max_n = max(4, round_half_up(PROCESSING["maxWindowSec"] * fps))
    chunks: list[Chunk] = []
    ss_res, dof = 0.0, 0
    for a, b in runs:
        s = a
        while s <= b:
            e = min(b, s + max_n - 1)
            if e - s + 1 < 4 or t[e] - t[s] < PROCESSING["minWindowSec"]:
                s += max_n
                continue
            st = sx = stt = stx = 0.0
            m = e - s + 1
            for i in range(s, e + 1):
                ti, xi = t[i], x[i]
                st += ti
                sx += xi
                stt += ti * ti
                stx += ti * xi
            slope = (m * stx - st * sx) / (m * stt - st * st)
            icpt = (sx - slope * st) / m
            chunks.append(Chunk(s, e, slope, icpt))
            for i in range(s, e + 1):
                ss_res += (x_raw[i] - (slope * t[i] + icpt)) ** 2
            dof += m - 2
            s += max_n
    residual_rms = math.sqrt(ss_res / dof) if dof > 0 else NAN
    residual_ratio = residual_rms / sigma if math.isfinite(sigma) and sigma > 0 else NAN
    slopes = [c.slope for c in chunks]
    est = median(slopes)
    ci = median_ci(slopes, G["minChunks"])
    hw = ci["hw"] if ci else NAN
    dur = t[-1] - t[0] if n else 0.0
    checks = [
        Check("valid", "Valid frames", valid_frac, valid_frac >= G["minValid"]),
        Check("fps", "Frame rate", fps, fps >= G["minFps"]),
        Check("noise", "Tracking noise", sigma, math.isfinite(sigma) and sigma <= G["maxNoise"]),
        Check("chunks", "Clean slow-phase windows", len(chunks), len(chunks) >= G["minChunks"]),
        Check("linearity", "Slow-phase fit (residual / noise)", residual_ratio,
              math.isfinite(residual_ratio) and residual_ratio <= G["maxResidualRatio"]),
        Check("ci", "Uncertainty (95% half-width)", hw, math.isfinite(hw) and hw <= G["maxCI"]),
    ]
    return Analysis(n, dur, fps, valid_frac, sigma, thr, fast_phases, chunks, residual_rms, est, ci, checks,
                    all(c.ok for c in checks))


def round_half_up(v: float) -> int:
    """JavaScript Math.round: halves round toward +infinity (Python's round() is banker's)."""
    return math.floor(v + 0.5)
