import { makeCase, type Case, type CaseType } from './scenarios';

/** Named SYNTHETIC scenarios. Each one is a deterministic case from lib/scenarios.ts (split "demo",
 *  salt 42), generated in the browser by NeuroAssist's own simulator and engine. */
export const SCENARIOS: { key: string; type: CaseType; index: number; title: string; blurb: string }[] = [
  { key: 'artifact', type: 'tracking_artifact', index: 1, title: 'Apparent change, tracking slip',
    blurb: 'A new session reads far above this subject’s baseline. NeuroAssist’s gate passes it.' },
  { key: 'change', type: 'true_change', index: 1, title: 'True change',
    blurb: 'Slow-phase velocity really moved. The collective should say so.' },
  { key: 'conflict', type: 'conflicting_history', index: 3, title: 'Conflicting history',
    blurb: 'Unverified exported files disagree with every measured session.' },
  { key: 'clean', type: 'clean', index: 1, title: 'Routine follow-up',
    blurb: 'A normal session inside the subject’s usual range.' },
  { key: 'misleading', type: 'misleading_change', index: 0, title: 'Misleading difference',
    blurb: 'Far from the last visit, which was an unusually low day, but within the usual range.' },
  { key: 'nobaseline', type: 'insufficient_baseline', index: 1, title: 'New subject',
    blurb: 'Only one prior session. A comparison is not yet possible.' },
  { key: 'incidental', type: 'change_with_incidental_artifact', index: 3, title: 'Change with slight head motion',
    blurb: 'A real change plus a little head movement that does not explain it.' },
  { key: 'timing', type: 'irregular_timestamps', index: 0, title: 'Batched timestamps',
    blurb: 'Frames were stamped when they arrived, not when they were captured.' },
];

const cache = new Map<string, Case>();
export function scenario(key: string): { meta: (typeof SCENARIOS)[number]; c: Case } {
  const meta = SCENARIOS.find((s) => s.key === key) ?? SCENARIOS[0]!;
  let c = cache.get(meta.key);
  if (!c) {
    c = makeCase(meta.type, meta.index, 'demo', 42);
    cache.set(meta.key, c);
  }
  return { meta, c };
}
