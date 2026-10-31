import { analyze, type Analysis } from './neuroassist/analyze';
import { ENGINE_VERSION } from './neuroassist/engine';
import { SESSION_SCHEMA, type DataLabel, type SessionRecord } from './contract';

const r4 = (v: number) => Math.round(v * 1e4) / 1e4;
const fin = (v: number) => (Number.isFinite(v) ? v : null);

/** Build a naci.session/1 record from a gaze trace using NeuroAssist's own engine and gate. */
export function toRecord(
  t: number[],
  x: number[],
  head: number[] | null,
  meta: { session_id: string; subject_id: string; recorded_at: string; label: DataLabel; source: string; engine?: string; generator?: Record<string, unknown> },
  withTrace = true,
): { record: SessionRecord; analysis: Analysis } {
  // Analyse exactly what is stored (rounded to 0.1 ms and 1e-4 deg), so the number follows from the
  // stored trace and anyone can recompute it.
  t = t.map(r4);
  x = x.map((v) => (Number.isFinite(v) ? r4(v) : NaN));
  if (head) head = head.map((v) => (Number.isFinite(v) ? r4(v) : NaN));
  const a = analyze(t, x);
  const record: SessionRecord = {
    schema: SESSION_SCHEMA,
    session_id: meta.session_id,
    subject_id: meta.subject_id,
    recorded_at: meta.recorded_at,
    protocol: 'FIXATION',
    provenance: { label: meta.label, source: meta.source, engine: meta.engine ?? ENGINE_VERSION, ...(meta.generator ? { generator: meta.generator } : {}) },
    measurement: {
      status: a.pass ? 'MEASURED' : 'ABSTAINED',
      metric: 'SLOW_PHASE_VELOCITY',
      unit: 'deg/s',
      value: a.pass ? r4(a.est) : null,
      ci_low: a.pass && a.ci ? r4(a.ci.lo) : null,
      ci_high: a.pass && a.ci ? r4(a.ci.hi) : null,
      windows: a.chunks.length,
    },
    quality: {
      valid_frac: r4(a.validFrac),
      fps: r4(a.fps),
      noise_deg: fin(a.sigma) === null ? null : r4(a.sigma),
      residual_ratio: (() => { const c = a.checks.find((k) => k.id === 'linearity'); return c && Number.isFinite(c.value) ? r4(c.value) : null; })(),
      checks: a.checks.map(({ id, label, show, rule, ok }) => ({ id, label, show, rule, ok })),
      abstain_reasons: a.checks.filter((c) => !c.ok).map((c) => c.fix),
    },
  };
  if (withTrace) {
    record.trace = {
      t: t.map(r4),
      x: x.map((v) => (Number.isFinite(v) ? r4(v) : null)),
      ...(head ? { head: head.map((v) => (Number.isFinite(v) ? r4(v) : null)) } : {}),
    };
  }
  return { record, analysis: a };
}
