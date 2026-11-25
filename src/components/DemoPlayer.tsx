import { Film, ImageIcon, Youtube } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { Exercise } from '@/domain/types';
import { demoSrc, useClipUrl, youtubeUrl } from '@/lib/clips';
import { useOnline } from '@/lib/online';
import { prefersReducedMotion } from '@/lib/platform';

/** Layer 1: 2-frame crossfade demo (offline). Layer 2: user's clip (preferred). Layer 3: YouTube link (online only). */
export function DemoPlayer({ exercise, className = '', compact }: { exercise: Exercise | undefined; className?: string; compact?: boolean }) {
  const clip = useClipUrl(exercise?.id);
  const online = useOnline();
  const [frame, setFrame] = useState<0 | 1>(0);
  const [mode, setMode] = useState<'clip' | 'demo'>('clip');
  const reduced = prefersReducedMotion();
  const showClip = !!clip && mode === 'clip';
  const src0 = demoSrc(exercise?.freeDbId, 0);
  const src1 = demoSrc(exercise?.freeDbId, 1);

  useEffect(() => {
    if (showClip || reduced || !src1) return;
    const t = setInterval(() => setFrame((f) => (f ? 0 : 1)), 900);
    return () => clearInterval(t);
  }, [showClip, reduced, src1]);

  return (
    <div className={`relative overflow-hidden rounded-card bg-white ${className}`}>
      {showClip ? (
        <video key={clip} src={clip} className="h-full w-full bg-black object-contain" muted loop playsInline autoPlay aria-label={`My clip: ${exercise?.name}`} />
      ) : src0 ? (
        <button type="button" className="relative block h-full w-full" onClick={() => reduced && setFrame((f) => (f ? 0 : 1))} aria-label={`${exercise?.name} demonstration`}>
          <img src={src0} alt="" className="absolute inset-0 h-full w-full object-contain" decoding="async" />
          {src1 && (
            <img
              src={src1}
              alt=""
              className="absolute inset-0 h-full w-full object-contain transition-opacity duration-300 ease-out"
              style={{ opacity: frame }}
              decoding="async"
            />
          )}
        </button>
      ) : (
        <div className="flex h-full w-full flex-col items-center justify-center gap-2 bg-surface2 p-4 text-center">
          <Film size={28} className="text-muted" aria-hidden />
          <p className="text-[15px] text-muted">{exercise?.cue ?? 'No demo yet. Record a clip of your trainer.'}</p>
        </div>
      )}
      {!compact && (
        <div className="absolute bottom-2 left-2 right-2 flex justify-between gap-2">
          {clip ? (
            <button
              type="button"
              onClick={() => setMode(mode === 'clip' ? 'demo' : 'clip')}
              className="flex min-h-[36px] items-center gap-1.5 rounded-full bg-black/70 px-3 text-[13px] font-semibold text-white backdrop-blur"
            >
              {mode === 'clip' ? <ImageIcon size={15} aria-hidden /> : <Film size={15} aria-hidden />}
              {mode === 'clip' ? 'Show demo' : 'My clip'}
            </button>
          ) : (
            <span />
          )}
          {online && exercise && (
            <a
              href={youtubeUrl(exercise.youtubeQuery, exercise.name)}
              target="_blank"
              rel="noopener noreferrer"
              className="flex min-h-[36px] items-center gap-1.5 rounded-full bg-black/70 px-3 text-[13px] font-semibold text-white backdrop-blur"
            >
              <Youtube size={15} aria-hidden /> YouTube
            </a>
          )}
        </div>
      )}
    </div>
  );
}
