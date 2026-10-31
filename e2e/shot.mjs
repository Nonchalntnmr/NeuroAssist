// Screenshot helper: node e2e/shot.mjs <url> <out.png> [width] [height] [waitMs] [fullPage 1|0] [nextClicks]
import { chromium } from 'playwright';
const [,, url, out, w = '1440', h = '900', wait = '4000', full = '1', clicks = '0'] = process.argv;
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: +w, height: +h } });
const errs = [];
p.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
p.on('pageerror', (e) => errs.push(String(e)));
await p.goto(url, { waitUntil: 'networkidle' });
await p.waitForTimeout(+wait);
for (let i = 0; i < +clicks; i++) { await p.getByRole('button', { name: 'Next step' }).click(); await p.waitForTimeout(700); }
await p.screenshot({ path: out, fullPage: full === '1' });
console.log('errors:', JSON.stringify(errs).slice(0, 800));
await b.close();
