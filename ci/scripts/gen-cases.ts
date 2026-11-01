/**
 * Generate the benchmark suites (SYNTHETIC). dev: used to choose thresholds. heldout: generated
 * with a different salt, never looked at while tuning; results are reported on it.
 *   npx tsx scripts/gen-cases.ts
 */
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { makeSuite, CASE_TYPES } from '../lib/scenarios';
import { ENGINE_VERSION } from '../lib/neuroassist/engine';

const SUITES = [
  { split: 'dev', salt: 7, perType: 12 },
  { split: 'heldout', salt: 2026, perType: 30 },
];
mkdirSync('benchmark/cases', { recursive: true });
const manifest: Record<string, unknown> = { engine: ENGINE_VERSION, case_types: CASE_TYPES, label: 'SYNTHETIC', suites: {} };
for (const s of SUITES) {
  const cases = makeSuite(s.split, s.salt, s.perType);
  const body = JSON.stringify({ schema: 'naci.cases/1', label: 'SYNTHETIC', ...s, engine: ENGINE_VERSION, cases });
  writeFileSync(`benchmark/cases/${s.split}.json`, body);
  const tally: Record<string, Record<string, number>> = {};
  for (const c of cases) {
    tally[c.type] ??= {};
    tally[c.type]![c.truth.decision] = (tally[c.type]![c.truth.decision] ?? 0) + 1;
  }
  (manifest.suites as Record<string, unknown>)[s.split] = {
    ...s, n: cases.length, sha256: createHash('sha256').update(body).digest('hex'), truth_by_type: tally,
  };
  console.log(s.split, cases.length, JSON.stringify(tally));
}
writeFileSync('benchmark/cases/MANIFEST.json', JSON.stringify(manifest, null, 2));
