import { CheckCircle2, Circle, Clock, Info, Play, Zap } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Navigate, useNavigate, useParams } from 'react-router-dom';
import { BackButton } from '@/components/BackButton';
import { Button, Card, Empty, SectionTitle } from '@/components/ui';
import { Segmented } from '@/components/Segmented';
import { useActiveSession, useExerciseMap, useProgram, useWeekPlan } from '@/data/hooks';
import { dayKey } from '@/domain/schedule';
import type { SessionMode } from '@/domain/types';
import { exerciseThumb } from '@/lib/clips';
import { prepareSession, startSession, type Prepared } from './session';

/** Pre-flight: choose Full or Express, see adaptations and the warm-up, then begin. */
export default function Prestart() {
  const { dayId: param } = useParams();
  const nav = useNavigate();
  const now = new Date();
  const bundle = useProgram();
  const week = useWeekPlan(now, bundle);
  const active = useActiveSession();
  const exMap = useExerciseMap();
  const dayId = param ?? week?.byDate[dayKey(now)]?.id;
  const [mode, setMode] = useState<SessionMode>('full');
  const [prep, setPrep] = useState<Prepared>();
  const [touched, setTouched] = useState(false);
  const [warm, setWarm] = useState<Set<number>>(new Set());
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!dayId) return;
    let alive = true;
    void prepareSession(dayId, mode).then((p) => {
      if (!alive || !p) return;
      setPrep(p);
      if (!touched && p.adaptation.preferExpress && mode === 'full') setMode('express');
    });
    return () => {
      alive = false;
    };
  }, [dayId, mode, touched]);

  if (active) return <Navigate to="/workout" replace />;
  if (bundle === undefined || (!param && !week)) return null;
  if (!dayId)
    return (
      <div className="p-4 pt-safe">
        <BackButton />
        <Empty title="No session planned today" body="Pick any session from the Train tab." />
      </div>
    );

  const begin = async () => {
    if (!prep) return;
    setBusy(true);
    await startSession(prep, mode);
    nav('/workout', { replace: true });
  };

  const warmup = bundle?.program.warmup ?? [];
  return (
    <div className="app-shell flex flex-col">
      <header className="pt-safe">
        <div className="px-2 pt-2">
          <BackButton />
        </div>
        <div className="px-4 pb-2">
          <p className="text-[13px] font-bold uppercase tracking-wider text-primary-ink">
            Week {prep?.cycleWeek ?? '–'} of 8{prep?.week ? ` · ${prep.week.focus}` : ''}
          </p>
          <h1 className="text-[28px] font-bold leading-tight tracking-tight">{prep?.day.title ?? ''}</h1>
        </div>
      </header>
      <main className="flex-1 overflow-y-auto px-4 pb-4">
        <Segmented
          label="Session length"
          value={mode}
          onChange={(v) => {
            setTouched(true);
            setMode(v);
          }}
          options={[
            { value: 'full', label: 'Full' },
            { value: 'express', label: 'Express ~40 min' },
          ]}
        />
        {prep && (
          <p className="mt-2 flex items-center gap-3 text-[15px] text-muted">
            <span className="flex items-center gap-1">
              <Clock size={16} aria-hidden /> ~{prep.estMin} min
            </span>
            <span>{prep.plan.length} exercises</span>
            {prep.hiit && prep.hiit < 3 && (
              <span className="flex items-center gap-1 text-info">
                <Zap size={16} aria-hidden /> Ramp {prep.hiit}/3
              </span>
            )}
          </p>
        )}

        {prep && (prep.adaptation.reasons.length > 0 || prep.deload || prep.week?.note) && (
          <Card className="mt-3 border-info/30 bg-info/[0.07]">
            <p className="flex items-center gap-2 font-semibold">
              <Info size={18} className="text-info" aria-hidden /> Tuned for you today
            </p>
            <ul className="mt-1.5 space-y-1 text-[15px] text-text/85">
              {prep.deload && <li>• Deload week: half the sets, same weights.</li>}
              {prep.week && !prep.deload && <li>• {prep.week.note}</li>}
              {prep.hiit && prep.hiit < 3 && <li>• Conditioning is ramping up gently from a beginner start. It gets harder as you complete sessions.</li>}
              {prep.adaptation.reasons.map((r) => (
                <li key={r}>• {r}</li>
              ))}
            </ul>
          </Card>
        )}

        {warmup.length > 0 && (
          <>
            <SectionTitle>Warm-up · 10 min</SectionTitle>
            <Card className="!py-1">
              {(mode === 'express' ? warmup.slice(0, 1) : warmup).map((w, i) => (
                <button
                  key={w.name}
                  type="button"
                  role="checkbox"
                  aria-checked={warm.has(i)}
                  onClick={() => setWarm((s) => new Set(s.has(i) ? [...s].filter((x) => x !== i) : [...s, i]))}
                  className="flex min-h-[52px] w-full items-center gap-3 text-left"
                >
                  {warm.has(i) ? <CheckCircle2 className="shrink-0 text-success" size={24} aria-hidden /> : <Circle className="shrink-0 text-muted" size={24} aria-hidden />}
                  <span className={`flex-1 ${warm.has(i) ? 'text-muted line-through' : ''}`}>{w.name}</span>
                  <span className="text-caption text-muted">{w.minutes ? `${w.minutes} min` : w.reps}</span>
                </button>
              ))}
            </Card>
          </>
        )}

        <SectionTitle>Today's exercises</SectionTitle>
        <ul className="space-y-2">
          {prep?.plan.map((e) => {
            const ex = exMap.get(e.exerciseId);
            const t = exerciseThumb(ex);
            return (
              <li key={e.plannedExerciseId} className="flex items-center gap-3 rounded-card border border-line/50 bg-surface p-2.5">
                <span className="h-12 w-12 shrink-0 overflow-hidden rounded-btn bg-white">{t && <img src={t} alt="" className="h-full w-full object-cover" />}</span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate font-semibold">
                    <span className="mr-1.5 text-primary-ink">{e.slot}</span>
                    {ex?.name ?? e.exerciseId}
                  </span>
                  <span className="block text-caption text-muted">
                    {e.sets} × {e.repsMin === e.repsMax ? e.repsMax : `${e.repsMin}–${e.repsMax}`}
                    {e.unit === 'reps' ? '' : e.unit === 'seconds' ? 's' : e.unit === 'minutes' ? ' min' : ' m'}
                    {e.perSide ? ' / side' : ''}
                    {e.rir != null ? ` · RIR ${e.rir}` : ''}
                    {e.restSec ? ` · rest ${e.restSec}s` : ''}
                  </span>
                </span>
                {e.isMain && <span className="rounded-full bg-primary/15 px-2 py-0.5 text-[11px] font-bold text-primary-ink">MAIN</span>}
              </li>
            );
          })}
        </ul>
      </main>
      <footer className="border-t border-line/50 px-4 pb-[calc(12px+env(safe-area-inset-bottom))] pt-3">
        <Button size="xl" block onClick={begin} disabled={!prep || busy || !prep.plan.length}>
          <Play size={22} fill="currentColor" aria-hidden /> Begin workout
        </Button>
      </footer>
    </div>
  );
}
