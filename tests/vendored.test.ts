import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { analyze } from '../lib/neuroassist/analyze';
import { simulate } from '../lib/neuroassist/simulate';
import { makeCase, CASE_TYPES } from '../lib/scenarios';
import { SCENARIOS, scenario } from '../lib/demo';

describe('vendored NeuroAssist engine', () => {
  it('is byte-identical to the copy recorded from the parent repository', () => {
    const lines = readFileSync('lib/neuroassist/VENDORED.sha256', 'utf8').trim().split('\n');
    for (const l of lines) {
      const [hash, file] = l.split(/\s+/);
      expect(createHash('sha256').update(readFileSync(`lib/neuroassist/${file}`)).digest('hex'), file).toBe(hash);
    }
  });
  it('recovers slow-phase velocity in its accurate range', () => {
    for (const spv of [3, -4, 6]) {
      const tr = simulate({ seed: 11, spv, fps: 30, noise: 0.1, blinks: 2, lost: 2, dur: 10 });
      const a = analyze(tr.t, tr.x);
      expect(a.pass).toBe(true);
      expect(Math.abs(a.est - spv)).toBeLessThan(0.3);
    }
  });
});

describe('scenarios', () => {
  it('are deterministic', () => {
    for (const t of CASE_TYPES) expect(JSON.stringify(makeCase(t, 3, 'x', 5))).toBe(JSON.stringify(makeCase(t, 3, 'x', 5)));
  });
  it('label everything synthetic or prerecorded, never real', () => {
    for (const s of SCENARIOS) {
      const { c } = scenario(s.key);
      for (const r of [...c.history, c.target]) expect(['SYNTHETIC', 'PRERECORDED']).toContain(r.provenance.label);
    }
  });
  it('store numbers that follow from the stored trace', () => {
    const { c } = scenario('artifact');
    const tr = c.target.trace!;
    const a = analyze(tr.t, tr.x.map((v) => (v === null ? NaN : v)));
    expect(a.pass).toBe(c.target.measurement.status === 'MEASURED');
    expect(Math.abs(a.est - (c.target.measurement.value as number))).toBeLessThan(1e-3);
  });
  it('the guided-demo case passes NeuroAssist’s own gate', () => {
    expect(scenario('artifact').c.target.measurement.status).toBe('MEASURED');
    expect(scenario('artifact').c.truth.decision).toBe('ABSTAIN');
  });
});
