"""Simpler systems the collective is compared against. Same inputs, same thresholds where they apply."""

from __future__ import annotations

import math
import time

from .collective import AGREE_TOL, HEAD_RATE, ROBUST_MIN, Z_CHANGE
from .contract import SessionRecord
from .memory import CIMemory, naive_baseline
from .neurocore import analyze, median


def _out(decision, t0, flagged=False, causes=None, baseline_ids=None, claim=None):
    return {"decision": decision, "latency_ms": round((time.perf_counter() - t0) * 1000, 2), "artifact_flagged": flagged,
            "artifact_causes": causes or [], "baseline_ids": baseline_ids, "claim": claim, "evidence": [], "messages": []}


GATE_CAUSE = {"valid": "MISSING_FRAMES", "fps": "TIMESTAMPS", "noise": "NOISE"}


def deterministic(target: SessionRecord, history: list[SessionRecord]) -> dict:
    """NeuroAssist as it ships (its quality gate) plus the simplest comparison: the previous visit.
    A change is called when the two 95% intervals do not overlap."""
    t0 = time.perf_counter()
    if not target.gate_passed():
        causes = [GATE_CAUSE.get(c.id, "GATE_" + c.id.upper()) for c in target.quality.checks if not c.ok]
        return _out("ABSTAIN", t0, True, causes)
    prev = naive_baseline(history, target.recorded_at, last_only=True)
    if not prev["n"]:
        return _out("NO_BASELINE", t0, baseline_ids=[])
    p = next(r for r in history if r.session_id == prev["used"][0]["session_id"])
    m = target.measurement
    overlap = not (m.ci_low > p.measurement.ci_high or m.ci_high < p.measurement.ci_low)
    return _out("NO_CHANGE" if overlap else "CHANGE", t0, baseline_ids=[p.session_id])


def single_agent(target: SessionRecord, history: list[SessionRecord]) -> dict:
    """One analyst with every input in one pass: reads the device verdict and the full history list,
    computes a z-score against all prior measured sessions. No independent trace inspection, no
    challenge, no memory semantics (every record counts the same)."""
    t0 = time.perf_counter()
    if not target.gate_passed():
        causes = [GATE_CAUSE.get(c.id, "GATE_" + c.id.upper()) for c in target.quality.checks if not c.ok]
        return _out("ABSTAIN", t0, True, causes)
    b = naive_baseline(history, target.recorded_at)
    ids = [u["session_id"] for u in b["used"]]
    if not b["sufficient"]:
        return _out("NO_BASELINE", t0, baseline_ids=ids)
    hw = target.ci_halfwidth()
    z = (target.measurement.value - b["median"]) / math.sqrt(b["spread"] ** 2 + (hw / 1.96) ** 2)
    return _out("CHANGE" if abs(z) >= Z_CHANGE else "NO_CHANGE", t0, baseline_ids=ids, claim={"z": round(z, 3)})


def monolith(target: SessionRecord, history: list[SessionRecord], fault: str | None = None) -> dict:
    """Ablation: every check the collective runs, in one sequential function, with CI memory, but no
    agents, no messages and no evidence ledger. Answers: is the gain from the checks or from the
    organisation?

    `fault` corrupts one stage, as the fault experiment does to one agent: "quality" (stage passes
    everything), "memory" (baseline = last record, flagged sufficient), "analysis" (always CHANGE),
    "robustness" (head test skipped). A crashed stage raises, so it has no "silent" mode."""
    t0 = time.perf_counter()
    tr = target.trace
    t = list(tr.t)
    x = [float("nan") if v is None else v for v in tr.x]
    head = None if tr.head is None else [float("nan") if v is None else v for v in tr.head]
    a = analyze(t, x)
    causes = []
    if not target.gate_passed():
        causes.append("DEVICE_GATE")
    if a.passed != target.gate_passed() or (a.passed and abs(a.est - target.measurement.value) > AGREE_TOL):
        causes.append("RECORD_MISMATCH")
    dts = [b - a_ for a_, b in zip(t, t[1:])]
    md = median(dts)
    if sum(1 for d in dts if d < 0.25 * md) / max(1, len(dts)) > 0.05:
        causes.append("TIMESTAMPS_BATCHED")
    if sum(1 for v in x if math.isfinite(v)) / len(x) < 0.75:
        causes.append("MISSING_FRAMES")
    if fault == "quality":
        causes = []
        if not target.gate_passed():
            return _out("ABSTAIN", t0)  # no value to report at all
    if causes:
        return _out("ABSTAIN", t0, True, causes)
    if head is not None and a.chunks and fault != "robustness":
        hs = []
        for c in a.chunks:
            pts = [(t[i], head[i]) for i in range(c.i0, c.i1 + 1) if math.isfinite(head[i])]
            if len(pts) >= 4:
                mt = sum(p[0] for p in pts) / len(pts)
                mh = sum(p[1] for p in pts) / len(pts)
                sxx = sum((p[0] - mt) ** 2 for p in pts)
                if sxx > 0:
                    hs.append(sum((p[0] - mt) * (p[1] - mh) for p in pts) / sxx)
        hr = median(hs) if hs else float("nan")
        if math.isfinite(hr) and abs(hr) > HEAD_RATE:
            h0 = median([h for h in head if math.isfinite(h)])
            ac = analyze(t, [xi - (hi - h0) for xi, hi in zip(x, head)])
            lim = max(target.ci_halfwidth(), ROBUST_MIN)
            if not ac.passed or abs(ac.est - target.measurement.value) > lim:
                return _out("ABSTAIN", t0, True, ["HEAD_COUPLING", "NOT_ROBUST_TO_HEAD_MOTION"])
            causes.append("HEAD_COUPLING")
    ci = CIMemory()
    for h in sorted(history, key=lambda r: r.recorded_at):
        ci.ingest(h)
    b = ci.baseline(target.subject_id, target.recorded_at)
    if fault == "memory":
        b = naive_baseline(history, target.recorded_at, last_only=True)
        b["sufficient"], b["spread"] = True, b["spread"] or 0.15
    ids = [u["session_id"] for u in b["used"]]
    if not b["sufficient"]:
        return _out("NO_BASELINE", t0, bool(causes), causes, ids)
    if fault == "analysis":
        return _out("CHANGE", t0, bool(causes), causes, ids)
    hw = target.ci_halfwidth()
    z = (target.measurement.value - b["median"]) / math.sqrt(b["spread"] ** 2 + (hw / 1.96) ** 2)
    return _out("CHANGE" if abs(z) >= Z_CHANGE else "NO_CHANGE", t0, bool(causes), causes, ids, {"z": round(z, 3)})
