import type { Metadata } from 'next';
import { Container, PageHead } from '@/components/ui';

export const metadata: Metadata = { title: 'Team' };

const PEOPLE = [
  {
    name: 'Nishanth Revuri',
    role: 'Engineering: signal processing, the collective, Contextual Intelligence',
    bio: 'First-year PhD student in mathematics and AI at MIT. Before that, quantitative finance at UBS and on Citadel’s EQR team. Built NeuroAssist’s signal engine, Contextual Intelligence, and this collective.',
  },
  {
    name: 'Jayashabari Shankar',
    role: 'Clinical and neuroscience',
    bio: 'Leads the clinical and neuroscience side of NeuroAssist: which eye movements matter, how they are examined at the bedside, and what a measurement must show before anyone should rely on it.',
  },
];

export default function Team() {
  return (
    <>
      <PageHead title="Team" lede="Two people, built for MIT ScienceClaw 2026." />
      <Container className="grid gap-6 pb-10 md:grid-cols-2">
        {PEOPLE.map((p) => (
          <article key={p.name} className="rounded-2xl border border-rule bg-panel p-7">
            <h2 className="t-h2">{p.name}</h2>
            <p className="mt-2 text-signal">{p.role}</p>
            <p className="t-body mt-5">{p.bio}</p>
          </article>
        ))}
      </Container>
    </>
  );
}
