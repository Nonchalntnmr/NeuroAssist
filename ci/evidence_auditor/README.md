# Scientific Evidence Auditor

A small, domain-neutral check for any scientific pipeline, agentic or not: is every claim you want to
report backed by evidence that **exists**, is **intact**, is of **adequate quality and provenance**, and
has **survived every challenge**?

- Pure Python standard library, one file. Copy the folder into your project.
- Pure function: the same input always gives the same report.
- JSON in, JSON out. Schema: `schema.json`.

## Use

```python
from evidence_auditor import audit, content_hash

content = {"method": "SPR", "kd_nM": 4.1, "replicates": 3}
obs = {
  "schema": "evidence-auditor.observation/1",
  "claims": [{"id": "c1", "statement": "V12 binds T with Kd 4.1 nM", "evidence": ["e1"], "requires": ["assay"]}],
  "evidence": [{"id": "e1", "type": "assay", "producer": "assay-agent", "content": content,
                "sha256": content_hash(content), "quality": "ok", "provenance": {"label": "REAL"}}],
  "challenges": [],
  "quality": {"status": "ok"},
}
report = audit(obs)          # report["recommendation"] -> "REPORT"
```

Over HTTP: `POST /api/py/v1/auditor/audit` with the observation as the body. Pass a `_policy` key to
override the defaults.

## Rules

A claim is **unsupported** when any of these holds:

- it cites no evidence, or cites an id that does not exist;
- a cited item has content whose sha256 does not match (`content_hash`: canonical JSON, sorted keys, no
  spaces, UTF-8);
- a cited item has quality `fail`;
- a cited item's provenance label is not in `allowed_labels`;
- an evidence type listed in `requires` is not among the cited items (also reported in `missing_evidence`);
- a challenge targeting it is still `open`.

Supported claims carry `caveats` (cited evidence with quality `concern`) and `disclose` (labels such as
`SYNTHETIC` that must be shown with the claim).

Recommendation: `REMEASURE` if overall quality is `fail`; otherwise `ABSTAIN` if no claim is supported;
otherwise `REPORT`.

## Policy (defaults)

```json
{"verify_hashes": true, "allowed_labels": ["REAL", "PRERECORDED", "SYNTHETIC"],
 "disclose_labels": ["SYNTHETIC", "PRERECORDED"], "remeasure_on": ["fail"],
 "unusable_quality": ["fail"], "caveat_quality": ["concern"]}
```

## Examples and tests

- `examples/protein_assay.json`: an invented binding-assay example from another domain. One claim is
  supported; the comparison is not (a failed QC plate and an open challenge).
- `examples/neuroassist_session.json`: exported from a NeuroAssist × CI run where a tracking slip was vetoed.
- `tests/test_evidence_auditor.py`: tampering, missing evidence, challenges, labels, invalid input.

## Limits

It checks the structure of the evidence, not the science: it cannot tell whether an assay was the right
one, only whether the claim cites what it says it needs and nothing it cites is broken or disputed.

MIT licence.
