"""Reproduce headline stats (k/n, Wilson 95% CI, exact McNemar) from NACI benchmark JSON. Stdlib only."""
import json, math, statistics, sys
from pathlib import Path

ROOT = Path.home() / "projects/contextual-intelligence/neuroassist-ci"
RES = json.loads((ROOT / "benchmark/results/heldout.json").read_text())
CASES = json.loads((ROOT / "benchmark/cases/heldout.json").read_text())["cases"]  # read-only, for truth.artifact/type
OUT = Path(__file__).with_name("benchmark_stats.json")
ABSTAINS, CONCL = ("ABSTAIN", "NO_BASELINE"), ("CHANGE", "NO_CHANGE")
Z = 1.959963984540054

def wilson(k, n, z=Z):
    if n == 0: return None
    p = k / n; d = 1 + z*z/n
    c = (p + z*z/(2*n)) / d; h = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n)) / d
    return [round(max(0.0, c-h), 4), round(min(1.0, c+h), 4)]

def stat(k, n):
    return {"k": k, "n": n, "p": round(k/n, 4) if n else None, "wilson95": wilson(k, n)}

def binom_two_sided_exact(b, c):
    n = b + c
    if n == 0: return 1.0
    k = min(b, c)
    tail = sum(math.comb(n, i) for i in range(k+1)) / 2**n
    return min(1.0, 2*tail)

meta = {c["case_id"]: c for c in CASES}
per_case = RES["per_case"]
out = {"source": str(ROOT / "benchmark/results/heldout.json"), "cases_sha256": RES["cases_sha256"],
       "n_cases": RES["n_cases"], "headline": {}, "per_type": {}, "mcnemar": {}, "cost_latency": {},
       "faults": {}, "monolith_faults": {}, "checks": []}

for s, pc in per_case.items():
    rows = [(cid, p, t) for cid, (p, t) in pc.items()]  # per_case value = [pred, truth]
    n = len(rows)
    correct = sum(p == t for _, p, t in rows)
    concl = [(cid, p, t) for cid, p, t in rows if p in CONCL]
    unsup = sum(p != t for _, p, t in concl)
    should_ab = [r for r in rows if r[2] in ABSTAINS]
    should_co = [r for r in rows if r[2] in CONCL]
    harmful = [r for r in rows if meta[r[0]]["truth"]["artifact"] and r[2] == "ABSTAIN"]
    h = {"accuracy": stat(correct, n),
         "unsupported_conclusion_rate": stat(unsup, n),
         "unsupported_among_conclusions": stat(unsup, len(concl)),
         "appropriate_abstention": stat(sum(r[1] in ABSTAINS for r in should_ab), len(should_ab)),
         "over_abstention": stat(sum(r[1] in ABSTAINS for r in should_co), len(should_co)),
         "harmful_artifact_caught": stat(sum(r[1] == "ABSTAIN" for r in harmful), len(harmful))}
    # artifact recall / false-flag need per-case 'flagged', not stored; recover counts from rates
    art_n = sum(meta[c]["truth"]["artifact"] for c, _, _ in rows); clean_n = n - art_n
    sm = RES["systems"][s]
    h["artifact_detection_recall"] = {**stat(round(sm["artifact_detection_recall"]*art_n), art_n), "recovered_from_rate": True}
    h["artifact_false_flag_rate"] = {**stat(round(sm["artifact_false_flag_rate"]*clean_n), clean_n), "recovered_from_rate": True}
    out["headline"][s] = {"label": sm["label"], **h}
    for m in ("accuracy", "unsupported_conclusion_rate", "unsupported_among_conclusions", "appropriate_abstention",
              "over_abstention", "harmful_artifact_caught"):
        if sm[m] is not None and abs(sm[m] - h[m]["p"]) > 1e-4:
            out["checks"].append(f"MISMATCH {s}.{m}: json={sm[m]} recomputed={h[m]['p']}")
    pt = {}
    for cid, p, t in rows:
        ty = meta[cid]["type"]; d = pt.setdefault(ty, [0, 0, 0])
        d[0] += p == t; d[1] += 1; d[2] += (p in CONCL and p != t)
    out["per_type"][s] = {ty: {**stat(k, nn), "unsupported": u} for ty, (k, nn, u) in sorted(pt.items())}
    for ty, v in out["per_type"][s].items():
        j = RES["per_type"][s][ty]
        if abs(j["accuracy"] - v["p"]) > 1e-4 or j["unsupported"] != v["unsupported"]:
            out["checks"].append(f"MISMATCH per_type {s}.{ty}")
    out["cost_latency"][s] = {"latency_ms_median": sm["latency_ms_median"], "latency_ms_p95": sm["latency_ms_p95"],
                              "latency_ms_mean": None, "llm_tokens": sm["llm_tokens"], "ci_calls": sm.get("ci_calls"),
                              "rounds": sm.get("rounds")}

def mcnemar(a, b, label):
    A, B = per_case[a], per_case[b]
    ids = sorted(set(A) & set(B)); assert len(ids) == len(A) == len(B)
    ca = {i: A[i][0] == A[i][1] for i in ids}; cb = {i: B[i][0] == B[i][1] for i in ids}
    both = sum(ca[i] and cb[i] for i in ids); neither = sum(not ca[i] and not cb[i] for i in ids)
    bb = sum(ca[i] and not cb[i] for i in ids); cc = sum(not ca[i] and cb[i] for i in ids)
    identical_preds = sum(A[i][0] == B[i][0] for i in ids)
    return {"comparison": label, "n": len(ids), "both_correct": both, "both_wrong": neither,
            f"b_{a}_right_{b}_wrong": bb, f"c_{a}_wrong_{b}_right": cc,
            "exact_mcnemar_p_two_sided": binom_two_sided_exact(bb, cc), "identical_decisions": identical_preds,
            "discordant_case_ids": [i for i in ids if ca[i] != cb[i]]}

for b in ("single_agent", "monolith_ci", "collective_naive_history", "deterministic"):
    out["mcnemar"][f"collective_ci_vs_{b}"] = mcnemar("collective_ci", b, f"collective_ci vs {b}")

N = RES["n_cases"]
ns_ab = sum(c["truth"]["decision"] in ABSTAINS for c in CASES); ns_co = N - ns_ab
for key, src in (("faults", RES.get("faults", {})), ("monolith_faults", RES.get("monolith_faults", {}))):
    for f, v in src.items():
        out[key][f] = {"accuracy": stat(round(v["accuracy"]*N), N),
                       "unsupported_conclusion_rate": stat(round(v["unsupported_conclusion_rate"]*N), N),
                       "over_abstention": stat(round(v["over_abstention"]*ns_co), ns_co),
                       "appropriate_abstention": stat(round(v["appropriate_abstention"]*ns_ab), ns_ab),
                       "recovered_from_rate": True}

OUT.write_text(json.dumps(out, indent=1))
print(json.dumps({"checks": out["checks"] or ["all recomputed metrics match JSON"]}, indent=1))
fmt = lambda d: f"{d['k']}/{d['n']} ({100*d['p']:.1f}%, {100*d['wilson95'][0]:.1f}-{100*d['wilson95'][1]:.1f})" if d["n"] else "n/a"
for s, h in out["headline"].items():
    print(s, "|", " | ".join(f"{m}={fmt(h[m])}" for m in ("accuracy", "unsupported_conclusion_rate", "harmful_artifact_caught", "unsupported_among_conclusions", "appropriate_abstention", "over_abstention", "artifact_detection_recall", "artifact_false_flag_rate")))
for k, v in out["mcnemar"].items():
    print(k, {x: y for x, y in v.items() if x != "discordant_case_ids"}, v["discordant_case_ids"])
for s, pt in out["per_type"].items():
    print(s, {t: f"{d['k']}/{d['n']}" for t, d in pt.items()})
for key in ("faults", "monolith_faults"):
    for f, v in out[key].items():
        print(key, f, "acc", fmt(v["accuracy"]), "unsup", fmt(v["unsupported_conclusion_rate"]), "over", fmt(v["over_abstention"]), "abst", fmt(v["appropriate_abstention"]))
