import { format, isSameDay } from 'date-fns';
import { useLiveQuery } from 'dexie-react-hooks';
import { BookOpen, CalendarDays, Check, ChevronRight, Dumbbell, HeartPulse, Moon, Play, Zap } from 'lucide-react';
import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Button, PageHeader, SectionTitle } from '@/components/ui';
import { Sheet } from '@/components/Sheet';
import { db } from '@/data/db';
import { useExerciseMap, useProgram, useWeekPlan } from '@/data/hooks';
import { cycleEntry, cycleWeek, dayKey, weekDates } from '@/domain/schedule';
import { isTrainingType, type DayType, type ProgramDay } from '@/domain/types';
import { exerciseThumb } from '@/lib/clips';

export const DAY_ICON: Record<DayType, typeof Dumbbell> = { strength: Dumbbell, cardio: HeartPulse, conditioning: Zap, rest: Moon, active_recovery: HeartPulse };

export default function Train() {
  const now = new Date();
  const bundle = useProgram();
  const week = useWeekPlan(now, bundle);
  const exMap = useExerciseMap();
  const nav = useNavigate();
  const [open, setOpen] = useState<ProgramDay | null>(null);
  const dates = weekDates(now);
  const sessions = useLiveQuery(() => db.sessions.where('dayKey').between(dayKey(dates[0]), dayKey(dates[6]), true, true).toArray(), [dayKey(dates[0])]);
  const doneOn = (k: string) => sessions?.some((s) => s.dayKey === k && s.status === 'done');
  const cw = bundle ? cycleWeek(now, bundle.program.startedOn) : 1;
  const ce = bundle ? cycleEntry(cw, bundle.program.progression.cycle) : undefined;
  const wf = bundle?.program.progression.weeks?.find((w) => w.week === cw);

  return (
    <div className="animate-fade-in">
      <PageHeader title="Train" sub={bundle ? `${bundle.program.name} · week ${cw} of 8` : undefined} />
      <div className="px-4">
        {ce && (
          <div className="mb-3 rounded-card border border-line/50 bg-surface p-4">
            <p className="text-[13px] font-bold uppercase tracking-wider text-primary-ink">This week's focus</p>
            <p className="mt-1 text-[17px] font-semibold">
              {ce.deload || wf?.deload
                ? 'Deload: half the sets, same weights'
                : wf
                  ? `${wf.focus}: main lifts ${wf.rirMain} reps in reserve, accessories ${wf.rirAccessory}`
                  : `Stop each set with ${ce.rir} reps in reserve`}
            </p>
            {(wf?.note ?? ce.note) && <p className="mt-0.5 text-[15px] text-muted">{wf?.note ?? ce.note}</p>}
          </div>
        )}

        <ul className="grid grid-cols-7 gap-1.5" aria-label="This week">
          {dates.map((d) => {
            const k = dayKey(d);
            const day = week?.byDate[k];
            const today = isSameDay(d, now);
            const done = doneOn(k);
            const training = day && isTrainingType(day.type);
            return (
              <li key={k}>
              <button
                type="button"
                onClick={() => day && setOpen(day)}
                aria-label={`${format(d, 'EEEE')}: ${day?.title ?? 'Rest'}${done ? ', done' : ''}`}
                className={`flex min-h-[72px] w-full flex-col items-center justify-center gap-1 rounded-btn border ${today ? 'border-primary bg-primary/10' : 'border-line/50 bg-surface'}`}
              >
                <span className={`text-[12px] font-semibold ${today ? 'text-primary-ink' : 'text-muted'}`}>{format(d, 'EEEEE')}</span>
                <span className="text-[17px] font-bold tnum">{format(d, 'd')}</span>
                <span
                  className={`flex h-4 w-4 items-center justify-center rounded-full ${done ? 'bg-success text-on-primary' : training ? 'bg-primary/70' : 'bg-line'}`}
                  aria-hidden
                >
                  {done && <Check size={11} strokeWidth={4} />}
                </span>
              </button>
              </li>
            );
          })}
        </ul>

        <SectionTitle>This week</SectionTitle>
        <ul className="space-y-2">
          {dates.map((d) => {
            const k = dayKey(d);
            const day = week?.byDate[k];
            const orig = week?.original[k];
            if (!day) return null;
            const Icon = DAY_ICON[day.type];
            const count = bundle?.planned.filter((p) => p.dayId === day.id).length ?? 0;
            const moved = week?.adjusted && orig?.id !== day.id;
            const done = doneOn(k);
            return (
              <li key={k}>
                <button
                  type="button"
                  onClick={() => setOpen(day)}
                  className={`flex min-h-[72px] w-full items-center gap-3 rounded-card border p-3 text-left ${isSameDay(d, now) ? 'border-primary/50 bg-surface' : 'border-line/50 bg-surface'} ${done ? 'opacity-70' : ''}`}
                >
                  <span className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-btn ${isTrainingType(day.type) ? 'bg-primary/15 text-primary-ink' : 'bg-surface2 text-muted'}`}>
                    <Icon size={22} aria-hidden />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-caption font-semibold text-muted">
                      {format(d, 'EEE d')}
                      {moved && <span className="ml-1.5 text-info">· moved</span>}
                      {done && <span className="ml-1.5 text-success">· done</span>}
                    </span>
                    <span className="block truncate text-[17px] font-semibold">{day.title}</span>
                    {count > 0 && <span className="block text-caption text-muted">{count} exercises · {day.durationMin ?? 60} min</span>}
                  </span>
                  <ChevronRight size={20} className="text-muted" aria-hidden />
                </button>
              </li>
            );
          })}
          {week?.dropped.map((d) => (
            <li key={d.id} className="rounded-card border border-dashed border-line px-4 py-3 text-[15px] text-muted">
              Dropped this week to fit: {d.title}. Do a 30-min brisk walk instead if you can.
            </li>
          ))}
        </ul>

        <div className="mt-6 grid grid-cols-2 gap-2">
          <Link to="/train/library" className="flex min-h-[64px] items-center gap-3 rounded-card border border-line/50 bg-surface px-4 font-semibold">
            <BookOpen size={22} className="text-primary-ink" aria-hidden /> Library
          </Link>
          <Link to="/train/history" className="flex min-h-[64px] items-center gap-3 rounded-card border border-line/50 bg-surface px-4 font-semibold">
            <CalendarDays size={22} className="text-primary-ink" aria-hidden /> History
          </Link>
        </div>
      </div>

      <Sheet
        open={!!open}
        onClose={() => setOpen(null)}
        title={open?.title ?? ''}
        tall
        footer={
          open && isTrainingType(open.type) && (bundle?.planned.some((p) => p.dayId === open.id) ?? false) ? (
            <Button block size="lg" onClick={() => nav(`/workout/start/${open.id}`)}>
              <Play size={20} fill="currentColor" aria-hidden /> Start this session
            </Button>
          ) : undefined
        }
      >
        {open && (
          <div className="pb-2">
            {open.notes && <p className="mb-3 text-[15px] text-muted">{open.notes}</p>}
            <ul className="divide-y divide-line/50">
              {bundle?.planned
                .filter((p) => p.dayId === open.id)
                .map((p) => {
                  const ex = exMap.get(p.exerciseId);
                  const thumb = exerciseThumb(ex);
                  return (
                    <li key={p.id}>
                      <Link to={`/train/library/${p.exerciseId}`} className="flex min-h-[64px] items-center gap-3 py-2">
                        <span className="h-12 w-12 shrink-0 overflow-hidden rounded-btn bg-white">{thumb && <img src={thumb} alt="" className="h-full w-full object-cover" loading="lazy" />}</span>
                        <span className="min-w-0 flex-1">
                          <span className="block truncate font-semibold">
                            <span className="mr-1.5 text-primary-ink">{p.slot}</span>
                            {ex?.name ?? p.exerciseId}
                          </span>
                          <span className="block text-caption text-muted">
                            {p.sets} × {p.repsMin === p.repsMax ? p.repsMin : `${p.repsMin}–${p.repsMax}`} {p.unit === 'reps' ? '' : p.unit}
                            {p.perSide ? ' / side' : ''} · rest {p.restSec}s
                          </span>
                        </span>
                        <ChevronRight size={18} className="text-muted" aria-hidden />
                      </Link>
                    </li>
                  );
                })}
            </ul>
            {!isTrainingType(open.type) && <p className="text-[15px] text-muted">{open.type === 'rest' ? 'Recovery is when you get stronger.' : 'Easy movement: walk, stretch, breathe.'}</p>}
          </div>
        )}
      </Sheet>
    </div>
  );
}

