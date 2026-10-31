'use client';
import Link from 'next/link';
import { useEffect, useMemo, useRef, useState } from 'react';
import { scenario } from '@/lib/demo';
import { runCollective, type RunResponse } from '@/lib/api';

/** Oscilloscope of a real (SYNTHETIC) NeuroAssist trace: the demo case's new session. It is drawn
 *  once, left to right; when the live run comes back, the Skeptic's finding is annotated with the
 *  numbers the collective actually computed. */
export function SignalHero() {
  const { c } = useMemo(() => scenario('artifact'), []);
  const tr = c.target.trace!;
  const ref = useRef<HTMLCanvasElement>(null);
  const [run, setRun] = useState<RunResponse | null>(null);
  const [failed, setFailed] = useState(false);
  const [done, setDone] = useState(false);

  useEffect(() => {
    runCollective(c.target, c.history).then(setRun).catch(() => setFailed(true));
  }, [c]);

  useEffect(() => {
    const cv = ref.current;
    if (!cv) return;
    const ctx = cv.getContext('2d');
    if (!ctx) return;
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    let raf = 0;
    const start = performance.now();
    const dur = reduce ? 0 : 3200;
    const draw = (now: number) => {
      const dpr = window.devicePixelRatio || 1;
      const w = cv.clientWidth, h = cv.clientHeight;
      if (cv.width !== w * dpr) { cv.width = w * dpr; cv.height = h * dpr; }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      const n = tr.t.length;
      const frac = dur ? Math.min(1, (now - start) / dur) : 1;
      const xs = tr.x.filter((v): v is number => v !== null);
      const lo = Math.min(...xs), hi = Math.max(...xs);
      const T = tr.t[n - 1]!;
      const px = (t: number) => (t / T) * w;
      const pyG = (v: number) => h * 0.12 + (1 - (v - lo) / (hi - lo || 1)) * h * 0.52;
      const heads = (tr.head ?? []).filter((v): v is number => v !== null);
      const hlo = Math.min(...heads, -0.5), hhi = Math.max(...heads, 0.5);
      const pyH = (v: number) => h * 0.74 + (1 - (v - hlo) / (hhi - hlo || 1)) * h * 0.18;
      // Grid: one line per second.
      ctx.strokeStyle = '#111b24'; ctx.lineWidth = 1;
      for (let s = 0; s <= T; s += 1) { ctx.beginPath(); ctx.moveTo(px(s), 0); ctx.lineTo(px(s), h); ctx.stroke(); }
      const until = frac * T;
      const path = (ys: (number | null)[], py: (v: number) => number, color: string, width: number, glow: boolean) => {
        ctx.save();
        if (glow) { ctx.shadowColor = color; ctx.shadowBlur = 10; }
        ctx.strokeStyle = color; ctx.lineWidth = width; ctx.lineJoin = 'round';
        ctx.beginPath();
        let pen = false;
        for (let i = 0; i < n; i++) {
          const t = tr.t[i]!; if (t > until) break;
          const v = ys[i];
          if (v === null || v === undefined) { pen = false; continue; }
          if (!pen) { ctx.moveTo(px(t), py(v)); pen = true; } else ctx.lineTo(px(t), py(v));
        }
        ctx.stroke(); ctx.restore();
      };
      path(tr.x, pyG, '#3ED6C5', 1.8, true);
      if (tr.head) path(tr.head, pyH, '#F0B54A', 1.4, false);
      // Write head
      if (frac < 1) {
        ctx.fillStyle = '#3ED6C5'; ctx.beginPath(); ctx.arc(px(until), h * 0.12, 2.5, 0, Math.PI * 2); ctx.fill();
        raf = requestAnimationFrame(draw);
      } else setDone(true);
    };
    raf = requestAnimationFrame(draw);
    const onResize = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(draw); };
    window.addEventListener('resize', onResize);
    return () => { cancelAnimationFrame(raf); window.removeEventListener('resize', onResize); };
  }, [tr]);

  const col = run?.collective;
  const cf = col?.messages.find((m) => m.kind === 'EVIDENCE' && m.topic === 'counterfactual');
  const veto = col?.messages.find((m) => m.kind === 'VETO' && m.sender === 'skeptic');
  const dev = c.target.measurement.value;

  return (
    <section className="relative overflow-hidden border-b border-rule">
      <div className="mx-auto max-w-[1240px] px-4 pb-10 pt-14 sm:px-6 sm:pt-20">
        <h1 className="t-display max-w-[11ch]">The nervous system interface</h1>
        <p className="t-lede mt-6 max-w-[56ch]">
          A decentralized scientific intelligence system that observes neurological signals, remembers context, and challenges its own conclusions.
        </p>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link href="/demo" className="btn btn-primary">Explore live demo</Link>
          <Link href="/science" className="btn btn-ghost">See the science</Link>
        </div>
      </div>
      <div className="relative mx-auto max-w-[1240px] px-4 sm:px-6">
        <div className="relative h-[300px] rounded-t-2xl border border-b-0 border-rule bg-[radial-gradient(120%_100%_at_50%_0%,#0d1820_0%,#06090C_70%)] sm:h-[360px]">
          <canvas ref={ref} className="absolute inset-0 h-full w-full" aria-hidden />
          <div className="pointer-events-none absolute left-4 top-3 text-xs text-muted">Gaze, degrees</div>
          <div className="pointer-events-none absolute bottom-[19%] left-4 text-xs text-challenge/80">Head yaw, degrees</div>
          <div className={`absolute bottom-4 right-4 max-w-[340px] rounded-lg border border-challenge/40 bg-ink/90 p-3 text-sm backdrop-blur transition-opacity duration-500 ${done && (col || failed) ? 'opacity-100' : 'opacity-0'}`} aria-live="polite">
            {col && cf && veto ? (
              <>
                <p className="font-semibold text-challenge">Skeptic agent</p>
                <p className="mt-1 text-fg/90">
                  NeuroAssist’s gate passed this session at <span className="readout">{dev?.toFixed(2)}</span> deg/s.
                  With head motion removed it reads <span className="readout">{(cf.body.est as number)?.toFixed(2)}</span>. Vetoed as a tracking artifact.
                </p>
                <p className="mt-1.5 text-xs text-muted">Computed live in {run!.server_ms.toFixed(0)} ms. <Link href="/demo" className="pointer-events-auto underline">Walk through it</Link></p>
              </>
            ) : failed ? (
              <p className="text-muted">The live collective did not answer. The guided demo explains this case step by step.</p>
            ) : null}
          </div>
        </div>
        <p className="t-small border-x border-b border-rule bg-panel px-4 py-2.5 sm:rounded-b-2xl">
          Synthetic recording from NeuroAssist’s own simulator, with a head-coupled tracking slip added. Not a patient.
        </p>
      </div>
    </section>
  );
}
