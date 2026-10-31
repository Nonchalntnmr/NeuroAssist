import Link from 'next/link';
import { Container } from '@/components/ui';

export default function NotFound() {
  return (
    <Container className="py-28">
      <h1 className="t-h1">This page does not exist</h1>
      <p className="t-lede mt-4 max-w-[52ch]">The address may be mistyped, or the page was moved. The guided demo is the best place to start.</p>
      <div className="mt-8 flex gap-3"><Link href="/demo" className="btn btn-primary">Explore live demo</Link><Link href="/" className="btn btn-ghost">Home</Link></div>
    </Container>
  );
}
