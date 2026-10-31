import type { Metadata } from 'next';
import Link from 'next/link';
import { PageHead, Section } from '@/components/ui';

export const metadata: Metadata = { title: 'Science' };

export default function Science() {
  return (
    <>
      <PageHead title="What a camera can measure, and what it cannot"
        lede="Eye movements are a window onto the brainstem and the vestibular system. Measuring them with an ordinary camera is possible, and fragile in specific, testable ways." />

      <Section title="The measurement">
        <div className="prose-lab">
          <p>
            When the eyes try to hold still on a target, some people’s eyes drift slowly to one side and snap back: nystagmus. The speed of that slow drift, the slow-phase velocity in degrees per second,
            is the quantity NeuroAssist estimates. Clinicians watch it change over hours and days, for example as vestibular function recovers.
          </p>
          <p>
            NeuroAssist finds the iris in each camera frame, converts its position to a gaze angle with a five-point calibration, detects the fast snaps, and fits straight lines to the slow drifts between them.
            The median slope, with a distribution-free 95% interval, is the reported value. Six checks must pass first, or it reports nothing.
          </p>
        </div>
      </Section>

      <Section title="Why it is fragile">
        <div className="prose-lab">
          <ul>
            <li><strong className="text-fg">Head motion.</strong> The camera sees the iris relative to the face. A head that turns one degree moves the estimated gaze by about one degree. Small, slow head turns look exactly like slow-phase drift.</li>
            <li><strong className="text-fg">Timing.</strong> A browser hands frames to the page late and in batches. If they are stamped when they arrive, velocities computed from those stamps are wrong.</li>
            <li><strong className="text-fg">Lost frames.</strong> Blinks, glare and a turned face remove frames. Long gaps leave too few clean drifts to fit.</li>
            <li><strong className="text-fg">Resolution.</strong> A 30 fps webcam cannot resolve small, fast resets. Below about 2 deg/s, NeuroAssist’s engine can pass a biased value; see <Link href="/research#blindspot" className="underline">the blind spot</Link>.</li>
            <li><strong className="text-fg">People differ.</strong> A value that is ordinary for one person is a large change for another. A comparison needs that person’s history, and history needs to be trustworthy.</li>
          </ul>
        </div>
      </Section>

      <Section title="Our method" aside="Everything numeric is deterministic code. No language model computes, estimates or rounds a value.">
        <div className="prose-lab">
          <p>We do not try to make the camera better. We make the reasoning around each measurement harder to fool, by giving it to agents that each see a different part of the evidence:</p>
          <ul>
            <li>Signal quality recomputes the number from raw frames, checks that it matches what the device reported, and inspects timing, gaps and head coupling.</li>
            <li>Memory asks Contextual Intelligence for the subject’s baseline as it stood before this session, from trusted records only, and reports any conflicts CI has recorded.</li>
            <li>Physiology compares the measurement with that baseline. It never sees the raw trace, so it cannot talk itself into accepting a bad recording.</li>
            <li>The skeptic looks at the head channel on its own, asks for re-analyses that test alternative explanations, re-derives every claim from its evidence, and challenges what does not hold.</li>
            <li>The evidence auditor certifies a claim only if every piece of evidence it cites exists, is intact, is adequate and has survived every challenge.</li>
          </ul>
          <p>The result is one of four answers: a change, no change, a valid measurement that cannot yet be compared, or an abstention with the reason.</p>
        </div>
      </Section>
    </>
  );
}
