"""Scientific Evidence Auditor: a small, domain-neutral check that every claim a scientific
pipeline wants to report is backed by evidence that exists, is intact, is of acceptable
quality and provenance, and has survived every challenge raised against it.

No dependencies beyond the Python standard library. Input and output are plain JSON
(schema: evidence_auditor/schema.json). See evidence_auditor/README.md.

    from evidence_auditor import audit
    report = audit(observation)            # -> dict, schema "evidence-auditor.report/1"
"""

from __future__ import annotations

import hashlib
import json
from typing import Any

__all__ = ["audit", "content_hash", "DEFAULT_POLICY", "REPORT_SCHEMA", "INPUT_SCHEMA"]
__version__ = "0.1.0"

INPUT_SCHEMA = "evidence-auditor.observation/1"
REPORT_SCHEMA = "evidence-auditor.report/1"
QUALITY = ("ok", "concern", "fail")

DEFAULT_POLICY: dict[str, Any] = {
    # Evidence whose content is present must match its sha256.
    "verify_hashes": True,
    # Provenance labels a reportable claim may rest on. Anything else makes the claim unsupported.
    "allowed_labels": ["REAL", "PRERECORDED", "SYNTHETIC"],
    # Labels that are allowed but must be disclosed next to the claim.
    "disclose_labels": ["SYNTHETIC", "PRERECORDED"],
    # Overall measurement quality that forces a recommendation, regardless of claims.
    "remeasure_on": ["fail"],
    # Evidence of this quality cannot support a claim.
    "unusable_quality": ["fail"],
    # Evidence of this quality supports a claim only with a caveat.
    "caveat_quality": ["concern"],
}


def content_hash(content: Any) -> str:
    """sha256 of canonical JSON (sorted keys, no whitespace, UTF-8). Producers must hash the same way."""
    body = json.dumps(content, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)
    return hashlib.sha256(body.encode()).hexdigest()


def _err(msg: str) -> ValueError:
    return ValueError(f"evidence-auditor: {msg}")


def _validate(obs: dict) -> None:
    if not isinstance(obs, dict):
        raise _err("observation must be an object")
    if obs.get("schema", INPUT_SCHEMA) != INPUT_SCHEMA:
        raise _err(f"unknown schema {obs.get('schema')!r}")
    for key in ("claims", "evidence"):
        if not isinstance(obs.get(key), list):
            raise _err(f"'{key}' must be a list")
    ids = [e.get("id") for e in obs["evidence"]]
    if any(not isinstance(i, str) or not i for i in ids):
        raise _err("every evidence item needs a string id")
    if len(set(ids)) != len(ids):
        raise _err("evidence ids must be unique")
    for c in obs["claims"]:
        if not isinstance(c.get("id"), str) or not isinstance(c.get("statement"), str):
            raise _err("every claim needs a string id and statement")
    q = (obs.get("quality") or {}).get("status", "ok")
    if q not in QUALITY:
        raise _err(f"quality.status must be one of {QUALITY}")


def audit(observation: dict, policy: dict | None = None) -> dict:
    """Audit an observation. Pure function: same input, same report."""
    _validate(observation)
    pol = {**DEFAULT_POLICY, **(policy or {})}
    evidence = {e["id"]: e for e in observation["evidence"]}
    challenges = observation.get("challenges") or []
    quality = observation.get("quality") or {"status": "ok", "reasons": []}

    integrity: dict[str, str | None] = {}
    for eid, e in evidence.items():
        problem = None
        if pol["verify_hashes"] and "content" in e:
            if not e.get("sha256"):
                problem = "has content but no sha256"
            elif content_hash(e["content"]) != e["sha256"]:
                problem = "content does not match its sha256"
        integrity[eid] = problem

    supported, unsupported, missing = [], [], []
    for c in observation["claims"]:
        reasons, caveats, disclose = [], [], set()
        refs = list(dict.fromkeys(c.get("evidence") or []))
        if not refs:
            reasons.append("cites no evidence")
        present_types = set()
        for r in refs:
            e = evidence.get(r)
            if e is None:
                reasons.append(f"cites {r}, which does not exist")
                continue
            present_types.add(e.get("type"))
            if integrity[r]:
                reasons.append(f"evidence {r} {integrity[r]}")
            eq = e.get("quality", "ok")
            if eq in pol["unusable_quality"]:
                reasons.append(f"evidence {r} ({e.get('type')}) has quality '{eq}'")
            elif eq in pol["caveat_quality"]:
                caveats.append(f"evidence {r} ({e.get('type')}) has quality '{eq}'")
            label = (e.get("provenance") or {}).get("label")
            if label is not None and label not in pol["allowed_labels"]:
                reasons.append(f"evidence {r} has provenance '{label}', not allowed for a reportable claim")
            if label in pol["disclose_labels"]:
                disclose.add(label)
        for need in c.get("requires") or []:
            if need not in present_types:
                missing.append({"claim_id": c["id"], "type": need})
                reasons.append(f"missing required evidence of type '{need}'")
        for ch in challenges:
            if ch.get("target_claim") == c["id"] and ch.get("status", "open") == "open":
                reasons.append(f"unresolved challenge {ch.get('id')} by {ch.get('by', '?')}: {ch.get('reason', '')}".strip())
        row = {"claim_id": c["id"], "statement": c["statement"], "type": c.get("type"), "evidence": refs}
        if reasons:
            unsupported.append({**row, "reasons": reasons})
        else:
            supported.append({**row, "caveats": caveats, "disclose": sorted(disclose)})

    reasons = []
    if quality.get("status") in pol["remeasure_on"]:
        rec = "REMEASURE"
        reasons.append("measurement quality is '%s': %s" % (quality["status"], "; ".join(quality.get("reasons") or []) or "no reason given"))
    elif not supported:
        rec = "ABSTAIN"
        reasons.append("no claim is supported by intact, adequate, unchallenged evidence")
    else:
        rec = "REPORT"
    return {
        "schema": REPORT_SCHEMA,
        "auditor_version": __version__,
        "recommendation": rec,
        "reasons": reasons,
        "supported": supported,
        "unsupported": unsupported,
        "missing_evidence": missing,
        "evidence_integrity": {k: (v or "ok") for k, v in integrity.items()},
    }
