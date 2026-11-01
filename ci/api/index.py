"""HTTP API for NeuroAssist x CI (Vercel Python function; FastAPI).

Routes (versioned):
  GET  /api/py/health
  POST /api/py/v1/collective/run     naci.session/1 target + history -> full collective run, plus the simpler systems
  POST /api/py/v1/auditor/audit      evidence-auditor.observation/1 -> evidence-auditor.report/1 (domain-neutral, for other teams)
  GET  /api/py/v1/benchmark          held-out benchmark results (SYNTHETIC)

Nothing sent here is stored. Each run builds a fresh, encrypted, in-memory CI store and drops it.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from typing import Literal

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from fastapi import FastAPI, HTTPException, Request  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from pydantic import BaseModel, Field, ValidationError  # noqa: E402

import evidence_auditor  # noqa: E402
from naci.baselines import deterministic, single_agent  # noqa: E402
from naci.collective import ROLES, run_collective  # noqa: E402
from naci.contract import SessionRecord  # noqa: E402

CI_COMMIT = "2e50658b868e27fca4ba5c11981b448076b93523"
MAX_BODY = 2_000_000

app = FastAPI(title="NeuroAssist x CI", version="1", docs_url="/api/py/docs", openapi_url="/api/py/openapi.json")


@app.middleware("http")
async def limits(request: Request, call_next):
    n = int(request.headers.get("content-length") or 0)
    if n > MAX_BODY:
        return JSONResponse({"error": "request too large", "limit_bytes": MAX_BODY}, status_code=413)
    resp = await call_next(request)
    resp.headers["Cache-Control"] = "no-store"
    resp.headers["X-Content-Type-Options"] = "nosniff"
    return resp


class RunRequest(BaseModel):
    target: SessionRecord
    history: list[SessionRecord] = Field(default=[], max_length=60)
    variant: Literal["ci", "naive", "none"] = "ci"
    faults: dict[str, Literal["silent", "byzantine"]] = {}
    compare: bool = True
    canonical: bool = False  # include each evidence item's canonical JSON so a client can re-hash it


@app.get("/api/py/health")
def health():
    try:
        import pcim  # noqa: F401
        ci_ok = True
    except Exception:  # pragma: no cover
        ci_ok = False
    return {"ok": ci_ok, "service": "neuroassist-ci", "api": "v1", "ci_commit": CI_COMMIT, "ci_importable": ci_ok,
            "auditor_version": evidence_auditor.__version__, "python": sys.version.split()[0],
            "region": os.environ.get("VERCEL_REGION")}


@app.post("/api/py/v1/collective/run")
def collective_run(req: RunRequest):
    if req.target.trace is None:
        raise HTTPException(422, "the target session needs its trace: the collective recomputes from raw frames")
    bad = set(req.faults) - set(ROLES)
    if bad:
        raise HTTPException(422, f"unknown agents {sorted(bad)}")
    subj = {req.target.subject_id} | {h.subject_id for h in req.history}
    if len(subj) != 1:
        raise HTTPException(422, "history and target must belong to the same subject")
    t0 = time.perf_counter()
    res = run_collective(req.target, req.history, req.variant, req.faults).to_json()
    if req.canonical:
        for e in res["evidence"]:
            e["canonical"] = json.dumps(e["content"], sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)
    out = {"schema": "naci.run/1", "computed": "live", "labels": sorted({req.target.provenance.label} | {h.provenance.label for h in req.history}),
           "collective": res, "roles": {k: {"name": v[0], "role": v[1]} for k, v in ROLES.items()}}
    if req.compare:
        out["compare"] = {"deterministic": deterministic(req.target, req.history), "single_agent": single_agent(req.target, req.history)}
    out["server_ms"] = round((time.perf_counter() - t0) * 1000, 2)
    return out


@app.post("/api/py/v1/auditor/audit")
async def auditor(request: Request):
    try:
        body = await request.json()
        policy = body.pop("_policy", None) if isinstance(body, dict) else None
        return evidence_auditor.audit(body, policy)
    except ValueError as e:
        raise HTTPException(422, str(e))


@app.get("/api/py/v1/benchmark")
def benchmark():
    p = ROOT / "benchmark" / "results" / "heldout.json"
    d = json.loads(p.read_text())
    d.pop("per_case", None)
    return d


@app.exception_handler(ValidationError)
async def _val(_, exc: ValidationError):
    return JSONResponse({"error": "invalid input", "detail": json.loads(exc.json())[:20]}, status_code=422)
