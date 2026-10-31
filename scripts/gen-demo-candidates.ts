import { writeFileSync } from 'node:fs';
import { makeCase, CASE_TYPES } from '../lib/scenarios';
const out = [];
for (const type of CASE_TYPES) for (let i = 0; i < 8; i++) out.push(makeCase(type, i, 'demo', 42));
writeFileSync('/tmp/claude-0/demo-cands.json', JSON.stringify({ cases: out }));
