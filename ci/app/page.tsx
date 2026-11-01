import Link from 'next/link';
import { SignalHero } from '@/components/home/SignalHero';
import { Container } from '@/components/ui';
import { RESULTS, pct } from '@/lib/results';
import { ArchitectureDiagram } from '@/components/ArchitectureDiagram';

export default function Home() {
  const S = RESULTS.systems;
  const rows = [
    { k: 'deterministic' as const, name: 'NeuroAssist alone, compared with the last visit' },
    { k: 'single_agent' as const, name: 'One agent with every input' },
    { k: 'collective_ci' as const, name: 'The collective, with CI memory' },
  ];
  return (
    <>
      <SignalHero />

      <section className="border-b border-rule">
        <Container className="grid gap-12 py-20 lg:grid-cols-[1fr_1fr]">
          <div>
            <h2 className="t-h1 max-w-[16ch]">AI can read language. We’re teaching it to investigate neurological signals.</h2>
          </div>
          <div className="space-y-5">
            <p className="t-body">
              A phone or laptop camera can measure eye movement: how fast the eyes drift during fixation, whether they hold a target.
              Those numbers matter only against the same person’s history, and only if the recording can be trusted.
            </p>
            <p className="t-body">
              Webcams drop frames, browsers stamp time late, and a head that moves a degree looks like an eye that moved a degree.
              Each person also has their own normal. A single number, compared with a single previous visit, is easy to over-read.
            </p>
            <p className="t-body text-fg">
              NeuroAssist × CI gives every measurement to five independent agents. Each sees different evidence, any of them can stop a conclusion,
              and the system reports an evidence-backed observation or it abstains.
            </p>
          </div>
        </Container>
      </section>

      <section className="border-b border-rule">
        <Container className="py-20">
          <h2 className="t-h2">Three products, one boundary</h2>
          <p className="t-body mt-3 max-w-prose">
            NeuroAssist measures. Contextual Intelligence remembers. The collective, a separate application, reasons over both through a versioned contract,
            <code className="code">naci.session/1</code>. Neither parent repository is modified.
          </p>
          <div className="mt-10"><ArchitectureDiagram /></div>
        </Container>
      </section>

      <section className="border-b border-rule">
        <Container className="grid gap-10 py-20 lg:grid-cols-[minmax(0,380px)_1fr]">
          <div>
            <h2 className="t-h2">Measured, on cases it never saw</h2>
            <p className="t-body mt-3">
              {RESULTS.n_cases} synthetic held-out cases across nine controlled situations. Thresholds were frozen in a git commit before this set was run once.
            </p>
            <Link href="/benchmark" className="mt-6 inline-block text-signal underline">Full results, per case type and under faults</Link>
          </div>
          <div className="min-w-0 overflow-x-auto">
            <table className="tbl min-w-[560px]">
              <thead><tr><th>System</th><th className="num">Correct</th><th className="num">Unsupported conclusions</th><th className="num">Harmful artifacts caught</th></tr></thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.k} className={r.k === 'collective_ci' ? 'hl' : ''}>
                    <td>{r.name}</td>
                    <td className="num">{pct(S[r.k].accuracy)}</td>
                    <td className="num">{pct(S[r.k].unsupported_conclusion_rate)}</td>
                    <td className="num">{pct(S[r.k].harmful_artifact_caught)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="t-small mt-4 max-w-[70ch]">
              What we do not claim: a single program running the same checks matches the collective on accuracy ({pct(S.monolith_ci.accuracy)}).
              The collective’s measured advantage over that program is fault isolation: with one component corrupted, the program’s unsupported-conclusion rate
              rises to {pct(RESULTS.monolith_faults['contextual_memory:byzantine']!.unsupported_conclusion_rate)}; the collective’s stays at {pct(RESULTS.faults['contextual_memory:byzantine']!.unsupported_conclusion_rate)}.
              All data is synthetic. Nothing has been tested on patients.
            </p>
          </div>
        </Container>
      </section>

      <section>
        <Container className="flex flex-col items-start gap-6 py-20 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 className="t-h2 max-w-[24ch]">Watch the collective reject a number that looks like a finding</h2>
            <p className="t-body mt-3 max-w-prose">Ninety seconds, no account. Every message you see is computed when you press play.</p>
          </div>
          <Link href="/demo" className="btn btn-primary">Explore live demo</Link>
        </Container>
      </section>
    </>
  );
}
