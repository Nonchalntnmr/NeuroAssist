import heldout from '@/benchmark/results/heldout.summary.json';
import blind from '@/benchmark/results/engine-blindspot.json';

export type SysKey = 'deterministic' | 'single_agent' | 'collective_no_history' | 'collective_naive_history' | 'collective_ci' | 'monolith_ci';
export const RESULTS = heldout as unknown as {
  split: string; n_cases: number; cases_sha256: string; generated_at: string; label: string;
  systems: Record<SysKey, { label: string; accuracy: number; unsupported_conclusion_rate: number; appropriate_abstention: number; over_abstention: number;
    artifact_detection_recall: number; harmful_artifact_caught: number; artifact_false_flag_rate: number; baseline_retrieval_jaccard: number | null;
    evidence_traceability: number | null; latency_ms_median: number; latency_ms_p95: number; llm_tokens: number }>;
  per_type: Record<SysKey, Record<string, { accuracy: number; unsupported: number; n: number }>>;
  faults: Record<string, { accuracy: number; unsupported_conclusion_rate: number; over_abstention: number }>;
  monolith_faults: Record<string, { accuracy: number; unsupported_conclusion_rate: number; over_abstention: number }>;
};
export const BLINDSPOT = blind as { rows: { spv: number; pass_rate: number; mean_abs_error: number | null; mean_ci_hw: number | null; ci_coverage: number | null }[]; n_per_point: number };
export const SYS_ORDER: SysKey[] = ['deterministic', 'single_agent', 'collective_no_history', 'collective_naive_history', 'collective_ci', 'monolith_ci'];
export const pct = (v: number | null | undefined, d = 1) => (v === null || v === undefined ? 'n/a' : `${(v * 100).toFixed(d)}%`);
export const TYPE_LABEL: Record<string, string> = {
  clean: 'Clean measurement', tracking_artifact: 'Tracking artifact', missing_frames: 'Missing frames', irregular_timestamps: 'Irregular timestamps',
  insufficient_baseline: 'Insufficient baseline', misleading_change: 'Misleading apparent change', true_change: 'True synthetic change',
  conflicting_history: 'Conflicting historical observations', change_with_incidental_artifact: 'Change with incidental artifact',
};
