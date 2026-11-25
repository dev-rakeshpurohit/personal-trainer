import { format, parseISO } from 'date-fns';
import { useLiveQuery } from 'dexie-react-hooks';
import { Trophy } from 'lucide-react';
import { useMemo } from 'react';
import { Link, useParams } from 'react-router-dom';
import { BackButton } from '@/components/BackButton';
import { DemoPlayer } from '@/components/DemoPlayer';
import { Toggle } from '@/components/Field';
import { Sparkline } from '@/components/Sparkline';
import { Card, Empty, SectionTitle } from '@/components/ui';
import { db } from '@/data/db';
import { useProfile } from '@/data/hooks';
import { e1rm } from '@/domain/progression';
import { displayWeight } from '@/domain/units';
import type { SetLog } from '@/domain/types';
import { ClipControls } from './ClipControls';

export default function ExerciseDetail() {
  const { exerciseId = '' } = useParams();
  const profile = useProfile();
  const ex = useLiveQuery(() => db.exercises.get(exerciseId), [exerciseId]);
  const data = useLiveQuery(async () => {
    const sets = await db.sets.where('exerciseId').equals(exerciseId).filter((s) => !s.isWarmup).toArray();
    const sessions = await db.sessions.bulkGet([...new Set(sets.map((s) => s.sessionId))]);
    const planned = await db.plannedExercises.filter((p) => p.exerciseId === exerciseId || p.swapExerciseId === exerciseId).toArray();
    const related = await db.exercises.bulkGet([...new Set(planned.flatMap((p) => [p.exerciseId, p.swapExerciseId]).filter((x): x is string => !!x && x !== exerciseId))]);
    return { sets, sessions: sessions.filter(Boolean), planned, related: related.filter(Boolean) };
  }, [exerciseId]);
  const units = profile?.units ?? 'kg';

  const bySession = useMemo(() => {
    if (!data) return [];
    const m = new Map<string, SetLog[]>();
    data.sets.forEach((s) => m.set(s.sessionId, [...(m.get(s.sessionId) ?? []), s]));
    return [...m.entries()]
      .map(([id, sets]) => ({ session: data.sessions.find((s) => s!.id === id)!, sets: sets.sort((a, b) => a.setIndex - b.setIndex) }))
      .filter((x) => x.session)
      .sort((a, b) => a.session.startedAt.localeCompare(b.session.startedAt));
  }, [data]);

  const e1rmSeries = bySession.map((s) => Math.max(0, ...s.sets.map((x) => e1rm(x.weightKg, x.reps) ?? 0))).filter((v) => v > 0);
  const prs = useMemo(() => {
    if (!data?.sets.length) return undefined;
    const heaviest = data.sets.reduce((a, s) => ((s.weightKg ?? 0) > (a.weightKg ?? 0) ? s : a));
    const best = data.sets.reduce((a, s) => ((e1rm(s.weightKg, s.reps) ?? 0) > (e1rm(a.weightKg, a.reps) ?? 0) ? s : a));
    const mostReps = data.sets.reduce((a, s) => ((s.reps ?? 0) > (a.reps ?? 0) ? s : a));
    const longest = data.sets.reduce((a, s) => ((s.seconds ?? 0) > (a.seconds ?? 0) ? s : a));
    return { heaviest, best, mostReps, longest };
  }, [data]);

  if (ex === undefined) return null;
  if (ex === null || !ex)
    return (
      <div className="p-4 pt-safe">
        <Empty title="Exercise not found" action={<BackButton to="/train/library" />} />
      </div>
    );

  return (
    <div className="animate-fade-in pb-4">
      <header className="pt-safe">
        <div className="flex items-center justify-between px-2 pt-2">
          <BackButton />
        </div>
        <h1 className="px-4 pb-3 text-[26px] font-bold leading-tight tracking-tight">{ex.name}</h1>
      </header>
      <div className="space-y-3 px-4">
        <DemoPlayer exercise={ex} className="aspect-[4/3] w-full" />
        <ClipControls exerciseId={ex.id} name={ex.name} />

        {(ex.cue || ex.instructions?.length) && (
          <Card>
            {ex.cue && <p className="text-[17px] font-semibold">{ex.cue}</p>}
            {ex.instructions && ex.instructions.length > 0 && (
              <ol className="mt-2 list-decimal space-y-1.5 pl-5 text-[15px] text-text/85">
                {ex.instructions.map((s) => (
                  <li key={s}>{s}</li>
                ))}
              </ol>
            )}
          </Card>
        )}

        <div className="flex flex-wrap gap-1.5">
          {[...ex.primaryMuscles, ...ex.equipment, ex.category].filter(Boolean).map((t) => (
            <span key={t} className="rounded-full bg-surface2 px-3 py-1.5 text-[13px] font-medium capitalize">
              {t}
            </span>
          ))}
        </div>

        <Card className="!py-1">
          <Toggle checked={!ex.isBodyweight} onChange={(v) => db.exercises.update(ex.id, { isBodyweight: !v })} label="Track weight" sub="Turn off for bodyweight-only movements" />
        </Card>

        {data && data.related.length > 0 && (
          <>
            <SectionTitle>Swap mapping</SectionTitle>
            <div className="space-y-2">
              {data.related.map((r) => (
                <Link key={r!.id} to={`/train/library/${r!.id}`} className="flex min-h-[52px] items-center justify-between rounded-card border border-line/50 bg-surface px-4">
                  <span className="font-semibold">{r!.name}</span>
                  <span className="text-caption text-muted">{data.planned.some((p) => p.swapExerciseId === r!.id) ? 'its swap' : 'swaps to this'}</span>
                </Link>
              ))}
            </div>
          </>
        )}

        <SectionTitle>Progress</SectionTitle>
        <Card>
          <p className="text-caption font-semibold text-muted">Estimated 1RM (Epley)</p>
          {e1rmSeries.length > 0 && <p className="text-[24px] font-bold tnum">{displayWeight(e1rmSeries[e1rmSeries.length - 1], units)} {units}</p>}
          <Sparkline values={e1rmSeries} label={`Estimated one-rep max trend for ${ex.name}`} />
        </Card>

        {prs && (
          <div className="grid grid-cols-2 gap-2">
            {!ex.isBodyweight && prs.heaviest.weightKg ? <Pr label="Heaviest" value={`${displayWeight(prs.heaviest.weightKg, units)} ${units} × ${prs.heaviest.reps ?? '–'}`} /> : null}
            {e1rm(prs.best.weightKg, prs.best.reps) ? <Pr label="Best e1RM" value={`${displayWeight(e1rm(prs.best.weightKg, prs.best.reps), units)} ${units}`} /> : null}
            {prs.mostReps.reps ? <Pr label="Most reps" value={`${prs.mostReps.reps}${prs.mostReps.weightKg ? ` @ ${displayWeight(prs.mostReps.weightKg, units)}` : ''}`} /> : null}
            {prs.longest.seconds ? <Pr label="Longest" value={`${prs.longest.seconds}s`} /> : null}
          </div>
        )}

        <SectionTitle>Log</SectionTitle>
        {bySession.length === 0 ? (
          <Empty title="No sets logged yet" body="Your history for this exercise will show here." />
        ) : (
          <ul className="space-y-2">
            {[...bySession].reverse().map(({ session, sets }) => (
              <li key={session.id} className="rounded-card border border-line/50 bg-surface p-3">
                <Link to={`/train/history/${session.dayKey}`} className="flex justify-between text-[15px] font-semibold">
                  <span>{format(parseISO(session.startedAt), 'EEE d MMM')}</span>
                  <span className="text-muted">{session.title}</span>
                </Link>
                <p className="mt-1 text-[15px] text-text/85 tnum">
                  {sets
                    .map((s) =>
                      s.seconds != null ? `${s.seconds}s` : s.meters != null ? `${s.meters} m` : `${s.weightKg ? `${displayWeight(s.weightKg, units)}×` : ''}${s.reps ?? ''}`,
                    )
                    .join(' · ')}
                </p>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function Pr({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-card border border-warning/30 bg-warning/[0.07] p-3">
      <p className="flex items-center gap-1 text-caption font-semibold text-warning">
        <Trophy size={14} aria-hidden /> {label}
      </p>
      <p className="mt-0.5 text-[17px] font-bold tnum">{value}</p>
    </div>
  );
}
