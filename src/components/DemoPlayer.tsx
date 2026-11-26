import { Film, ImageIcon, Play, Youtube } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { Exercise } from '@/domain/types';
import { DEMO_CREDIT, demoAnimSrc, demoSrc, exerciseThumb, useClipUrl, youtubeUrl } from '@/lib/clips';
import { useOnline } from '@/lib/online';
import { prefersReducedMotion } from '@/lib/platform';
import { CLIP_LOOP_SEC } from '@/lib/recorder';

/**
 * Layer 1: animated 3D demo (offline, precached) — falls back to the 2-frame photo crossfade.
 * Layer 2: the user's own clip (preferred when present). Layer 3: YouTube link (online only).
 */
export function DemoPlayer({ exercise, className = '', compact }: { exercise: Exercise | undefined; className?: string; compact?: boolean }) {
  const clip = useClipUrl(exercise?.id);
  const online = useOnline();
  const [frame, setFrame] = useState<0 | 1>(0);
  const [mode, setMode] = useState<'clip' | 'demo'>('clip');
  const reduced = prefersReducedMotion();
  const showClip = !!clip && mode === 'clip';
  const [animFailed, setAnimFailed] = useState(false);
  const [playing, setPlaying] = useState(!reduced);
  useEffect(() => setAnimFailed(false), [exercise?.id]);
  const anim = animFailed ? undefined : demoAnimSrc(exercise?.id);
  const still = exerciseThumb(exercise);
  const src0 = demoSrc(exercise?.freeDbId, 0);
  const src1 = demoSrc(exercise?.freeDbId, 1);

  useEffect(() => {
    if (showClip || reduced || !src1 || anim) return;
    const t = setInterval(() => setFrame((f) => (f ? 0 : 1)), 900);
    return () => clearInterval(t);
  }, [showClip, reduced, src1, anim]);

  return (
    <div className={`relative overflow-hidden rounded-card bg-white ${className}`}>
      {showClip ? (
        <video
          key={clip}
          src={clip}
          className="h-full w-full bg-black object-contain"
          muted
          loop
          playsInline
          autoPlay
          aria-label={`My clip: ${exercise?.name}`}
          onTimeUpdate={(e) => {
            if (e.currentTarget.currentTime > CLIP_LOOP_SEC) e.currentTarget.currentTime = 0;
          }}
        />
      ) : anim ? (
        <button
          type="button"
          className="relative block h-full w-full"
          onClick={() => reduced && setPlaying((p) => !p)}
          aria-label={`${exercise?.name} demonstration${reduced ? (playing ? ', tap to pause' : ', tap to play') : ''}`}
        >
          <img
            key={anim}
            src={playing ? anim : still}
            alt=""
            className="absolute inset-0 h-full w-full object-contain"
            decoding="async"
            onError={() => setAnimFailed(true)}
          />
          {!playing && (
            <span className="absolute left-1/2 top-1/2 flex h-12 w-12 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-black/60 text-white">
              <Play size={22} aria-hidden />
            </span>
          )}
          <span className="pointer-events-none absolute right-2 top-1.5 text-[10px] font-medium text-black/35">{DEMO_CREDIT}</span>
        </button>
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
