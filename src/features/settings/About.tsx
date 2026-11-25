import { ExternalLink } from 'lucide-react';
import { useRef, useState } from 'react';
import { BackButton } from '@/components/BackButton';
import { Card, PageHeader, SectionTitle } from '@/components/ui';
import research from '../../../seed/alternates.research.json';
import { useUI } from '@/store/ui';

export default function About() {
  const taps = useRef(0);
  const toast = useUI((s) => s.toast);
  const [showSources, setShowSources] = useState(false);
  return (
    <div className="pb-8">
      <PageHeader title="About" right={<BackButton to="/more" />} />
      <div className="space-y-3 px-4">
        <Card>
          <button
            type="button"
            className="text-left"
            onClick={() => {
              taps.current++;
              if (taps.current === 7) {
                try {
                  localStorage.setItem('repmate:dev', '1');
                } catch {
                  /* ignore */
                }
                toast('Developer tools enabled (More → Developer)');
              }
            }}
          >
            <p className="text-[20px] font-bold">Repmate</p>
            <p className="text-[15px] text-muted">Version {__APP_VERSION__}</p>
          </button>
          <p className="mt-2 text-[15px] text-text/85">Your offline gym coach and food diary. No account, no ads, no tracking. Everything stays on this phone.</p>
        </Card>
        <SectionTitle>The science</SectionTitle>
        <Card>
          <p className="text-[15px] text-text/85">
            Progression is double progression with reps-in-reserve targets, an 8-week wave with a deload, accessory rotation every 4 weeks, Express sessions built on minimum-effective-dose research, and a gentle conditioning ramp.
          </p>
          <button type="button" onClick={() => setShowSources(!showSources)} className="mt-2 min-h-[44px] text-[15px] font-semibold text-primary-ink" aria-expanded={showSources}>
            {showSources ? 'Hide' : 'Show'} {research.sources.length} sources
          </button>
          {showSources && (
            <ul className="mt-1 space-y-1.5 text-[13px] text-muted">
              {research.sources.map((s) => (
                <li key={s}>{s}</li>
              ))}
            </ul>
          )}
          <p className="mt-2 text-caption text-muted">General fitness guidance, not medical advice. Check with a doctor if you have a health condition.</p>
        </Card>
        <SectionTitle>Licences</SectionTitle>
        <Card className="space-y-2 text-[15px]">
          <p>
            Exercise images from <strong>free-exercise-db</strong> (public domain, Unlicense).
          </p>
          <p>
            <strong>Inter</strong> typeface (SIL Open Font License). <strong>Lucide</strong> icons (ISC). React, Dexie, Recharts, date-fns, Zod, fflate (MIT / Apache-2.0).
          </p>
          <a href="https://github.com/yuhonas/free-exercise-db" target="_blank" rel="noopener noreferrer" className="inline-flex min-h-[44px] items-center gap-1 font-semibold text-primary-ink">
            free-exercise-db <ExternalLink size={14} aria-hidden />
          </a>
        </Card>
      </div>
    </div>
  );
}
