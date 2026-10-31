'use client';
import { CartesianGrid, ComposedChart, Line, ReferenceArea, ReferenceLine, ResponsiveContainer, Scatter, Tooltip, XAxis, YAxis } from 'recharts';
import type { SessionRecord } from '@/lib/contract';

const AX = { stroke: '#243341', tick: { fill: '#8796A3', fontSize: 12 }, tickLine: false };
const TIP = { contentStyle: { background: '#101820', border: '1px solid #243341', borderRadius: 8, color: '#E4ECF1', fontSize: 13 }, labelStyle: { color: '#8796A3' } };

/** History of one subject: each session as a point, the CI baseline as a band, the new session in teal. */
export function BaselineChart({ history, target, baseline, height = 260 }: {
  history: SessionRecord[]; target: SessionRecord; height?: number;
  baseline?: { median: number | null; spread: number | null; used: { session_id: string }[]; excluded: { session_id: string }[] } | null;
}) {
  const t0 = Date.parse(history[0]?.recorded_at ?? target.recorded_at);
  const day = (iso: string) => Math.round((Date.parse(iso) - t0) / 864e5);
  const used = new Set(baseline?.used.map((u) => u.session_id) ?? []);
  const excluded = new Set(baseline?.excluded.map((u) => u.session_id) ?? []);
  const pt = (r: SessionRecord) => ({ day: day(r.recorded_at), v: r.measurement.value, id: r.session_id, label: r.provenance.label, lo: r.measurement.ci_low, hi: r.measurement.ci_high });
  const measured = history.filter((h) => h.measurement.value !== null);
  const inBase = measured.filter((h) => (baseline ? used.has(h.session_id) : h.provenance.label !== 'PRERECORDED')).map(pt);
  const out = measured.filter((h) => (baseline ? excluded.has(h.session_id) : h.provenance.label === 'PRERECORDED')).map(pt);
  const tgt = target.measurement.value !== null ? [pt(target)] : [];
  const all = [...inBase, ...out, ...tgt].map((p) => p.v as number);
  const lo = Math.floor(Math.min(...all, baseline?.median ?? all[0] ?? 0) - 1.2);
  const hi = Math.ceil(Math.max(...all, baseline?.median ?? all[0] ?? 0) + 1.2);
  const med = baseline?.median ?? null;
  const sp = baseline?.spread ?? null;
  return (
    <figure>
      <div style={{ height }} role="img" aria-label="Slow-phase velocity of each session over time, with the personal baseline band">
        <ResponsiveContainer>
          <ComposedChart margin={{ top: 10, right: 16, bottom: 4, left: -8 }}>
            <CartesianGrid stroke="#18232D" vertical={false} />
            <XAxis type="number" dataKey="day" domain={['dataMin - 3', 'dataMax + 3']} {...AX} label={{ value: 'days since first session', fill: '#5A6976', fontSize: 12, position: 'insideBottomRight', dy: 10 }} />
            <YAxis type="number" dataKey="v" domain={[lo, hi]} {...AX} width={52} tickFormatter={(v) => `${v}`} />
            {med !== null && sp !== null && <ReferenceArea y1={med - 3 * sp} y2={med + 3 * sp} fill="#3987e5" fillOpacity={0.09} stroke="none" />}
            {med !== null && <ReferenceLine y={med} stroke="#3987e5" strokeDasharray="4 4" strokeWidth={1.5} />}
            <Tooltip {...TIP} cursor={false} formatter={(v: number) => [`${v?.toFixed?.(2)} deg/s`, 'SPV']} labelFormatter={() => ''} />
            <Scatter name="Baseline session" data={inBase} fill="#3987e5" shape="circle" />
            <Scatter name="Excluded record" data={out} fill="#06090C" stroke="#FF7A6B" strokeWidth={2} shape="diamond" />
            <Scatter name="New session" data={tgt} fill="#3ED6C5" stroke="#06090C" strokeWidth={2} shape="circle" />
          </ComposedChart>
        </ResponsiveContainer>
      </div>
      <figcaption className="t-small mt-2 flex flex-wrap gap-x-5 gap-y-1">
        <span><Dot c="#3987e5" /> Session in the baseline</span>
        {out.length > 0 && <span><Dot c="#FF7A6B" hollow /> Record left out (lower trust)</span>}
        <span><Dot c="#3ED6C5" /> New session</span>
        {med !== null && <span><span className="mr-1.5 inline-block h-2 w-5 align-middle" style={{ background: '#3987e533' }} />Baseline ± 3 spreads (deg/s)</span>}
      </figcaption>
    </figure>
  );
}

function Dot({ c, hollow }: { c: string; hollow?: boolean }) {
  return <span className="mr-1.5 inline-block h-2.5 w-2.5 rounded-full align-middle" style={hollow ? { border: `2px solid ${c}` } : { background: c }} aria-hidden />;
}

/** The raw trace an agent inspects: gaze (deg) and head yaw (deg). */
export function TraceChart({ trace, height = 220, showHead = true }: { trace: NonNullable<SessionRecord['trace']>; height?: number; showHead?: boolean }) {
  const data = trace.t.map((t, i) => ({ t, x: trace.x[i], h: trace.head?.[i] ?? null }));
  return (
    <figure>
      <div style={{ height }} role="img" aria-label="Gaze position and head yaw over the recording">
        <ResponsiveContainer>
          <ComposedChart data={data} margin={{ top: 8, right: 16, bottom: 4, left: -8 }}>
            <CartesianGrid stroke="#18232D" vertical={false} />
            <XAxis dataKey="t" type="number" domain={[0, 'dataMax']} {...AX} tickFormatter={(v) => `${Math.round(v)}s`} />
            <YAxis {...AX} width={52} />
            <Tooltip {...TIP} labelFormatter={(v: number) => `${v.toFixed(2)} s`} formatter={(v: number, n: string) => [`${v?.toFixed?.(2)}°`, n === 'x' ? 'Gaze' : 'Head yaw']} />
            <Line dataKey="x" stroke="#3ED6C5" strokeWidth={1.5} dot={false} isAnimationActive={false} connectNulls={false} />
            {showHead && trace.head && <Line dataKey="h" stroke="#F0B54A" strokeWidth={1.5} dot={false} isAnimationActive={false} strokeDasharray="1 0" />}
          </ComposedChart>
        </ResponsiveContainer>
      </div>
      <figcaption className="t-small mt-2 flex flex-wrap gap-x-5">
        <span><span className="mr-1.5 inline-block h-0.5 w-5 bg-signal align-middle" />Gaze (degrees)</span>
        {showHead && trace.head && <span><span className="mr-1.5 inline-block h-0.5 w-5 bg-challenge align-middle" />Head yaw (degrees)</span>}
        <span className="text-faint">Gaps are lost frames.</span>
      </figcaption>
    </figure>
  );
}
