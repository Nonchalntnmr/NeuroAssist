import json
import math
from pathlib import Path

import pytest

from evidence_auditor import content_hash
from naci.benchmark import load
from naci.collective import ACCESS, AccessDenied, Board, run_collective
from naci.contract import SessionRecord
from naci.memory import CIMemory
from naci.neurocore import analyze

ROOT = Path(__file__).resolve().parent.parent


@pytest.fixture(scope="module")
def dev():
    _, cases, _ = load("dev")
    return {c["case_id"]: c for c in cases}


def test_neurocore_matches_typescript_engine_exactly():
    suite = json.loads((ROOT / "benchmark/cases/heldout.json").read_text())
    ts = {p["case_id"]: p for p in json.loads((ROOT / "benchmark/cases/parity-ts.json").read_text())}
    for c in suite["cases"]:
        tr = c["target"]["trace"]
        a = analyze(tr["t"], tr["x"])
        p = ts[c["case_id"]]
        assert a.passed == p["pass"] and len(a.chunks) == p["chunks"] and a.fast_phases == p["fastPhases"]
        for k in ("est", "sigma"):
            v = getattr(a, k)
            assert (p[k] is None and not math.isfinite(v)) or abs(v - p[k]) < 1e-9


def test_records_follow_from_their_traces(dev):
    for c in dev.values():
        t = c["target"]
        a = analyze(t.trace.t, t.trace.x)
        assert a.passed == t.gate_passed()
        if a.passed:
            assert abs(a.est - t.measurement.value) < 1e-3


def test_agents_cannot_read_outside_their_access(dev):
    c = next(iter(dev.values()))
    b = Board("r", c["target"], CIMemory().audit, None, c["history"])
    with pytest.raises(AccessDenied):
        b.read("physiology", "trace.gaze")
    with pytest.raises(AccessDenied):
        b.read("skeptic", "trace.gaze")
    with pytest.raises(AccessDenied):
        b.read("signal_quality", "ci_memory")
    with pytest.raises(AccessDenied):
        b.history_records("physiology")
    assert "trace.gaze" in ACCESS["signal_quality"] and "ci_memory" in ACCESS["contextual_memory"]


def test_deterministic_and_reproducible(dev):
    c = dev["dev-tracking_artifact-1"]
    r1, r2 = run_collective(c["target"], c["history"]), run_collective(c["target"], c["history"])
    # Decisions, numbers and the message flow are deterministic. CI gives memory items random ids
    # (pcim.types.new_id), so evidence that cites them hashes differently per run.
    strip = lambda r: [(m["sender"], m["kind"], m["text"]) for m in r.messages if m["kind"] != "MEMORY_WRITE"]
    assert strip(r1) == strip(r2) and r1.decision == r2.decision
    no_ci = lambda r: [e["sha256"] for e in r.evidence if e["type"] not in ("baseline", "conflict_report", "audit_report")]
    assert no_ci(r1) == no_ci(r2)


def test_snap_artifact_is_challenged_and_vetoed(dev):
    c = dev["dev-tracking_artifact-1"]
    assert c["target"].gate_passed(), "this slip passes NeuroAssist's own gate"
    r = run_collective(c["target"], c["history"])
    kinds = [(m["sender"], m["kind"]) for m in r.messages]
    assert ("skeptic", "EVIDENCE_REQUEST") in kinds and ("signal_quality", "EVIDENCE") in kinds
    assert ("skeptic", "VETO") in kinds and r.decision == "ABSTAIN"


def test_conflicts_come_from_ci_and_are_resolved_with_disclosure(dev):
    c = dev["dev-conflicting_history-0"]
    r = run_collective(c["target"], c["history"])
    base = next(e for e in r.evidence if e["type"] == "baseline")["content"]
    assert base["conflicts"], "CI opened conflicts for the lower-trust imports"
    assert all(e["trust"] == "untrusted" for e in base["excluded"])
    kinds = [(m["sender"], m["kind"]) for m in r.messages]
    assert ("skeptic", "CHALLENGE") in kinds and ("contextual_memory", "EVIDENCE") in kinds and ("skeptic", "RESOLVE") in kinds
    assert r.decision == c["truth"]["decision"]


def test_evidence_hashes_and_ci_audit_chain_verify(dev):
    c = dev["dev-true_change-0"]
    r = run_collective(c["target"], c["history"])
    for e in r.evidence:
        assert content_hash(e["content"]) == e["sha256"]
    assert r.audit["chain_ok"] and r.audit["entries"] > 0
    v = next(m for m in r.messages if m["kind"] == "VERDICT")
    ids = {e["id"] for e in r.evidence}
    assert v["refs"] and all(x in ids for x in v["refs"])


def test_baseline_is_as_of_the_session_time(dev):
    c = dev["dev-true_change-0"]
    later = c["target"].model_copy(update={"session_id": "future", "recorded_at": c["target"].recorded_at.replace(year=2027)})
    r = run_collective(c["target"], c["history"] + [later])
    base = next(e for e in r.evidence if e["type"] == "baseline")["content"]
    assert "future" not in [u["session_id"] for u in base["used"]]


@pytest.mark.parametrize("agent", ["signal_quality", "contextual_memory", "physiology", "skeptic", "auditor"])
@pytest.mark.parametrize("mode", ["silent", "byzantine"])
def test_one_faulty_agent_never_makes_an_artifact_into_a_conclusion(dev, agent, mode):
    for cid in ("dev-tracking_artifact-1", "dev-tracking_artifact-3", "dev-conflicting_history-0"):
        c = dev[cid]
        r = run_collective(c["target"], c["history"], faults={agent: mode})
        truth = c["truth"]["decision"]
        assert r.decision in (truth, "ABSTAIN", "NO_BASELINE"), (cid, agent, mode, r.decision)


def test_contract_rejects_bad_records(dev):
    c = next(iter(dev.values()))
    d = c["target"].model_dump(mode="json", by_alias=True)
    for bad in ({**d, "schema": "naci.session/2"}, {**d, "subject_id": "a b"},
                {**d, "trace": {**d["trace"], "t": list(reversed(d["trace"]["t"]))}},
                {**d, "measurement": {**d["measurement"], "status": "MEASURED", "value": None}}):
        with pytest.raises(Exception):
            SessionRecord.model_validate(bad)


def test_messages_map_onto_ci_exchange_format(dev):
    c = dev["dev-true_change-0"]
    r = run_collective(c["target"], c["history"])
    from naci.contract import AgentMessage
    m = AgentMessage.model_validate(r.messages[0])
    ci = m.to_ci(c["target"].subject_id)
    assert ci.wire()["schemaVersion"] == "ci.agent-message/1"
