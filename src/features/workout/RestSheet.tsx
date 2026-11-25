import { Minus, Plus, SkipForward } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { formatDuration } from '@/domain/units';
import { chime, vibrate } from '@/lib/notify';
import { useUI } from '@/store/ui';

interface Props {
  endsAt: number;
  total: number;
  next?: string;
  sound: boolean;
  vibrateOn: boolean;
  onAdjust: (deltaSec: number) => void;
  onSkip: () => void;
  onDone: () => void;
}

/** Timestamp-based rest timer: correct after screen lock / app suspension (derived from endsAt). */
export function RestSheet({ endsAt, total, next, sound, vibrateOn, onAdjust, onSkip, onDone }: Props) {
  const [now, setNow] = useState(Date.now());
  const fired = useRef<number>();
  const flash = useUI((s) => s.triggerFlash);
  const remaining = Math.max(0, Math.ceil((endsAt - now) / 1000));
  const over = endsAt - now <= 0;

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 250);
    const onVis = () => setNow(Date.now());
    document.addEventListener('visibilitychange', onVis);
    return () => {
      clearInterval(t);
      document.removeEventListener('visibilitychange', onVis);
    };
  }, []);

  useEffect(() => {
    if (!over || fired.current === endsAt) return;
    fired.current = endsAt;
    // only alert if we hit zero while visible (or within 5 s of returning)
    if (Date.now() - endsAt < 5000) {
      if (sound) chime('end');
      if (vibrateOn) vibrate([200, 100, 200]);
      flash();
    }
    const t = setTimeout(onDone, 2500);
    return () => clearTimeout(t);
  }, [over, endsAt, sound, vibrateOn, flash, onDone]);

  const pct = total > 0 ? Math.min(1, Math.max(0, 1 - (endsAt - now) / (total * 1000))) : 1;
  const milestone = remaining === 30 || remaining === 10 ? `${remaining} seconds left` : over ? 'Rest over. Go!' : '';

  return (
    <div className="fixed inset-x-0 bottom-0 z-40 animate-slide-up rounded-t-[24px] border-t border-line/60 bg-surface2 shadow-[0_-12px_40px_rgba(0,0,0,0.45)]" role="timer" aria-label="Rest timer">
      <div className="h-1 overflow-hidden rounded-t-[24px] bg-line">
        <div className="h-full bg-primary transition-[width] duration-300 ease-linear" style={{ width: `${pct * 100}%` }} />
      </div>
      <div className="px-5 pb-[calc(14px+env(safe-area-inset-bottom))] pt-3">
        <div className="flex items-center justify-between">
          <p className="text-[13px] font-bold uppercase tracking-wider text-muted">{over ? 'Go!' : 'Rest'}</p>
          {next && <p className="max-w-[70%] truncate text-[14px] text-muted">Next: <span className="font-semibold text-text">{next}</span></p>}
        </div>
        <p className={`text-center text-hero tnum ${over ? 'text-success' : ''}`}>{over ? 'GO' : formatDuration(remaining)}</p>
        <span className="sr-only" aria-live="assertive">
          {milestone}
        </span>
        <div className="mt-2 grid grid-cols-3 gap-2">
          <button type="button" onClick={() => onAdjust(-15)} className="flex min-h-[56px] items-center justify-center gap-1 rounded-btn bg-surface text-[17px] font-bold active:bg-line" aria-label="Rest 15 seconds less">
            <Minus size={18} aria-hidden /> 15
          </button>
          <button type="button" onClick={() => onAdjust(15)} className="flex min-h-[56px] items-center justify-center gap-1 rounded-btn bg-surface text-[17px] font-bold active:bg-line" aria-label="Rest 15 seconds more">
            <Plus size={18} aria-hidden /> 15
          </button>
          <button type="button" onClick={onSkip} className="flex min-h-[56px] items-center justify-center gap-1.5 rounded-btn bg-primary text-[17px] font-bold text-on-primary">
            <SkipForward size={18} aria-hidden /> {over ? 'Done' : 'Skip'}
          </button>
        </div>
      </div>
    </div>
  );
}

/** Count-up work timer for timed sets (planks, intervals). */
export function WorkTimer({ target, label, sound, onFinish, onCancel }: { target: number; label: string; sound: boolean; onFinish: (secs: number) => void; onCancel: () => void }) {
  const [start] = useState(Date.now());
  const [now, setNow] = useState(Date.now());
  const beeped = useRef(false);
  const flash = useUI((s) => s.triggerFlash);
  const elapsed = Math.floor((now - start) / 1000);
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 200);
    return () => clearInterval(t);
  }, []);
  useEffect(() => {
    if (elapsed >= target && !beeped.current) {
      beeped.current = true;
      if (sound) chime('end');
      flash();
    } else if (elapsed > 0 && target - elapsed <= 3 && target - elapsed > 0 && sound) chime('tick');
  }, [elapsed, target, sound, flash]);
  const done = elapsed >= target;
  return (
    <div className="fixed inset-0 z-50 flex animate-fade-in flex-col items-center justify-center bg-bg/95 px-6 backdrop-blur" role="timer" aria-label={`${label} work timer`}>
      <p className="text-[15px] font-semibold uppercase tracking-wider text-muted">{label}</p>
      <p className={`mt-2 text-[96px] font-bold leading-none tnum ${done ? 'text-success' : ''}`}>{elapsed}s</p>
      <p className="mt-2 text-[17px] text-muted">Target {target}s</p>
      <span className="sr-only" aria-live="assertive">{done ? 'Target reached' : ''}</span>
      <div className="mt-10 flex w-full max-w-sm gap-3 pb-safe">
        <button type="button" onClick={onCancel} className="min-h-[56px] flex-1 rounded-btn bg-surface2 text-[17px] font-semibold">
          Cancel
        </button>
        <button type="button" onClick={() => onFinish(Math.max(1, elapsed))} className="min-h-[56px] flex-[2] rounded-btn bg-success text-[17px] font-bold text-on-primary">
          Done · log {Math.max(1, elapsed)}s
        </button>
      </div>
    </div>
  );
}
