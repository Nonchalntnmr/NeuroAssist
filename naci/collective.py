"""The decentralized scientific collective.

Five agents share a blackboard. Each round, every agent sees the messages of earlier rounds and
decides on its own whether to act; there is no planner and no fixed call order (agents in the
same round cannot see each other's messages, so their order does not matter). The run ends when
a round passes with no new message.

Each agent has:
  - its own evidence access, enforced by the board: reading an input it was not granted raises
    AccessDenied (see ACCESS);
  - its own authority: SignalQuality and Skeptic can VETO the measurement, the Skeptic can
    CHALLENGE a claim, the Auditor can refuse to certify it; only PhysiologicalAnalysis makes
    claims and only ContextualMemory reads or writes CI memory;
  - a way to ask for more evidence (EVIDENCE_REQUEST) and to answer such requests.

No one agent decides. A claim is reported only if it is still standing, no measurement veto is
active and the Evidence Auditor certifies it. Every number on the board comes from deterministic
code (naci.neurocore, NeuroAssist's engine); no language model is involved.
"""

from __future__ import annotations

import datetime as dt
import math
import time
from dataclasses import dataclass, field

from evidence_auditor import audit as run_audit, content_hash

from .contract import AgentMessage, SessionRecord
from .memory import CIMemory, naive_baseline
from .neurocore import analyze, median

# Thresholds. Chosen on the dev split only (benchmark/cases/dev.json); see docs/BENCHMARK.md.
Z_CHANGE = 3.0  # |z| beyond which a difference from the personal baseline is called a change
HEAD_RATE = 0.4  # deg/s of head yaw during slow phases that is enough to bias the estimate
HEAD_RANGE = 1.0  # deg: head yaw range over a recording that warrants a robustness test (Skeptic's own check)
ROBUST_MIN = 0.5  # deg/s: an estimate that moves more than max(own 95% half-width, this) under correction is not robust
AGREE_TOL = 0.05  # deg/s: server recomputation must match the device's number
TIMING_TINY = 0.05  # fraction of frame intervals under a quarter of the median interval
MAX_GAP_S = 1.0
MAX_ROUNDS = 16

ACCESS = {
    "signal_quality": {"trace.time", "trace.gaze", "trace.head", "device_record"},
    "contextual_memory": {"ci_memory"},
    "physiology": {"device_record"},
    "skeptic": {"trace.time", "trace.head", "device_record"},
    "auditor": {"device_record"},
}
ROLES = {
    "signal_quality": ("Signal Quality Agent", "Recomputes the measurement from the raw trace and inspects timing, gaps and head coupling. Can veto the measurement."),
    "contextual_memory": ("Contextual Memory Agent", "The only agent that reads or writes CI memory. Builds the personal baseline from trusted, prior sessions and reports conflicts."),
    "physiology": ("Physiological Analysis Agent", "Compares the measurement with the personal baseline and proposes the only claims. Never sees the raw trace."),
    "skeptic": ("Scientific Skeptic Agent", "Looks for alternative explanations, asks for counterfactual re-analyses and challenges claims. Can veto the measurement."),
    "auditor": ("Evidence Auditor Agent", "Certifies only claims backed by intact, adequate, unchallenged evidence (evidence_auditor package)."),
}


class AccessDenied(PermissionError):
    pass


@dataclass
class Evidence:
    id: str
    type: str
    producer: str
    content: dict
    sha256: str
    quality: str = "ok"
    provenance: dict | None = None
    derived_from: list[str] = field(default_factory=list)

    def public(self) -> dict:
        return {"id": self.id, "type": self.type, "producer": self.producer, "sha256": self.sha256, "quality": self.quality,
                "provenance": self.provenance, "derived_from": self.derived_from, "content": self.content}


class Board:
    def __init__(self, run_id: str, target: SessionRecord, audit_log, ci: CIMemory | None, history: list[SessionRecord]):
        self.run_id = run_id
        self.target = target
        self.audit = audit_log
        self.ci = ci
        self._history = history
        self.messages: list[AgentMessage] = []
        self.evidence: dict[str, Evidence] = {}
        self.reads: list[dict] = []
        self._n = 0
        rec = target.model_dump(mode="json", by_alias=True, exclude={"trace"})
        self.device_ev = self.add_evidence("device_record", "neuroassist", rec, provenance=target.provenance.model_dump(),
                                           quality="ok" if target.gate_passed() else "fail")

    # -- inputs, enforced by ACCESS
    def read(self, agent: str, what: str):
        if what not in ACCESS.get(agent, set()):
            raise AccessDenied(f"{agent} may not read {what}")
        self.reads.append({"agent": agent, "input": what})
        tr = self.target.trace
        nan = float("nan")
        if what == "trace.time":
            return list(tr.t)
        if what == "trace.gaze":
            return [nan if v is None else v for v in tr.x]
        if what == "trace.head":
            return None if tr.head is None else [nan if v is None else v for v in tr.head]
        if what == "device_record":
            return self.target
        if what == "ci_memory":
            return self.ci
        raise KeyError(what)

    def history_records(self, agent: str) -> list[SessionRecord]:
        """Raw history, for the no-CI ablation's context agent only."""
        if agent != "contextual_memory":
            raise AccessDenied(f"{agent} may not read history")
        return self._history

    # -- shared outputs
    def add_evidence(self, typ: str, producer: str, content: dict, *, quality: str = "ok", provenance: dict | None = None,
                     derived_from: list[str] | None = None) -> Evidence:
        sha = content_hash(content)
        eid = f"ev_{sha[:16]}"
        ev = Evidence(eid, typ, producer, content, sha, quality, provenance, list(derived_from or []))
        self.evidence[eid] = ev
        self.audit.append(self.target.subject_id, "evidence.add", ev=eid, type=typ, producer=producer, sha256=sha)
        return ev

    def post(self, rnd: int, sender: str, kind: str, topic: str, text: str, body: dict | None = None,
             refs: list[str] | None = None, to: str = "*", reply_to: str | None = None) -> AgentMessage:
        self._n += 1
        m = AgentMessage(id=f"msg_{self._n:03d}", run_id=self.run_id, round=rnd, sender=sender, to=to, kind=kind,
                         topic=topic, text=text[:600], body=body or {}, refs=refs or [], reply_to=reply_to)
        return m

    def visible(self, rnd: int) -> list[AgentMessage]:
        return [m for m in self.messages if m.round < rnd]


def _finite(v) -> bool:
    return v is not None and isinstance(v, (int, float)) and math.isfinite(v)


def _window_slopes(t: list[float], y: list[float], win_s: float = 0.5) -> list[float]:
    """Least-squares slope of y in consecutive windows (finite samples only)."""
    out, i, n = [], 0, len(t)
    while i < n:
        j = i
        while j < n and t[j] - t[i] < win_s:
            j += 1
        pts = [(t[k], y[k]) for k in range(i, j) if _finite(y[k])]
        if len(pts) >= 6:
            mt = sum(p[0] for p in pts) / len(pts)
            my = sum(p[1] for p in pts) / len(pts)
            sxx = sum((p[0] - mt) ** 2 for p in pts)
            if sxx > 0:
                out.append(sum((p[0] - mt) * (p[1] - my) for p in pts) / sxx)
        i = max(j, i + 1)
    return out


# --------------------------------------------------------------------------- agents
class Agent:
    key = ""

    def __init__(self, fault: str | None = None):
        self.fault = fault  # None | "silent" | "byzantine"
        self.name, self.role = ROLES[self.key]

    def step(self, board: Board, rnd: int) -> list[AgentMessage]:
        if self.fault == "silent":
            return []
        return self.act(board, rnd, board.visible(rnd))

    def act(self, board: Board, rnd: int, seen: list[AgentMessage]) -> list[AgentMessage]:
        raise NotImplementedError

    @staticmethod
    def mine(seen, sender):
        return [m for m in seen if m.sender == sender]

    @staticmethod
    def requests_for(seen, me):
        answered = {m.reply_to for m in seen if m.sender == me and m.kind == "EVIDENCE"}
        return [m for m in seen if m.kind == "EVIDENCE_REQUEST" and m.to == me and m.id not in answered]


class SignalQualityAgent(Agent):
    key = "signal_quality"

    def act(self, board, rnd, seen):
        out = []
        if not self.mine(seen, self.key):
            out += self._inspect(board, rnd)
        for req in self.requests_for(seen, self.key):
            out.append(self._counterfactual(board, rnd, req))
        return out

    def _inspect(self, board, rnd):
        t = board.read(self.key, "trace.time")
        x = board.read(self.key, "trace.gaze")
        head = board.read(self.key, "trace.head")
        rec: SessionRecord = board.read(self.key, "device_record")
        a = analyze(t, x)
        flags = []
        # 1. Does the device's number follow from its own trace?
        dev_v = rec.measurement.value
        agrees = (a.passed == rec.gate_passed()) and (not a.passed or (_finite(dev_v) and abs(a.est - dev_v) <= AGREE_TOL))
        if not agrees:
            flags.append({"code": "RECORD_MISMATCH", "severity": "fail",
                          "detail": f"recomputed {'%.3f' % a.est if a.passed else 'no value'} vs device {dev_v}"})
        if not rec.gate_passed():
            failed = [c.id for c in rec.quality.checks if not c.ok]
            flags.append({"code": "DEVICE_GATE", "severity": "fail", "detail": "NeuroAssist gate abstained: " + ", ".join(failed)})
        # 2. Timing integrity.
        dts = [b - a_ for a_, b in zip(t, t[1:])]
        med_dt = median(dts)
        tiny = sum(1 for d in dts if d < 0.25 * med_dt) / max(1, len(dts))
        cv = (sum((d - med_dt) ** 2 for d in dts) / max(1, len(dts))) ** 0.5 / med_dt if med_dt > 0 else float("inf")
        if tiny > TIMING_TINY:
            flags.append({"code": "TIMESTAMPS_BATCHED", "severity": "fail",
                          "detail": f"{tiny:.0%} of frame intervals are under a quarter of the median ({med_dt * 1000:.1f} ms): frames were stamped on arrival, not capture"})
        # 3. Gaps.
        longest, run, prev_t = 0.0, 0, None
        gap_start = None
        for ti, xi in zip(t, x):
            if _finite(xi):
                if gap_start is not None:
                    longest = max(longest, ti - gap_start)
                gap_start = None
            elif gap_start is None:
                gap_start = ti
        valid = sum(1 for v in x if _finite(v)) / len(x)
        if valid < 0.75:
            flags.append({"code": "MISSING_FRAMES", "severity": "fail", "detail": f"{valid:.0%} valid frames, longest gap {longest:.2f} s"})
        elif longest > MAX_GAP_S:
            flags.append({"code": "LONG_GAP", "severity": "concern", "detail": f"longest gap {longest:.2f} s"})
        # 4. Head coupling: head yaw slope inside the slow-phase windows the engine used.
        head_rate = None
        if head is not None and a.chunks:
            hs = []
            for c in a.chunks:
                pts = [(t[i], head[i]) for i in range(c.i0, c.i1 + 1) if _finite(head[i])]
                if len(pts) >= 4:
                    mt = sum(p[0] for p in pts) / len(pts)
                    mh = sum(p[1] for p in pts) / len(pts)
                    sxx = sum((p[0] - mt) ** 2 for p in pts)
                    if sxx > 0:
                        hs.append(sum((p[0] - mt) * (p[1] - mh) for p in pts) / sxx)
            head_rate = median(hs) if hs else None
            if _finite(head_rate) and abs(head_rate) > HEAD_RATE:
                flags.append({"code": "HEAD_COUPLING", "severity": "concern",
                              "detail": f"head yaw moves at {head_rate:+.2f} deg/s inside the slow-phase windows; gaze estimate may include it"})
        if self.fault == "byzantine":
            flags, agrees = [], True
        verdict = "REJECT" if any(f["severity"] == "fail" for f in flags) else "CONCERN" if flags else "ACCEPT"
        content = {"verdict": verdict, "flags": flags,
                   "recompute": {"passed": a.passed, "est": round(a.est, 4) if a.passed else None,
                                 "ci_hw": round(a.ci["hw"], 4) if a.ci else None, "windows": len(a.chunks), "agrees_with_device": agrees},
                   "timing": {"median_dt_ms": round(med_dt * 1000, 2), "tiny_frac": round(tiny, 4), "cv": round(cv, 3)},
                   "gaps": {"valid_frac": round(valid, 4), "longest_gap_s": round(longest, 3)},
                   "head_rate_deg_s": None if head_rate is None or not _finite(head_rate) else round(head_rate, 3)}
        ev = board.add_evidence("quality_report", self.key, content, quality={"ACCEPT": "ok", "CONCERN": "concern", "REJECT": "fail"}[verdict],
                                derived_from=[board.device_ev.id])
        text = {"ACCEPT": "Trace checks pass; the device's number matches my recomputation.",
                "CONCERN": "Usable, with concerns: " + "; ".join(f["detail"] for f in flags),
                "REJECT": "Measurement rejected: " + "; ".join(f["detail"] for f in flags)}[verdict]
        msgs = [board.post(rnd, self.key, "FINDING", "measurement_quality", text, {"verdict": verdict, "codes": [f["code"] for f in flags]}, [ev.id])]
        if verdict == "REJECT":
            msgs.append(board.post(rnd, self.key, "VETO", "measurement", "I veto use of this measurement.", {"codes": [f["code"] for f in flags]}, [ev.id]))
        return msgs

    def _counterfactual(self, board, rnd, req):
        what = req.body.get("request")
        t = board.read(self.key, "trace.time")
        x = board.read(self.key, "trace.gaze")
        head = board.read(self.key, "trace.head")
        if what != "head_corrected" or head is None or self.fault == "byzantine":
            # A byzantine agent stonewalls; an honest one says it cannot.
            content = {"request": what, "available": False}
            ev = board.add_evidence("counterfactual", self.key, content, quality="fail")
            return board.post(rnd, self.key, "EVIDENCE", "counterfactual", "Cannot provide that re-analysis.", content, [ev.id], to=req.sender, reply_to=req.id)
        h0 = median([h for h in head if _finite(h)])
        xc = [xi - (hi - h0) if _finite(xi) and _finite(hi) else float("nan") for xi, hi in zip(x, head)]
        a = analyze(t, xc)
        content = {"request": what, "available": True, "method": "gaze minus head yaw (gain 1), then the NeuroAssist engine",
                   "passed": a.passed, "est": round(a.est, 4) if _finite(a.est) else None,
                   "ci_hw": round(a.ci["hw"], 4) if a.ci else None, "windows": len(a.chunks)}
        ev = board.add_evidence("counterfactual", self.key, content, quality="ok" if a.passed else "concern", derived_from=[board.device_ev.id])
        txt = (f"Head-corrected re-analysis: {a.est:+.2f} deg/s" if a.passed else "Head-corrected re-analysis does not pass the gate.")
        return board.post(rnd, self.key, "EVIDENCE", "counterfactual", txt, content, [ev.id], to=req.sender, reply_to=req.id)


class ContextualMemoryAgent(Agent):
    key = "contextual_memory"

    def __init__(self, fault=None, mode="ci"):
        super().__init__(fault)
        self.mode = mode  # "ci" | "naive"

    def act(self, board, rnd, seen):
        out = []
        rec: SessionRecord = board.target
        if not self.mine(seen, self.key):
            if self.mode == "ci":
                ci: CIMemory = board.read(self.key, "ci_memory")
                b = ci.baseline(rec.subject_id, rec.recorded_at)
                src = "CI TemporalMemory.valid_at + trust ranks + conflict ledger"
            else:
                b = naive_baseline(board.history_records(self.key), rec.recorded_at)
                src = "raw history list (no CI)"
            if self.fault == "byzantine":  # a corrupted memory: only the last record, whatever its source
                b = naive_baseline(board.history_records(self.key), rec.recorded_at, last_only=True)
                b["sufficient"] = True
            b["source"] = src
            ev = board.add_evidence("baseline", self.key, b, quality="ok" if b["sufficient"] else "concern")
            if b["n"]:
                txt = f"Personal baseline from {b['n']} prior session(s): median {b['median']:+.2f} deg/s, spread {b['spread'] or 0:.2f}."
            else:
                txt = "No usable prior sessions for this subject."
            if b["excluded"]:
                txt += f" Excluded {len(b['excluded'])}: " + "; ".join(sorted({e['reason'] for e in b['excluded']})) + "."
            if b["conflicts"]:
                txt += f" CI holds {len(b['conflicts'])} open conflict(s) in this history."
            out.append(board.post(rnd, self.key, "FINDING", "baseline", txt,
                                  {"n": b["n"], "sufficient": b["sufficient"], "conflicts": len(b["conflicts"])}, [ev.id]))
        for req in self.requests_for(seen, self.key):
            base = next((board.evidence[r] for m in self.mine(seen, self.key) for r in m.refs if board.evidence[r].type == "baseline"), None)
            b = base.content if base else {"conflicts": [], "excluded": [], "conflicted_items": []}
            used_items = {u.get("memory_item") for u in b.get("used", [])}
            explained = all(not (set([c["a"], c["b"]]) & used_items) or
                            not (set(b.get("conflicted_items", [])) & used_items) for c in b.get("conflicts", []))
            content = {"request": req.body.get("request"), "conflicts": b.get("conflicts", []),
                       "excluded": b.get("excluded", []), "conflicted_items_in_baseline": sorted(set(b.get("conflicted_items", [])) & used_items),
                       "resolution": ("Every conflicted, lower-trust record was left out of the baseline; CI keeps the "
                                      "higher-trust measurement as current.") if explained else "Conflicted records are inside the baseline."}
            ev = board.add_evidence("conflict_report", self.key, content, derived_from=[base.id] if base else [])
            out.append(board.post(rnd, self.key, "EVIDENCE", "conflicts", content["resolution"], {"explained": explained}, [ev.id],
                                  to=req.sender, reply_to=req.id))
        # After a verdict, record the session and the collective's judgement in CI.
        verdict = next((m for m in seen if m.kind == "VERDICT"), None)
        if verdict and self.mode == "ci" and not any(m.kind == "MEMORY_WRITE" for m in self.mine(seen, self.key)):
            ci: CIMemory = board.read(self.key, "ci_memory")
            accepted = verdict.body.get("decision") in ("CHANGE", "NO_CHANGE", "NO_BASELINE")
            w = ci.ingest(rec, accepted=accepted)
            out.append(board.post(rnd, self.key, "MEMORY_WRITE", "memory",
                                  f"Stored this session in CI as {'accepted' if accepted else 'not accepted'} (item {w['item']}).",
                                  {"item": w["item"], "accepted": accepted, "conflicts": len(w["conflicts"])}))
        return out


class PhysiologyAgent(Agent):
    key = "physiology"

    def act(self, board, rnd, seen):
        out = []
        rec: SessionRecord = board.read(self.key, "device_record")
        q = next((m for m in seen if m.sender == "signal_quality" and m.topic == "measurement_quality"), None)
        base_msg = next((m for m in seen if m.sender == "contextual_memory" and m.topic == "baseline"), None)
        my_claims = [m for m in self.mine(seen, self.key) if m.kind == "CLAIM"]
        if not my_claims:
            if rnd < 1:
                return []  # wait one round for the quality and memory findings
            if q is None and rnd < 2:
                return []
            vetoed = any(m.kind == "VETO" for m in seen)
            if vetoed or not rec.gate_passed():
                if any(m.topic == "assessment" for m in self.mine(seen, self.key)):
                    return []
                return [board.post(rnd, self.key, "FINDING", "assessment", "No assessment: the measurement is vetoed.", {})]
            v, hw = rec.measurement.value, rec.ci_halfwidth()
            refs = [board.device_ev.id] + (q.refs if q else [])
            b = board.evidence[base_msg.refs[0]].content if base_msg else None
            if self.fault == "byzantine":
                claim = {"type": "CHANGE", "z": None}
                text = f"Change from baseline (measured {v:+.2f} deg/s)."
                refs += base_msg.refs if base_msg else []
            elif not b or not b["sufficient"] or not b.get("spread") or b.get("median") is None:
                claim = {"type": "NO_BASELINE", "value": v, "ci_hw": hw}
                text = (f"Slow-phase velocity {v:+.2f} ± {hw:.2f} deg/s. Not compared: "
                        f"{'no' if not b else b['n']} prior trusted session(s), {3} needed.")
                refs += base_msg.refs if base_msg else []
            else:
                sd = math.sqrt(b["spread"] ** 2 + (hw / 1.96) ** 2)
                z = (v - b["median"]) / sd
                typ = "CHANGE" if abs(z) >= Z_CHANGE else "NO_CHANGE"
                claim = {"type": typ, "value": v, "ci_hw": hw, "baseline_median": b["median"], "baseline_spread": b["spread"],
                         "baseline_n": b["n"], "z": round(z, 3)}
                text = (f"{'Change' if typ == 'CHANGE' else 'No change'} from personal baseline: {v:+.2f} deg/s vs "
                        f"{b['median']:+.2f} ± {b['spread']:.2f} (n={b['n']}), z = {z:+.2f}.")
                refs += base_msg.refs
            ev = board.add_evidence("analysis", self.key, claim, derived_from=refs)
            out.append(board.post(rnd, self.key, "CLAIM", claim["type"], text, {"claim": claim}, refs + [ev.id]))
            return out
        # Respond to challenges against a standing claim.
        claim = my_claims[-1]
        withdrawn = any(m.kind == "REVISION" and m.reply_to for m in self.mine(seen, self.key))
        for ch in [m for m in seen if m.kind == "CHALLENGE" and m.reply_to == claim.id]:
            if withdrawn or self.fault == "byzantine":
                continue
            if ch.body.get("ground") == "not_robust":
                out.append(board.post(rnd, self.key, "REVISION", "withdraw",
                                      "Withdrawn: the number does not survive the artifact correction, so the comparison is not supported.",
                                      {"withdraw": True}, ch.refs, reply_to=ch.id))
                withdrawn = True
        return out


class SkepticAgent(Agent):
    key = "skeptic"

    def act(self, board, rnd, seen):
        if self.fault == "byzantine":
            return []
        out = []
        rec: SessionRecord = board.read(self.key, "device_record")
        mine = self.mine(seen, self.key)
        # Independent look at head motion (the Skeptic sees the head channel, not the gaze).
        if not any(m.topic == "head_motion" for m in mine) and rec.gate_passed():
            head = board.read(self.key, "trace.head")
            t = board.read(self.key, "trace.time")
            rate = median(_window_slopes(t, head)) if head else None
            rng = (max(h for h in head if _finite(h)) - min(h for h in head if _finite(h))) if head else None
            content = {"head_rate_deg_s": round(rate, 3) if _finite(rate) else None, "head_range_deg": round(rng, 3) if _finite(rng) else None}
            ev = board.add_evidence("head_motion", self.key, content)
            moved = (_finite(rate) and abs(rate) > HEAD_RATE) or (_finite(rng) and rng > HEAD_RANGE)
            out.append(board.post(rnd, self.key, "FINDING", "head_motion",
                                  f"Head yaw drifts at {rate:+.2f} deg/s (range {rng:.2f}°)." if _finite(rate) else "No head channel.",
                                  content, [ev.id]))
            if moved:
                out.append(board.post(rnd, self.key, "EVIDENCE_REQUEST", "counterfactual",
                                      "Alternative explanation: head motion. Re-estimate with head yaw removed.",
                                      {"request": "head_corrected"}, [ev.id], to="signal_quality"))
        # If Signal Quality reports head coupling and nobody has asked yet, ask.
        q = next((m for m in seen if m.sender == "signal_quality" and m.topic == "measurement_quality"), None)
        asked = any(m.kind == "EVIDENCE_REQUEST" and m.topic == "counterfactual" for m in mine + out)
        if q and "HEAD_COUPLING" in q.body.get("codes", []) and not asked and rec.gate_passed():
            out.append(board.post(rnd, self.key, "EVIDENCE_REQUEST", "counterfactual",
                                  "Signal Quality reports head coupling. Re-estimate with head yaw removed.",
                                  {"request": "head_corrected"}, q.refs, to="signal_quality"))
        claim = next((m for m in reversed(seen) if m.kind == "CLAIM"), None)
        cf = next((m for m in seen if m.kind == "EVIDENCE" and m.topic == "counterfactual" and m.to == self.key), None)
        req_open = any(m.kind == "EVIDENCE_REQUEST" and m.topic == "counterfactual" for m in mine) and cf is None
        # Robustness test of the measurement under the counterfactual.
        if cf and rec.gate_passed() and not any(m.topic == "robustness" or m.kind == "VETO" for m in mine):
            hw = rec.ci_halfwidth()
            thr = max(hw if _finite(hw) else 0, ROBUST_MIN)
            if not cf.body.get("available"):
                out.append(board.post(rnd, self.key, "VETO", "measurement",
                                      "The head-motion explanation could not be tested; I do not accept the number.", {"ground": "untestable"}, cf.refs))
                out.append(board.post(rnd, self.key, "FINDING", "robustness", "Untestable.", {}))
            else:
                d = abs((cf.body.get("est") if cf.body.get("passed") else float("inf")) - rec.measurement.value)
                if d > thr:
                    out.append(board.post(rnd, self.key, "VETO", "measurement",
                                          f"Not robust: removing head motion moves the estimate by {d:.2f} deg/s (limit {thr:.2f}). A tracking artifact explains the number.",
                                          {"ground": "not_robust", "delta": round(d, 3) if _finite(d) else None, "limit": round(thr, 3)}, cf.refs))
                    if claim:
                        out.append(board.post(rnd, self.key, "CHALLENGE", claim.topic,
                                              "This claim rests on a number that a tracking artifact explains.", {"ground": "not_robust"}, cf.refs, reply_to=claim.id))
                else:
                    out.append(board.post(rnd, self.key, "FINDING", "robustness",
                                          f"Robust: removing head motion moves the estimate by {d:.2f} deg/s (limit {thr:.2f}).", {"delta": round(d, 3)}, cf.refs))
        # Challenge comparisons made against a history that has conflicts, until memory explains them.
        if claim and claim.topic in ("CHANGE", "NO_CHANGE"):
            base_msg = next((m for m in seen if m.sender == "contextual_memory" and m.topic == "baseline"), None)
            nconf = base_msg.body.get("conflicts", 0) if base_msg else 0
            if nconf and not any(m.kind == "CHALLENGE" and m.body.get("ground") == "conflicts" for m in mine):
                out.append(board.post(rnd, self.key, "CHALLENGE", claim.topic,
                                      f"The history has {nconf} open conflict(s). Show that no conflicted record is inside the baseline.",
                                      {"ground": "conflicts"}, base_msg.refs, reply_to=claim.id))
                out.append(board.post(rnd, self.key, "EVIDENCE_REQUEST", "conflicts", "Explain the conflicts.",
                                      {"request": "conflict_resolution"}, base_msg.refs, to="contextual_memory"))
            ans = next((m for m in seen if m.kind == "EVIDENCE" and m.topic == "conflicts" and m.to == self.key), None)
            ch = next((m for m in mine if m.kind == "CHALLENGE" and m.body.get("ground") == "conflicts"), None)
            if ans and ch and not any(m.kind == "RESOLVE" and m.reply_to == ch.id for m in mine):
                if ans.body.get("explained"):
                    out.append(board.post(rnd, self.key, "RESOLVE", "conflicts",
                                          "Resolved: conflicted, lower-trust records were excluded. The claim must disclose them.", {}, ans.refs, reply_to=ch.id))
            # A comparison needs enough prior sessions; count them myself rather than trust the flag.
            b = board.evidence[base_msg.refs[0]].content if base_msg else None
            if b is not None and b["n"] < b.get("min_n", 3) and not any(m.body.get("ground") == "baseline" for m in mine):
                out.append(board.post(rnd, self.key, "CHALLENGE", claim.topic,
                                      f"Only {b['n']} prior session(s) behind this comparison; {b.get('min_n', 3)} are needed.",
                                      {"ground": "baseline"}, base_msg.refs, reply_to=claim.id))
            # Re-derive the claim from the evidence it cites.
            if b is not None and b["n"] and b["spread"] and rec.gate_passed() and not any(m.body.get("ground") == "inconsistent" for m in mine):
                hw = rec.ci_halfwidth()
                z = (rec.measurement.value - b["median"]) / math.sqrt(b["spread"] ** 2 + (hw / 1.96) ** 2)
                expect = "CHANGE" if abs(z) >= Z_CHANGE else "NO_CHANGE"
                if expect != claim.topic:
                    out.append(board.post(rnd, self.key, "CHALLENGE", claim.topic,
                                          f"The claim does not follow from its own evidence: I get z = {z:+.1f}, which means {expect}.",
                                          {"ground": "inconsistent", "z": round(z, 3)}, base_msg.refs, reply_to=claim.id))
        _ = req_open
        return out


class AuditorAgent(Agent):
    key = "auditor"

    def act(self, board, rnd, seen):
        if any(m.kind == "VERDICT" for m in seen) or rnd < 2:
            return []
        # Wait until the previous round was quiet and no evidence request is unanswered.
        last = [m for m in seen if m.round == rnd - 1]
        answered = {m.reply_to for m in seen if m.kind == "EVIDENCE"}
        pending = [m for m in seen if m.kind == "EVIDENCE_REQUEST" and m.id not in answered]
        if last and rnd < MAX_ROUNDS - 1:
            return []
        if pending and rnd < MAX_ROUNDS - 1:
            return []
        rep, decision, claim = self.certify(board, seen)
        refs = [r for s in rep["supported"] for r in s["evidence"]]
        txt = {"REPORT": f"Certified: {claim.text}" if claim else "Certified.", "ABSTAIN": "Abstain: " + "; ".join(rep["reasons"] + [r for u in rep["unsupported"] for r in u["reasons"]][:3]),
               "REMEASURE": "Remeasure: " + "; ".join(rep["reasons"])}[rep["recommendation"]]
        ev = board.add_evidence("audit_report", self.key, rep)
        return [board.post(rnd, self.key, "VERDICT", "verdict", txt, {"decision": decision, "recommendation": rep["recommendation"]}, refs + [ev.id])]

    def certify(self, board, seen):
        claims = [m for m in seen if m.kind == "CLAIM"]
        withdrawn = {m.reply_to for m in seen if m.kind == "REVISION" and m.body.get("withdraw")}
        # A REVISION replies to the challenge; find which claim that challenge targeted.
        ch_target = {m.id: m.reply_to for m in seen if m.kind == "CHALLENGE"}
        withdrawn_claims = {ch_target.get(w) for w in withdrawn}
        standing = [c for c in claims if c.id not in withdrawn_claims]
        resolved = {m.reply_to for m in seen if m.kind == "RESOLVE"}
        challenges = [{"id": m.id, "target_claim": m.reply_to, "by": m.sender, "reason": m.text,
                       "status": "resolved" if m.id in resolved else "open"} for m in seen if m.kind == "CHALLENGE"]
        vetoes = [m for m in seen if m.kind == "VETO"]
        lifted = {m.reply_to for m in seen if m.kind == "LIFT_VETO"}
        active = [v for v in vetoes if v.id not in lifted]
        quality = {"status": "fail" if active else "ok", "reasons": [f"{v.sender}: {v.text}" for v in active]}
        q = next((m for m in seen if m.sender == "signal_quality" and m.topic == "measurement_quality"), None)
        if not active and q and q.body.get("verdict") == "CONCERN":
            quality["status"] = "concern"
        if q is None and not active:
            quality = {"status": "fail", "reasons": ["no independent quality inspection on record"]}
        requires = {"CHANGE": ["device_record", "quality_report", "baseline"], "NO_CHANGE": ["device_record", "quality_report", "baseline"],
                    "NO_BASELINE": ["device_record", "quality_report"]}
        obs = {"schema": "evidence-auditor.observation/1",
               "claims": [{"id": c.id, "statement": c.text, "type": c.topic, "evidence": c.refs, "requires": requires.get(c.topic, [])} for c in standing],
               "evidence": [e.public() for e in board.evidence.values()],
               "challenges": challenges, "quality": quality}
        if q is not None and "HEAD_COUPLING" in q.body.get("codes", []):
            # A concern must be tested before a claim that rests on the measurement is reported.
            cf_refs = [r for m in seen if m.kind == "EVIDENCE" and m.topic == "counterfactual" for r in m.refs]
            for c in obs["claims"]:
                c["requires"] = c["requires"] + ["counterfactual"]
                c["evidence"] = c["evidence"] + cf_refs
        rep = run_audit(obs)
        if self.fault == "byzantine":  # rubber stamp
            rep = {**rep, "recommendation": "REPORT" if standing else rep["recommendation"],
                   "supported": [{"claim_id": c.id, "statement": c.text, "type": c.topic, "evidence": c.refs, "caveats": [], "disclose": []} for c in standing],
                   "unsupported": []}
        claim = None
        if rep["recommendation"] == "REPORT":
            sup = {s["claim_id"] for s in rep["supported"]}
            claim = next((c for c in reversed(standing) if c.id in sup), None)
        decision = claim.topic if claim else "ABSTAIN"
        # Vetoes and open challenges are binding whatever the auditor says.
        open_on_claim = claim is not None and any(c["status"] == "open" and c["target_claim"] == claim.id for c in challenges)
        if active or open_on_claim:
            decision, claim = "ABSTAIN", None
        return rep, decision, claim


AGENTS = [SignalQualityAgent, ContextualMemoryAgent, PhysiologyAgent, SkepticAgent, AuditorAgent]


@dataclass
class RunResult:
    decision: str
    variant: str
    messages: list[dict]
    evidence: list[dict]
    audit: dict
    latency_ms: float
    rounds: int
    access_log: list[dict]
    artifact_flagged: bool
    artifact_causes: list[str]
    baseline_ids: list[str] | None
    claim: dict | None
    ci_calls: list[dict]
    vetoes: list[dict]
    agents: list[dict]

    def to_json(self) -> dict:
        return self.__dict__


def run_collective(target: SessionRecord, history: list[SessionRecord], variant: str = "ci",
                   faults: dict[str, str] | None = None) -> RunResult:
    """variant: "ci" (memory through CI), "naive" (raw history, no CI), "none" (no historical context)."""
    t0 = time.perf_counter()
    faults = faults or {}
    ci = CIMemory()
    for h in sorted(history, key=lambda r: r.recorded_at):
        ci.ingest(h)  # history is written before the run, as NeuroAssist would have synced it
    run_id = f"run_{content_hash({'t': target.session_id, 'v': variant, 'f': faults})[:12]}"
    board = Board(run_id, target, ci.audit, ci if variant == "ci" else None, history)
    agents: list[Agent] = []
    for cls in AGENTS:
        if cls is ContextualMemoryAgent:
            if variant == "none":
                continue
            agents.append(cls(faults.get(cls.key), mode="ci" if variant == "ci" else "naive"))
        else:
            agents.append(cls(faults.get(cls.key)))
    if variant != "ci":
        ACCESS_NAIVE = {"history"}
        _ = ACCESS_NAIVE
    rnd = 0
    quiet = 0
    while rnd < MAX_ROUNDS:
        new: list[AgentMessage] = []
        for ag in agents:
            new += ag.step(board, rnd)
        board.messages += new
        quiet = quiet + 1 if not new else 0
        rnd += 1
        if quiet >= 2:
            break
    verdict = next((m for m in board.messages if m.kind == "VERDICT"), None)
    decision = verdict.body["decision"] if verdict else "ABSTAIN"
    q = next((m for m in board.messages if m.sender == "signal_quality" and m.topic == "measurement_quality"), None)
    causes = list(q.body.get("codes", [])) if q else []
    if any(m.kind == "VETO" and m.sender == "skeptic" for m in board.messages):
        causes.append("NOT_ROBUST_TO_HEAD_MOTION")
    base = next((board.evidence[r] for m in board.messages if m.topic == "baseline" for r in m.refs), None)
    claim_msg = next((m for m in board.messages if m.kind == "CLAIM"), None)
    lat = (time.perf_counter() - t0) * 1000
    return RunResult(
        decision=decision, variant=variant,
        messages=[m.model_dump(by_alias=True) for m in board.messages],
        evidence=[e.public() for e in board.evidence.values()],
        audit=ci.audit_summary(), latency_ms=round(lat, 2), rounds=rnd, access_log=board.reads,
        artifact_flagged=bool([c for c in causes if c not in ("LONG_GAP",)]), artifact_causes=causes,
        baseline_ids=[u["session_id"] for u in base.content["used"]] if base else None,
        claim=claim_msg.body.get("claim") if claim_msg else None, ci_calls=ci.calls,
        vetoes=[{"by": m.sender, "text": m.text} for m in board.messages if m.kind == "VETO"],
        agents=[{"key": a.key, "name": a.name, "role": a.role, "access": sorted(ACCESS[a.key]), "fault": a.fault} for a in agents],
    )
