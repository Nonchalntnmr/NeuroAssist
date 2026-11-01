'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import type { SessionRecord } from './contract';

export type AgentKey = 'signal_quality' | 'contextual_memory' | 'physiology' | 'skeptic' | 'auditor';
export interface Msg {
  id: string; round: number; sender: AgentKey; to: string; kind: string; topic: string; text: string;
  body: Record<string, any>; refs: string[]; reply_to: string | null;
}
export interface Ev { id: string; type: string; producer: string; sha256: string; quality: string; provenance: any; derived_from: string[]; content: any; canonical?: string }
export interface Collective {
  decision: string; variant: string; messages: Msg[]; evidence: Ev[]; latency_ms: number; rounds: number;
  audit: { entries: number; head: string; chain_ok: boolean }; access_log: { agent: string; input: string }[];
  artifact_causes: string[]; baseline_ids: string[] | null; claim: any; ci_calls: any[]; vetoes: { by: string; text: string }[];
  agents: { key: AgentKey; name: string; role: string; access: string[]; fault: string | null }[];
}
export interface RunResponse {
  schema: string; computed: 'live'; labels: string[]; collective: Collective; server_ms: number;
  compare?: { deterministic: { decision: string }; single_agent: { decision: string; claim?: any } };
  roles: Record<AgentKey, { name: string; role: string }>;
}

export const AGENTS: { key: AgentKey; short: string; color: string }[] = [
  // Validated categorical palette (dataviz validator, dark surface #0B1117: lightness band, chroma,
  // CVD and normal-vision separation all pass). Always shown with the agent's name.
  { key: 'signal_quality', short: 'Signal quality', color: '#199e70' },
  { key: 'contextual_memory', short: 'Memory (CI)', color: '#3987e5' },
  { key: 'physiology', short: 'Physiology', color: '#d55181' },
  { key: 'skeptic', short: 'Skeptic', color: '#c98500' },
  { key: 'auditor', short: 'Auditor', color: '#9085e9' },
];
export const agentColor = (k: string) => AGENTS.find((a) => a.key === k)?.color ?? '#8796A3';
export const agentShort = (k: string) => AGENTS.find((a) => a.key === k)?.short ?? k;

export async function runCollective(target: SessionRecord, history: SessionRecord[], opts: { variant?: string; faults?: Record<string, string>; canonical?: boolean } = {}): Promise<RunResponse> {
  const res = await fetch('/api/py/v1/collective/run', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ target, history, variant: opts.variant ?? 'ci', faults: opts.faults ?? {}, canonical: !!opts.canonical }),
  });
  if (!res.ok) {
    let detail = `${res.status}`;
    try { const j = await res.json(); detail = j.detail ? (typeof j.detail === 'string' ? j.detail : JSON.stringify(j.detail).slice(0, 300)) : j.error ?? detail; } catch { /* not JSON */ }
    throw new Error(`The collective service answered ${res.status}: ${detail}`);
  }
  return res.json();
}

export function useRun(target: SessionRecord | null, history: SessionRecord[], opts: { variant?: string; faults?: Record<string, string>; canonical?: boolean } = {}) {
  const [data, setData] = useState<RunResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const seq = useRef(0);
  const key = JSON.stringify([target?.session_id, opts]);
  const run = useCallback(async () => {
    if (!target) return;
    const n = ++seq.current;
    setLoading(true); setError(null);
    try {
      const d = await runCollective(target, history, opts);
      if (n === seq.current) setData(d);
    } catch (e) {
      if (n === seq.current) { setError(e instanceof Error ? e.message : String(e)); setData(null); }
    } finally {
      if (n === seq.current) setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
  useEffect(() => { void run(); }, [run]);
  return { data, error, loading, rerun: run };
}

export const DECISION_TEXT: Record<string, { label: string; color: string; plain: string }> = {
  CHANGE: { label: 'Change', color: '#3ED6C5', plain: 'Evidence-backed change from this subject’s baseline.' },
  NO_CHANGE: { label: 'No change', color: '#7FD88F', plain: 'Within this subject’s usual range.' },
  NO_BASELINE: { label: 'Measured, not compared', color: '#6E9BFF', plain: 'A valid measurement, but too little history to compare.' },
  ABSTAIN: { label: 'Abstain', color: '#FF7A6B', plain: 'The evidence does not support a conclusion. Remeasure.' },
};
