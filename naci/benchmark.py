"""Benchmark: identical SYNTHETIC cases through every system.

    python3 -m naci.benchmark --split dev        # tuning set
    python3 -m naci.benchmark --split heldout    # reported set (never used for tuning)
    python3 -m naci.benchmark --split heldout --faults   # adds the fault-injection experiment

Writes benchmark/results/<split>.json. Deterministic: rerunning gives identical decisions.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import statistics
import sys
import time
from pathlib import Path

from .baselines import deterministic, monolith, single_agent
from .collective import run_collective
from .contract import SessionRecord

ROOT = Path(__file__).resolve().parent.parent
ABSTAINS = ("ABSTAIN", "NO_BASELINE")
CONCLUSIONS = ("CHANGE", "NO_CHANGE")

SYSTEMS = {
    "deterministic": ("NeuroAssist gate + previous visit", lambda t, h: deterministic(t, h)),
    "single_agent": ("Single agent, one pass, full history", lambda t, h: single_agent(t, h)),
    "collective_no_history": ("Collective, no historical context", lambda t, h: run_collective(t, h, "none").to_json()),
    "collective_naive_history": ("Collective, raw history (no CI)", lambda t, h: run_collective(t, h, "naive").to_json()),
    "collective_ci": ("Collective + CI memory", lambda t, h: run_collective(t, h, "ci").to_json()),
    "monolith_ci": ("Ablation: same checks in one function + CI", lambda t, h: monolith(t, h)),
}
FAULTS = [(a, f) for a in ("signal_quality", "contextual_memory", "physiology", "skeptic", "auditor") for f in ("silent", "byzantine")]


def load(split: str):
    raw = (ROOT / "benchmark" / "cases" / f"{split}.json").read_bytes()
    suite = json.loads(raw)
    cases = []
    for c in suite["cases"]:
        cases.append({**c, "target": SessionRecord.model_validate(c["target"]),
                      "history": [SessionRecord.model_validate(h) for h in c["history"]]})
    return suite, cases, hashlib.sha256(raw).hexdigest()


def score(rows: list[dict]) -> dict:
    n = len(rows)
    correct = sum(r["pred"] == r["truth"] for r in rows)
    concl = [r for r in rows if r["pred"] in CONCLUSIONS]
    unsupported = [r for r in concl if r["pred"] != r["truth"]]
    should_abstain = [r for r in rows if r["truth"] in ABSTAINS]
    should_conclude = [r for r in rows if r["truth"] in CONCLUSIONS]
    art = [r for r in rows if r["artifact"]]
    clean = [r for r in rows if not r["artifact"]]
    harmful = [r for r in rows if r["artifact"] and r["truth"] == "ABSTAIN"]
    base = [r for r in rows if r["truth_baseline"] and r["baseline_ids"] is not None and r["truth"] in CONCLUSIONS]
    lat = [r["latency_ms"] for r in rows]

    def jacc(a, b):
        a, b = set(a), set(b)
        return len(a & b) / len(a | b) if a | b else 1.0

    def pct(x, d):
        return round(x / d, 4) if d else None

    return {
        "n": n,
        "accuracy": pct(correct, n),
        "unsupported_conclusion_rate": pct(len(unsupported), n),
        "unsupported_among_conclusions": pct(len(unsupported), len(concl)),
        "appropriate_abstention": pct(sum(r["pred"] in ABSTAINS for r in should_abstain), len(should_abstain)),
        "over_abstention": pct(sum(r["pred"] in ABSTAINS for r in should_conclude), len(should_conclude)),
        "artifact_detection_recall": pct(sum(r["flagged"] for r in art), len(art)),
        "harmful_artifact_caught": pct(sum(r["pred"] == "ABSTAIN" for r in harmful), len(harmful)),
        "artifact_false_flag_rate": pct(sum(r["flagged"] for r in clean), len(clean)),
        "baseline_retrieval_jaccard": round(statistics.mean(jacc(r["baseline_ids"], r["truth_baseline"]) for r in base), 4) if base else None,
        "evidence_traceability": pct(sum(r["traceable"] for r in rows if r["pred"] in CONCLUSIONS + ("NO_BASELINE",)),
                                     sum(1 for r in rows if r["pred"] in CONCLUSIONS + ("NO_BASELINE",))),
        "latency_ms_median": round(statistics.median(lat), 2),
        "latency_ms_p95": round(sorted(lat)[int(0.95 * (len(lat) - 1))], 2),
        "llm_tokens": 0,
    }


def traceable(out: dict) -> bool:
    """A reported conclusion is traceable if a certified verdict cites hash-identified evidence that exists."""
    ev = {e["id"]: e for e in out.get("evidence", [])}
    verdict = next((m for m in out.get("messages", []) if m["kind"] == "VERDICT"), None)
    return bool(verdict and verdict["refs"] and all(r in ev and ev[r].get("sha256") for r in verdict["refs"]))


def run(split: str, faults: bool = False, systems: list[str] | None = None) -> dict:
    suite, cases, sha = load(split)
    out = {"schema": "naci.benchmark/1", "split": split, "label": "SYNTHETIC", "cases_sha256": sha, "n_cases": len(cases),
           "python": platform.python_version(), "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "systems": {}, "per_type": {}, "per_case": {}}
    for key in systems or SYSTEMS:
        label, fn = SYSTEMS[key]
        rows = []
        for c in cases:
            o = fn(c["target"], c["history"])
            rows.append({"case_id": c["case_id"], "type": c["type"], "pred": o["decision"], "truth": c["truth"]["decision"],
                         "artifact": c["truth"]["artifact"], "flagged": bool(o.get("artifact_flagged")),
                         "baseline_ids": o.get("baseline_ids"), "truth_baseline": c["truth"]["baseline_ids"],
                         "traceable": traceable(o), "latency_ms": o["latency_ms"], "causes": o.get("artifact_causes", [])})
        out["systems"][key] = {"label": label, **score(rows)}
        by_type = {}
        for t in sorted({r["type"] for r in rows}):
            rr = [r for r in rows if r["type"] == t]
            by_type[t] = {"accuracy": round(sum(r["pred"] == r["truth"] for r in rr) / len(rr), 4),
                          "unsupported": sum(r["pred"] in CONCLUSIONS and r["pred"] != r["truth"] for r in rr), "n": len(rr)}
        out["per_type"][key] = by_type
        out["per_case"][key] = {r["case_id"]: [r["pred"], r["truth"]] for r in rows}
        print(f"{key:28s} acc={out['systems'][key]['accuracy']} unsup={out['systems'][key]['unsupported_conclusion_rate']} "
              f"abst={out['systems'][key]['appropriate_abstention']} over={out['systems'][key]['over_abstention']} "
              f"art={out['systems'][key]['artifact_detection_recall']} trace={out['systems'][key]['evidence_traceability']} "
              f"lat={out['systems'][key]['latency_ms_median']}ms", file=sys.stderr)
    if faults:
        out["faults"] = {}
        for agent, mode in FAULTS:
            rows = []
            for c in cases:
                o = run_collective(c["target"], c["history"], "ci", faults={agent: mode}).to_json()
                rows.append({"case_id": c["case_id"], "type": c["type"], "pred": o["decision"], "truth": c["truth"]["decision"],
                             "artifact": c["truth"]["artifact"], "flagged": bool(o.get("artifact_flagged")),
                             "baseline_ids": o.get("baseline_ids"), "truth_baseline": c["truth"]["baseline_ids"],
                             "traceable": traceable(o), "latency_ms": o["latency_ms"]})
            s = score(rows)
            out["faults"][f"{agent}:{mode}"] = {k: s[k] for k in ("accuracy", "unsupported_conclusion_rate", "over_abstention", "appropriate_abstention")}
            print(f"fault {agent}:{mode:10s} acc={s['accuracy']} unsup={s['unsupported_conclusion_rate']} over={s['over_abstention']}", file=sys.stderr)
        # The same component faults in the monolith (one stage corrupted; no other stage overlaps it).
        out["monolith_faults"] = {}
        for agent, stage in (("signal_quality", "quality"), ("contextual_memory", "memory"), ("physiology", "analysis"), ("skeptic", "robustness")):
            rows = []
            for c in cases:
                o = monolith(c["target"], c["history"], fault=stage)
                rows.append({"case_id": c["case_id"], "type": c["type"], "pred": o["decision"], "truth": c["truth"]["decision"],
                             "artifact": c["truth"]["artifact"], "flagged": bool(o.get("artifact_flagged")),
                             "baseline_ids": o.get("baseline_ids"), "truth_baseline": c["truth"]["baseline_ids"],
                             "traceable": False, "latency_ms": o["latency_ms"]})
            s = score(rows)
            out["monolith_faults"][f"{agent}:byzantine"] = {k: s[k] for k in ("accuracy", "unsupported_conclusion_rate", "over_abstention", "appropriate_abstention")}
            print(f"monolith {stage:10s} acc={s['accuracy']} unsup={s['unsupported_conclusion_rate']} over={s['over_abstention']}", file=sys.stderr)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", default="dev")
    ap.add_argument("--faults", action="store_true")
    ap.add_argument("--systems", nargs="*")
    a = ap.parse_args(argv)
    res = run(a.split, a.faults, a.systems)
    p = ROOT / "benchmark" / "results" / f"{a.split}.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(res, indent=1))
    print(p)


if __name__ == "__main__":
    main()
