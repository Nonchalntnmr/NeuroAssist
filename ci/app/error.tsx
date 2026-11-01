'use client';
import { Container } from '@/components/ui';

export default function ErrorPage({ error, reset }: { error: Error; reset: () => void }) {
  return (
    <Container className="py-28">
      <h1 className="t-h1">This page failed to load</h1>
      <p className="t-lede mt-4 max-w-[60ch]">{error.message || 'An unexpected error occurred in the browser.'} Reload the page, or try again below.</p>
      <button className="btn btn-primary mt-8" onClick={reset}>Try again</button>
    </Container>
  );
}
