"""naci.session/1 and naci.agent-message/1. Mirror of lib/contract.ts.

The session record is the integration boundary with NeuroAssist (parent A). The agent message
is the collective's wire format; `to_ci()` maps it onto CI's own `ci.agent-message/1`
(pcim.exchange.AgentMessage), so a CI gateway can carry it unchanged.
"""

from __future__ import annotations

import datetime as dt
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

SESSION_SCHEMA = "naci.session/1"
MESSAGE_SCHEMA = "naci.agent-message/1"
DataLabel = Literal["REAL", "PRERECORDED", "SYNTHETIC"]
Decision = Literal["CHANGE", "NO_CHANGE", "NO_BASELINE", "ABSTAIN"]


class Provenance(BaseModel):
    model_config = ConfigDict(extra="allow")
    label: DataLabel
    source: str = Field(min_length=1, max_length=80)
    engine: str = Field(min_length=1, max_length=40)
    generator: dict | None = None


class Measurement(BaseModel):
    status: Literal["MEASURED", "ABSTAINED"]
    metric: Literal["SLOW_PHASE_VELOCITY"] = "SLOW_PHASE_VELOCITY"
    unit: Literal["deg/s"] = "deg/s"
    value: float | None
    ci_low: float | None = None
    ci_high: float | None = None
    windows: int = 0

    @model_validator(mode="after")
    def _measured_has_value(self):
        if self.status == "MEASURED" and self.value is None:
            raise ValueError("a MEASURED record needs a value")
        return self


class GateCheck(BaseModel):
    id: str
    label: str
    show: str = ""
    rule: str = ""
    ok: bool


class Quality(BaseModel):
    valid_frac: float = Field(ge=0, le=1)
    fps: float
    noise_deg: float | None = None
    residual_ratio: float | None = None
    checks: list[GateCheck] = []
    abstain_reasons: list[str] = []


class Trace(BaseModel):
    t: list[float] = Field(min_length=30, max_length=3600)
    x: list[float | None]
    head: list[float | None] | None = None  # signed head yaw, degrees

    @model_validator(mode="after")
    def _lengths(self):
        if len(self.x) != len(self.t) or (self.head is not None and len(self.head) != len(self.t)):
            raise ValueError("t, x and head must have the same length")
        if any(b < a for a, b in zip(self.t, self.t[1:])):
            raise ValueError("frame times must not decrease")
        return self


class SessionRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schema_: Literal["naci.session/1"] = Field(alias="schema")
    session_id: str = Field(min_length=1, max_length=120, pattern=r"^[A-Za-z0-9._:-]+$")
    subject_id: str = Field(min_length=1, max_length=80, pattern=r"^[A-Za-z0-9._:-]+$")
    recorded_at: dt.datetime
    protocol: Literal["FIXATION"]
    provenance: Provenance
    measurement: Measurement
    quality: Quality
    trace: Trace | None = None

    @field_validator("recorded_at")
    @classmethod
    def _aware(cls, v: dt.datetime) -> dt.datetime:
        return v if v.tzinfo else v.replace(tzinfo=dt.timezone.utc)

    def gate_passed(self) -> bool:
        return self.measurement.status == "MEASURED"

    def ci_halfwidth(self) -> float:
        m = self.measurement
        if m.ci_low is None or m.ci_high is None:
            return float("nan")
        return (m.ci_high - m.ci_low) / 2


MessageKind = Literal["FINDING", "CLAIM", "CHALLENGE", "EVIDENCE_REQUEST", "EVIDENCE", "REVISION", "RESOLVE",
                      "VETO", "LIFT_VETO", "VERDICT", "MEMORY_WRITE"]


class AgentMessage(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)
    schema_: Literal["naci.agent-message/1"] = Field(default=MESSAGE_SCHEMA, alias="schema")
    id: str
    run_id: str
    round: int
    sender: str
    to: str = "*"
    kind: MessageKind
    topic: str
    text: str = Field(max_length=600)
    body: dict = {}
    refs: list[str] = []
    reply_to: str | None = None

    def to_ci(self, subject_id: str):
        """The same message in CI's exchange format (pcim.exchange.AgentMessage)."""
        from pcim.exchange import AgentMessage as CIMessage

        return CIMessage(
            task_id=self.run_id[:64], project_id=subject_id[:64], sender=self.sender, recipient=self.to,
            goal=f"{self.kind}:{self.topic}"[:2000], claim=self.text, evidence_refs=list(self.refs),
            uncertainty=self.body.get("uncertainty"), requested_action=self.body.get("request"),
            timestamp=dt.datetime.now(dt.timezone.utc).isoformat(),
        )
