import json
from pathlib import Path

import pytest

from evidence_auditor import audit, content_hash

EX = Path(__file__).resolve().parent.parent / "evidence_auditor" / "examples"


def ev(i, typ, content, **kw):
    return {"id": i, "type": typ, "producer": "p", "content": content, "sha256": content_hash(content), **kw}


def base():
    return {"schema": "evidence-auditor.observation/1",
            "claims": [{"id": "c1", "statement": "X rose", "evidence": ["e1", "e2"], "requires": ["measurement", "baseline"]}],
            "evidence": [ev("e1", "measurement", {"v": 2}), ev("e2", "baseline", {"m": 1})], "challenges": [],
            "quality": {"status": "ok"}}


def test_supported_claim_is_reported():
    r = audit(base())
    assert r["recommendation"] == "REPORT" and [s["claim_id"] for s in r["supported"]] == ["c1"]


def test_tampered_evidence_is_caught():
    o = base()
    o["evidence"][0]["content"] = {"v": 3}
    r = audit(o)
    assert r["recommendation"] == "ABSTAIN" and "does not match its sha256" in r["unsupported"][0]["reasons"][0]


def test_missing_required_evidence():
    o = base()
    o["claims"][0]["evidence"] = ["e1"]
    r = audit(o)
    assert r["missing_evidence"] == [{"claim_id": "c1", "type": "baseline"}]


def test_open_challenge_blocks_and_resolved_does_not():
    o = base()
    o["challenges"] = [{"id": "k", "target_claim": "c1", "by": "skeptic", "reason": "artifact", "status": "open"}]
    assert audit(o)["recommendation"] == "ABSTAIN"
    o["challenges"][0]["status"] = "resolved"
    assert audit(o)["recommendation"] == "REPORT"


def test_bad_quality_means_remeasure_and_labels_are_disclosed():
    o = base()
    o["evidence"][0]["provenance"] = {"label": "SYNTHETIC"}
    r = audit(o)
    assert r["supported"][0]["disclose"] == ["SYNTHETIC"]
    o["quality"] = {"status": "fail", "reasons": ["camera dropped frames"]}
    assert audit(o)["recommendation"] == "REMEASURE"


def test_dangling_reference_and_disallowed_label():
    o = base()
    o["claims"][0]["evidence"].append("nope")
    assert "does not exist" in " ".join(audit(o)["unsupported"][0]["reasons"])
    o = base()
    o["evidence"][1]["provenance"] = {"label": "RUMOUR"}
    assert audit(o)["recommendation"] == "ABSTAIN"


def test_invalid_input_is_rejected():
    with pytest.raises(ValueError):
        audit({"claims": [], "evidence": [{"id": "a"}, {"id": "a"}]})
    with pytest.raises(ValueError):
        audit({"claims": [], "evidence": [], "quality": {"status": "great"}})


@pytest.mark.parametrize("name", ["protein_assay.json", "neuroassist_session.json"])
def test_examples_run(name):
    o = json.loads((EX / name).read_text())
    r = audit(o)
    assert r["schema"] == "evidence-auditor.report/1"
    exp = o.get("_expect")
    if exp:
        assert r["recommendation"] == exp
