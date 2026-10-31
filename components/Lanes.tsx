'use client';
import { AGENTS, agentColor, agentShort, type Msg } from '@/lib/api';

const KIND: Record<string, { label: string; tone: string }> = {
  FINDING: { label: 'Finding', tone: 'text-muted' },
  CLAIM: { label: 'Claim', tone: 'text-fg' },
  EVIDENCE_REQUEST: { label: 'Asks for evidence', tone: 'text-memory' },
  EVIDENCE: { label: 'Provides evidence', tone: 'text-memory' },
  CHALLENGE: { label: 'Challenge', tone: 'text-challenge' },
  VETO: { label: 'Veto', tone: 'text-veto' },
  REVISION: { label: 'Revision', tone: 'text-challenge' },
  RESOLVE: { label: 'Resolved', tone: 'text-ok' },
  VERDICT: { label: 'Verdict', tone: 'text-fg' },
  MEMORY_WRITE: { label: 'Writes to CI', tone: 'text-memory' },
};

/** Swimlanes: one column per agent, one row per round. Who acted, when, and in reply to whom. */
export function Lanes({ messages, upTo, highlight }: { messages: Msg[]; upTo?: number; highlight?: (m: Msg) => boolean }) {
  const shown = upTo === undefined ? messages : messages.filter((m) => m.round <= upTo);
  const rounds = [...new Set(shown.map((m) => m.round))].sort((a, b) => a - b);
  const byId = Object.fromEntries(messages.map((m) => [m.id, m]));
  return (
    <div className="overflow-hidden rounded-xl border border-rule bg-panel">
      {/* Desktop: lanes */}
      <div className="hidden md:block">
        <div className="grid grid-cols-[56px_repeat(5,minmax(0,1fr))] border-b border-rule text-sm">
          <div className="px-3 py-3 text-faint">Round</div>
          {AGENTS.map((a) => (
            <div key={a.key} className="flex items-center gap-2 border-l border-rule px-3 py-3 font-medium">
              <span className="h-2.5 w-2.5 rounded-sm" style={{ background: a.color }} aria-hidden />
              {a.short}
            </div>
          ))}
        </div>
        {rounds.map((r) => (
          <div key={r} className="grid grid-cols-[56px_repeat(5,minmax(0,1fr))] border-b border-rule last:border-0">
            <div className="readout px-3 py-3 text-sm text-faint">{r}</div>
            {AGENTS.map((a) => (
              <div key={a.key} className="space-y-2 border-l border-rule p-2">
                {shown.filter((m) => m.round === r && m.sender === a.key).map((m) => (
                  <Card key={m.id} m={m} reply={m.reply_to ? byId[m.reply_to] : undefined} hl={highlight?.(m)} />
                ))}
              </div>
            ))}
          </div>
        ))}
      </div>
      {/* Mobile: single column */}
      <ol className="divide-y divide-rule md:hidden">
        {shown.map((m) => (
          <li key={m.id} className="p-3">
            <div className="mb-1 flex items-center gap-2 text-xs text-muted">
              <span className="h-2 w-2 rounded-sm" style={{ background: agentColor(m.sender) }} aria-hidden />
              <span className="font-medium text-fg">{agentShort(m.sender)}</span>
              <span>round {m.round}</span>
            </div>
            <Card m={m} reply={m.reply_to ? byId[m.reply_to] : undefined} hl={highlight?.(m)} bare />
          </li>
        ))}
      </ol>
    </div>
  );
}

function Card({ m, reply, hl, bare }: { m: Msg; reply?: Msg; hl?: boolean; bare?: boolean }) {
  const k = KIND[m.kind] ?? { label: m.kind, tone: 'text-muted' };
  return (
    <div className={`${bare ? '' : 'rounded-lg border p-2.5'} ${hl ? 'border-challenge/60 bg-challenge/[0.06]' : 'border-rule2/70 bg-raised/60'} transition-colors`}
      style={bare ? undefined : { borderLeft: `2px solid ${agentColor(m.sender)}` }}>
      <p className={`text-xs font-semibold ${k.tone}`}>
        {k.label}
        {m.to !== '*' && <span className="font-normal text-faint"> to {agentShort(m.to)}</span>}
      </p>
      <p className="mt-1 text-[0.86rem] leading-snug text-fg/90">{m.text}</p>
      {reply && <p className="mt-1.5 text-xs text-faint">In reply to {agentShort(reply.sender)}: {reply.kind.toLowerCase().replace('_', ' ')}</p>}
      {m.refs.length > 0 && <p className="readout mt-1.5 truncate text-[0.7rem] text-faint" title={m.refs.join(' ')}>{m.refs.join(' ')}</p>}
    </div>
  );
}
