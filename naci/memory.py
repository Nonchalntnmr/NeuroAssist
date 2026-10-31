"""The collective's memory is CI's memory (parent B), used through its public classes.

- pcim.memory.TemporalMemory: bitemporal assertions. Each session is an episode valid from the
  time it was recorded; `valid_at(t)` answers "what did we know had happened before t", so a
  session can never be compared against measurements taken after it.
- Trust ranks decide authority. A NeuroAssist measurement is IMPORTED (a granted device source);
  an exported file of unknown origin is UNTRUSTED. When a lower-trust record contradicts the
  keyed latest observation, CI keeps the trusted value and opens a conflict instead of
  overwriting it.
- pcim.sovereignty.consent.ConsentLedger: every source needs a store grant before CI accepts
  its records.
- pcim.sovereignty.audit.AuditLog: every write, grant and evidence item goes onto CI's
  hash-chained audit log; `verify()` recomputes the chain.
Records are encrypted at rest per item by CI's Store (AES-GCM, ephemeral key per run).
"""

from __future__ import annotations

import datetime as dt
import math

from pcim.embed import HashingEmbedder
from pcim.memory import CONFLICT_FLAG, TemporalMemory
from pcim.sovereignty.audit import AuditLog
from pcim.sovereignty.consent import ConsentLedger
from pcim.sovereignty.crypto import KeyRing
from pcim.store import Store
from pcim.types import Sensitivity, Trust

from .contract import SessionRecord

TRUST_FOR_LABEL = {"REAL": Trust.IMPORTED, "SYNTHETIC": Trust.IMPORTED, "PRERECORDED": Trust.UNTRUSTED}
PROTOCOL_TAG = "protocol:FIXATION"
MIN_BASELINE = 3
SPREAD_FLOOR = 0.15  # deg/s: below this, day-to-day spread is not resolvable by the instrument


def _source(rec: SessionRecord) -> str:
    return "neuroassist" if rec.provenance.label != "PRERECORDED" else "export"


class CIMemory:
    def __init__(self) -> None:
        self.store = Store(":memory:", KeyRing.ephemeral())
        self.audit = AuditLog(self.store)
        self.ledger = ConsentLedger(self.store, self.audit)
        self.memory = TemporalMemory(self.store, HashingEmbedder(), self.audit, self.ledger)
        self.calls: list[dict] = []  # which CI calls the collective made, for the evidence view

    def _subject(self, sid: str) -> None:
        if self.store.get_user(sid) is None:
            self.store.create_user(sid)
            for src in ("neuroassist", "export"):
                self.ledger.grant(sid, src, "store", max_sensitivity=Sensitivity.SENSITIVE,
                                  note="NeuroAssist x CI research prototype")

    def ingest(self, rec: SessionRecord, accepted: bool | None = None) -> dict:
        """Write one session into CI. `accepted` is the collective's verdict on it (None: not judged)."""
        self._subject(rec.subject_id)
        trust = TRUST_FOR_LABEL[rec.provenance.label]
        m = rec.measurement
        value = {"session_id": rec.session_id, "status": m.status, "value": m.value, "ci_low": m.ci_low,
                 "ci_high": m.ci_high, "engine": rec.provenance.engine, "label": rec.provenance.label,
                 "accepted": accepted}
        content = (f"FIXATION session {rec.session_id}: slow-phase velocity "
                   f"{'%.3f deg/s' % m.value if m.value is not None else 'not measured (gate abstained)'}")
        tags = (PROTOCOL_TAG, f"session:{rec.session_id}", f"label:{rec.provenance.label}",
                "measured" if m.status == "MEASURED" else "abstained")
        ep = self.memory.remember(rec.subject_id, content, kind="episode", source=_source(rec), trust=trust,
                                  sensitivity=Sensitivity.SENSITIVE, valid_from=rec.recorded_at, value=value,
                                  tags=tags, provenance={"session_id": rec.session_id, "engine": rec.provenance.engine})
        conflicts: list[str] = []
        if m.status == "MEASURED" and accepted is not False:
            res = self.memory.remember(rec.subject_id, f"Latest FIXATION slow-phase velocity: {m.value:.3f} deg/s",
                                       kind="fact", key="FIXATION/latest_spv", value=round(m.value, 4),
                                       source=_source(rec), trust=trust, sensitivity=Sensitivity.SENSITIVE,
                                       valid_from=rec.recorded_at, parents=(ep.item.id,),
                                       provenance={"session_id": rec.session_id})
            conflicts = res.conflicts
        self.calls.append({"op": "TemporalMemory.remember", "session": rec.session_id, "trust": trust.value,
                           "item": ep.item.id, "conflicts": len(conflicts)})
        return {"item": ep.item.id, "conflicts": conflicts}

    def baseline(self, subject_id: str, at: dt.datetime) -> dict:
        """Personal baseline from what CI held as having happened before `at`."""
        self.calls.append({"op": "TemporalMemory.valid_at", "at": at.isoformat()})
        known = self.memory.valid_at(subject_id, at - dt.timedelta(seconds=1)) if self.store.get_user(subject_id) else []
        # Lexical retrieval through CI's embedder, recorded so the evidence view can show the ranking.
        hits = self.memory.search(subject_id, "FIXATION session slow-phase velocity", k=50) if known else []
        self.calls.append({"op": "TemporalMemory.search", "hits": len(hits)})
        conflicted_ids = {i.id for i in known if CONFLICT_FLAG in i.flags}
        used, excluded = [], []
        for it in sorted((i for i in known if i.kind == "episode" and PROTOCOL_TAG in i.tags), key=lambda i: i.valid_from):
            v = it.value or {}
            sid = v.get("session_id")
            reason = None
            if it.trust.rank < Trust.IMPORTED.rank:
                reason = f"source trust {it.trust.value} is below a NeuroAssist measurement"
            elif v.get("status") != "MEASURED":
                reason = "the measurement gate abstained on this session"
            elif v.get("accepted") is False:
                reason = "the collective rejected this session"
            entry = {"session_id": sid, "value": v.get("value"), "recorded_at": it.valid_from.isoformat(),
                     "label": v.get("label"), "engine": v.get("engine"), "trust": it.trust.value, "memory_item": it.id}
            if reason:
                excluded.append({**entry, "reason": reason})
            else:
                used.append(entry)
        vals = [u["value"] for u in used]
        conflicts = self.store.list_conflicts(subject_id) if self.store.get_user(subject_id) else []
        n = len(vals)
        med = _median(vals) if vals else None
        spread = max(SPREAD_FLOOR, 1.4826 * _median([abs(v - med) for v in vals])) if n >= 2 else None
        return {"n": n, "median": med, "spread": spread, "sufficient": n >= MIN_BASELINE, "used": used,
                "excluded": excluded, "conflicts": [{"id": c["id"], "a": c["item_a"], "b": c["item_b"]} for c in conflicts],
                "conflicted_items": sorted(conflicted_ids), "min_n": MIN_BASELINE}

    def audit_summary(self) -> dict:
        ok, bad = self.audit.verify()
        return {"entries": len(self.audit.entries()), "head": self.audit.head(), "chain_ok": ok, "first_bad": bad}


def _median(a: list[float]) -> float:
    b = sorted(a)
    m = len(b) >> 1
    return b[m] if len(b) % 2 else (b[m - 1] + b[m]) / 2


def naive_baseline(history: list[SessionRecord], at: dt.datetime, last_only: bool = False) -> dict:
    """No CI: every prior measured record counts the same, whatever its source (used by ablations)."""
    prior = sorted((r for r in history if r.recorded_at < at and r.measurement.status == "MEASURED"),
                   key=lambda r: r.recorded_at)
    if last_only:
        prior = prior[-1:]
    vals = [r.measurement.value for r in prior]
    n = len(vals)
    med = _median(vals) if vals else None
    spread = max(SPREAD_FLOOR, 1.4826 * _median([abs(v - med) for v in vals])) if n >= 2 else None
    used = [{"session_id": r.session_id, "value": r.measurement.value, "label": r.provenance.label} for r in prior]
    return {"n": n, "median": med, "spread": spread, "sufficient": n >= MIN_BASELINE, "used": used, "excluded": [],
            "conflicts": [], "conflicted_items": [], "min_n": MIN_BASELINE}


def finite(v) -> bool:
    return v is not None and isinstance(v, (int, float)) and math.isfinite(v)
