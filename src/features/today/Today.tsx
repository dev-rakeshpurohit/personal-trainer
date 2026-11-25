import { differenceInCalendarDays, format, parseISO } from 'date-fns';
import { useLiveQuery } from 'dexie-react-hooks';
import { ArrowRight, CalendarClock, Camera, CheckCircle2, Circle, Clock, Flame, Footprints, HardDriveDownload, Moon, Play, Ruler, Scale, Sparkles, TrendingDown, TrendingUp, WifiOff } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { Button, Card, SectionTitle } from '@/components/ui';
import { Ring } from '@/components/Ring';
import { db, getMeta, setMeta } from '@/data/db';
import { replanOffKey, useActiveSession, useDiet, useExerciseMap, useProfile, useProgram, useWeekPlan } from '@/data/hooks';
import { setHabit } from '@/data/repo';
import { dayTotals, mealsForDay, nextMeal } from '@/domain/diet';
import { allCoveredDates } from '@/domain/replan';
import { cycleWeek, dayKey, isDeloadWeek, weekdayOf } from '@/domain/schedule';
import { current7dAvg, rateKgPerWeek, trainingStreak, weeklyAverage } from '@/domain/stats';
import { isTrainingType, type Profile, type ProgramDay } from '@/domain/types';
import { displayWeight } from '@/domain/units';
import { useOnline } from '@/lib/online';
import { MealCard } from '@/features/eat/MealCard';
import { goHeavierFor } from '@/features/workout/progressionData';
import { CoachMarks, InstallGuide } from './Guides';
import { QuickLogSheet, type QuickKind } from './QuickLog';

const greeting = (h: number) => (h < 5 ? 'Up late' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening');

export default function Today() {
  const profile = useProfile();
  if (!profile) return null;
  return <TodayInner profile={profile} />;
}

function TodayInner({ profile }: { profile: Profile }) {
  const now = new Date();
  const today = dayKey(now);
  const nav = useNavigate();
  const [params, setParams] = useSearchParams();
  const online = useOnline();
  const bundle = useProgram();
  const diet = useDiet();
  const exMap = useExerciseMap();
  const week = useWeekPlan(now, bundle);
  const active = useActiveSession();
  const [quick, setQuick] = useState<QuickKind | null>((params.get('log') as QuickKind) ?? null);
  const [tour, setTour] = useState(params.get('welcome') === '1');

  const data = useLiveQuery(async () => {
    const [mealLogs, habitLogs, sessionsToday, body, done, lastBackupAt, onboardedAt] = await Promise.all([
      db.mealLogs.where('dayKey').equals(today).toArray(),
      db.habitLogs.where('dayKey').equals(today).toArray(),
      db.sessions.where('dayKey').equals(today).toArray(),
      db.bodyLogs.orderBy('dayKey').toArray(),
      db.sessions.where('status').equals('done').toArray(),
      getMeta<string>('lastBackupAt'),
      getMeta<string>('onboardedAt'),
    ]);
    return { mealLogs, habitLogs, sessionsToday, body, done, lastBackupAt, onboardedAt };
  }, [today]);

  const todayDay: ProgramDay | undefined = week?.byDate[today];
  const originalDay = week?.original[today];
  const moved = !!week?.adjusted && todayDay?.id !== originalDay?.id;
  const planned = useMemo(() => (todayDay && bundle ? bundle.planned.filter((p) => p.dayId === todayDay.id) : []), [todayDay, bundle]);
  const restDay = !todayDay || !isTrainingType(todayDay.type);
  const doneToday = data?.sessionsToday.find((s) => s.status === 'done');

  const cw = bundle ? cycleWeek(now, bundle.program.startedOn) : 1;
  const deload = bundle ? isDeloadWeek(cw, bundle.program.progression.cycle) : false;

  const [heavier, setHeavier] = useState<{ name: string; message: string }[]>([]);
  useEffect(() => {
    if (!bundle || !planned.length || restDay) return setHeavier([]);
    let alive = true;
    void goHeavierFor(planned, exMap, profile, bundle.program, now).then((r) => alive && setHeavier(r));
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [planned, exMap, bundle, restDay, profile]);

  const meals = diet ? mealsForDay(diet.meals, restDay) : [];
  const totals = dayTotals(data?.mealLogs ?? []);
  const loggedIds = new Set((data?.mealLogs ?? []).map((l) => l.plannedMealId!).filter(Boolean));
  const next = nextMeal(meals, loggedIds, format(now, 'HH:mm'));
  const habit = (id: string) => data?.habitLogs.find((h) => h.habitId === id)?.value ?? 0;
  const kcalTarget = diet?.plan.kcalTarget ?? profile.kcalTarget;
  const proteinTarget = diet?.plan.proteinTargetG ?? profile.proteinTargetG;

  const streak = useMemo(() => {
    if (!bundle || !data) return 0;
    const covered = allCoveredDates(bundle.days, data.done.map((s) => ({ programDayId: s.programDayId, dayKey: s.dayKey })));
    const isPlanned = (d: Date) => {
      const p = bundle.days.find((x) => x.weekday === weekdayOf(d));
      return !!p && isTrainingType(p.type);
    };
    return trainingStreak(isPlanned, covered, now, data.onboardedAt ? parseISO(data.onboardedAt) : undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bundle, data, today]);

  const bodyPts = useMemo(() => (data?.body ?? []).filter((b) => b.weightKg != null).map((b) => ({ dayKey: b.dayKey, value: b.weightKg! })), [data]);
  const rate = rateKgPerWeek(bodyPts, now);
  const avg7 = current7dAvg(bodyPts, now);
  const thisWeek = weeklyAverage(bodyPts, now);
  const weighedToday = bodyPts.some((p) => p.dayKey === today);

  const backupDue = (() => {
    if (!data) return false;
    const ref = data.lastBackupAt ?? data.onboardedAt;
    return !!ref && differenceInCalendarDays(now, parseISO(ref)) >= 30;
  })();

  const closeQuick = () => {
    setQuick(null);
    if (params.get('log')) {
      params.delete('log');
      setParams(params, { replace: true });
    }
  };
  const closeTour = () => {
    setTour(false);
    params.delete('welcome');
    setParams(params, { replace: true });
    void setMeta('seenCoachMarks', true);
  };

  return (
    <div className="animate-fade-in">
      <header className="pt-safe">
        <div className="flex items-start justify-between px-4 pb-1 pt-4">
          <div className="min-w-0">
            <p className="text-[15px] font-medium text-muted">{format(now, 'EEEE, d MMMM')}</p>
            <h1 className="truncate text-[28px] font-bold leading-tight tracking-tight">
              {greeting(now.getHours())}, {profile.name}
            </h1>
          </div>
          <div className="flex shrink-0 items-center gap-2 pt-1">
            {streak > 0 && (
              <span className="flex h-9 items-center gap-1 rounded-full bg-warning/15 px-3 text-[15px] font-bold text-warning" aria-label={`${streak} session streak`}>
                <Flame size={16} aria-hidden /> {streak}
              </span>
            )}
            <span className={`h-2.5 w-2.5 rounded-full ${online ? 'bg-success' : 'bg-muted'}`} role="img" aria-label={online ? 'Online' : 'Offline'} />
          </div>
        </div>
        {!online && (
          <p className="mx-4 mt-1 inline-flex items-center gap-1.5 rounded-full bg-surface2 px-3 py-1 text-caption font-medium text-muted">
            <WifiOff size={14} aria-hidden /> Offline · everything still works
          </p>
        )}
      </header>

      <div className="space-y-3 px-4 pt-3">
        {week?.adjusted && week.missed.length > 0 && (
          <Card className="border-info/40 bg-info/[0.08]">
            <div className="flex gap-3">
              <CalendarClock className="mt-0.5 shrink-0 text-info" size={22} aria-hidden />
              <div className="min-w-0 flex-1">
                <p className="font-semibold">Plan adjusted for a missed session</p>
                <p className="mt-0.5 text-[15px] text-muted">
                  Missed {week.missed.map((m) => `${m.day.title.split(' –')[0]} (${format(parseISO(m.date), 'EEE')})`).join(', ')}.{' '}
                  {moved && todayDay ? `Today: ${todayDay.title}.` : 'The rest of the week has been re-flowed.'}
                  {week.dropped.length > 0 && ` Dropped this week: ${week.dropped.map((d) => d.title.split(' –')[0]).join(', ')}.`}
                </p>
                <div className="mt-2 flex gap-2">
                  <Link to="/train" className="flex min-h-[44px] items-center text-[15px] font-semibold text-info">
                    See week
                  </Link>
                  <button type="button" className="min-h-[44px] px-2 text-[15px] font-semibold text-muted" onClick={() => setMeta(replanOffKey(now), true)}>
                    Keep original plan
                  </button>
                </div>
              </div>
            </div>
          </Card>
        )}

        <HeroCard
          day={todayDay}
          moved={moved}
          planned={planned.length}
          muscles={[...new Set(planned.flatMap((p) => exMap.get(p.exerciseId)?.primaryMuscles ?? []))].slice(0, 4)}
          deload={deload}
          cycleWeek={cw}
          activeTitle={active?.session.title}
          doneToday={doneToday ? { title: doneToday.title, min: doneToday.endedAt ? Math.round((parseISO(doneToday.endedAt).getTime() - parseISO(doneToday.startedAt).getTime()) / 60000) : undefined, id: doneToday.id } : undefined}
          steps={habit('steps')}
          today={today}
          recovery={{ walk: habit('recovery-walk'), mobility: habit('recovery-mobility') }}
          onStart={() => nav('/workout/today')}
          onSteps={() => setQuick('steps')}
        />

        <div className="grid grid-cols-4 gap-2 rounded-card border border-line/50 bg-surface p-3">
          <RingStat label="Protein" value={totals.proteinG} max={proteinTarget} unit="g" color="rgb(var(--primary))" />
          <RingStat label="Calories" value={totals.kcal} max={kcalTarget} unit="kcal" color="rgb(var(--warning))" remaining />
          <RingStat label="Water" value={habit('water') / 1000} max={3} unit="L" color="rgb(var(--info))" decimals={1} onTap={() => setHabit(today, 'water', habit('water') + 250)} tapLabel="Add 250 ml water" />
          <RingStat label="Steps" value={habit('steps')} max={8000} unit="" color="rgb(var(--success))" compact onTap={() => setQuick('steps')} tapLabel="Log steps" />
        </div>

        {next && (
          <>
            <SectionTitle action={<Link to="/eat" className="flex min-h-[44px] items-center gap-1 text-[14px] font-semibold text-primary-ink">All meals <ArrowRight size={16} aria-hidden /></Link>}>
              Next meal
            </SectionTitle>
            <MealCard meal={next} log={data?.mealLogs.find((l) => l.plannedMealId === next.id)} dayKey={today} highlight />
          </>
        )}

        <SectionTitle>Quick log</SectionTitle>
        <div className="grid grid-cols-4 gap-2">
          <QuickTile Icon={Scale} label="Weight" done={weighedToday} onClick={() => setQuick('weight')} />
          <QuickTile Icon={Ruler} label="Waist" onClick={() => setQuick('waist')} />
          <QuickTile Icon={Camera} label="Photo" onClick={() => setQuick('photo')} />
          <QuickTile Icon={Footprints} label="Steps" done={habit('steps') >= 8000} onClick={() => setQuick('steps')} />
        </div>

        <SectionTitle>Coach</SectionTitle>
        <div className="space-y-2">
          {deload && <CoachCard Icon={Moon} tone="info" title={`Deload week (week ${cw} of 8)`} body="Half the sets, same weights. Let your body catch up; you'll come back stronger." />}
          {heavier.length > 0 && (
            <CoachCard
              Icon={TrendingUp}
              tone="success"
              title={`${heavier.length} ${heavier.length === 1 ? 'lift is' : 'lifts are'} ready to go heavier`}
              body={heavier.map((h) => `${h.name}: ${h.message}`).join(' · ')}
            />
          )}
          {rate && avg7 != null && (
            <CoachCard
              Icon={rate.lossPerWeek >= 0 ? TrendingDown : TrendingUp}
              tone={rate.lossPerWeek >= 0.3 && rate.lossPerWeek <= 1 ? 'success' : 'warning'}
              title={`Weekly average ${rate.lossPerWeek >= 0 ? '−' : '+'}${Math.abs(rate.lossPerWeek).toFixed(1)} kg/week ${rate.lossPerWeek >= 0.5 && rate.lossPerWeek <= 0.75 ? '✅' : ''}`}
              body={`7-day average ${displayWeight(avg7, profile.units)} ${profile.units}. Goal ${displayWeight(profile.goalWeightKg, profile.units)} ${profile.units}.`}
              to="/progress"
            />
          )}
          {!rate && (
            <CoachCard
              Icon={Scale}
              tone="muted"
              title={thisWeek.valid ? 'Weekly average ready' : `${thisWeek.needed} more weigh-in${thisWeek.needed === 1 ? '' : 's'} this week`}
              body="With 4+ weigh-ins a week, Repmate can tell you if the plan is working."
            />
          )}
          {backupDue && <CoachCard Icon={HardDriveDownload} tone="warning" title="Time for your monthly backup" body="iOS can clear data from web apps. Save a backup to Files or iCloud." to="/more/backup" />}
        </div>
      </div>

      {quick && <QuickLogSheet kind={quick} onClose={closeQuick} dayKey={today} profile={profile} />}
      <CoachMarks open={tour} onClose={closeTour} />
      {!tour && <InstallGuide />}
    </div>
  );
}

function HeroCard(p: {
  day?: ProgramDay;
  moved: boolean;
  planned: number;
  muscles: string[];
  deload: boolean;
  cycleWeek: number;
  activeTitle?: string;
  doneToday?: { title: string; min?: number; id: string };
  steps: number;
  today: string;
  recovery: { walk: number; mobility: number };
  onStart: () => void;
  onSteps: () => void;
}) {
  if (p.doneToday)
    return (
      <Card glow className="!border-success/40">
        <p className="text-[13px] font-bold uppercase tracking-wider text-success">Done today</p>
        <h2 className="mt-1 text-[26px] font-bold leading-tight">{p.doneToday.title}</h2>
        <p className="mt-1 text-[15px] text-muted">{p.doneToday.min ? `${p.doneToday.min} min · ` : ''}Great work. Eat your protein, sleep well.</p>
        <Link to={`/workout/summary/${p.doneToday.id}`} className="mt-4 flex min-h-[48px] items-center justify-center gap-2 rounded-btn bg-surface2 font-semibold">
          <CheckCircle2 size={20} className="text-success" aria-hidden /> View summary
        </Link>
      </Card>
    );

  if (!p.day || p.day.type === 'rest')
    return (
      <Card glow>
        <div className="flex items-center justify-between gap-4">
          <div>
            <p className="text-[13px] font-bold uppercase tracking-wider text-muted">Rest day</p>
            <h2 className="mt-1 text-[26px] font-bold leading-tight">{p.day?.title ?? 'Recover'}</h2>
            <p className="mt-1 text-[15px] text-muted">{p.day?.notes ?? 'Aim for at least 7,000 steps.'}</p>
          </div>
          <button type="button" onClick={p.onSteps} aria-label="Log steps">
            <Ring value={p.steps} max={7000} size={88} stroke={8} color="rgb(var(--success))" label="Steps">
              <span className="text-[16px] font-bold tnum">{(p.steps / 1000).toFixed(1)}k</span>
              <span className="text-[11px] text-muted">/ 7k</span>
            </Ring>
          </button>
        </div>
      </Card>
    );

  if (p.day.type === 'active_recovery')
    return (
      <Card glow>
        <p className="text-[13px] font-bold uppercase tracking-wider text-info">Active recovery</p>
        <h2 className="mt-1 text-[26px] font-bold leading-tight">{p.day.title}</h2>
        <div className="mt-3 space-y-1">
          <RecoveryItem today={p.today} id="recovery-walk" label="45–60 min brisk walk" done={!!p.recovery.walk} />
          <RecoveryItem today={p.today} id="recovery-mobility" label="10 min mobility" done={!!p.recovery.mobility} />
        </div>
      </Card>
    );

  return (
    <Card glow className="!p-5">
      <div className="flex items-center gap-2">
        <p className="text-[13px] font-bold uppercase tracking-wider text-primary-ink">Today · {p.day.type}</p>
        {p.moved && <span className="rounded-full bg-info/20 px-2 py-0.5 text-[12px] font-bold text-info">Moved</span>}
        {p.deload && <span className="rounded-full bg-info/20 px-2 py-0.5 text-[12px] font-bold text-info">Deload</span>}
      </div>
      <h2 className="mt-1 text-[30px] font-bold leading-[1.1] tracking-tight">{p.day.title}</h2>
      <p className="mt-2 flex items-center gap-3 text-[15px] text-muted">
        <span className="flex items-center gap-1">
          <Clock size={16} aria-hidden /> {p.day.durationMin ?? 60} min
        </span>
        <span>{p.planned} exercises</span>
        <span>Week {p.cycleWeek}/8</span>
      </p>
      {p.muscles.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-1.5">
          {p.muscles.map((m) => (
            <span key={m} className="rounded-full bg-bg/60 px-2.5 py-1 text-[13px] font-medium capitalize text-text/80">
              {m}
            </span>
          ))}
        </div>
      )}
      <Button size="xl" block className="mt-5" onClick={p.onStart} disabled={!p.planned}>
        <Play size={22} fill="currentColor" aria-hidden /> {p.activeTitle ? 'Resume workout' : p.planned ? 'Start workout' : 'No exercises yet'}
      </Button>
      {!p.planned && (
        <Link to="/more/plan" className="mt-2 flex min-h-[44px] items-center justify-center text-[15px] font-semibold text-primary-ink">
          Add exercises in the plan editor
        </Link>
      )}
    </Card>
  );
}

function RecoveryItem({ today, id, label, done }: { today: string; id: string; label: string; done: boolean }) {
  return (
    <button type="button" role="checkbox" aria-checked={done} onClick={() => setHabit(today, id, done ? 0 : 1)} className="flex min-h-[48px] w-full items-center gap-3 text-left text-[17px]">
      {done ? <CheckCircle2 className="text-success" size={24} aria-hidden /> : <Circle className="text-muted" size={24} aria-hidden />}
      <span className={done ? 'text-muted line-through' : ''}>{label}</span>
    </button>
  );
}

function RingStat(p: { label: string; value: number; max: number; unit: string; color: string; remaining?: boolean; decimals?: number; compact?: boolean; onTap?: () => void; tapLabel?: string }) {
  const shown = p.compact ? `${(p.value / 1000).toFixed(1)}k` : p.value.toFixed(p.decimals ?? 0);
  const inner = (
    <div className="flex flex-col items-center gap-1">
      <Ring value={p.value} max={p.max} size={64} stroke={6} color={p.color} label={p.label}>
        <span className="text-[14px] font-bold leading-none tnum">{shown}</span>
      </Ring>
      <span className="text-[12px] font-medium text-muted">
        {p.remaining ? `${Math.max(0, Math.round(p.max - p.value))} left` : p.label}
      </span>
    </div>
  );
  return p.onTap ? (
    <button type="button" onClick={p.onTap} aria-label={p.tapLabel} className="rounded-btn py-1 active:bg-surface2">
      {inner}
    </button>
  ) : (
    <div className="py-1">{inner}</div>
  );
}

function QuickTile({ Icon, label, onClick, done }: { Icon: typeof Scale; label: string; onClick: () => void; done?: boolean }) {
  return (
    <button type="button" onClick={onClick} className="relative flex min-h-[76px] flex-col items-center justify-center gap-1.5 rounded-card border border-line/50 bg-surface active:bg-surface2" aria-label={`Log ${label.toLowerCase()}`}>
      <Icon size={22} className="text-primary-ink" aria-hidden />
      <span className="text-[13px] font-semibold">{label}</span>
      {done && <CheckCircle2 size={14} className="absolute right-2 top-2 text-success" aria-label="Logged today" />}
    </button>
  );
}

function CoachCard({ Icon, title, body, tone, to }: { Icon: typeof Sparkles; title: string; body: string; tone: 'info' | 'success' | 'warning' | 'muted'; to?: string }) {
  const color = { info: 'text-info', success: 'text-success', warning: 'text-warning', muted: 'text-muted' }[tone];
  const inner = (
    <div className="flex gap-3 rounded-card border border-line/50 bg-surface p-4">
      <Icon size={22} className={`mt-0.5 shrink-0 ${color}`} aria-hidden />
      <div className="min-w-0 flex-1">
        <p className="font-semibold">{title}</p>
        <p className="mt-0.5 text-[15px] text-muted">{body}</p>
      </div>
      {to && <ArrowRight size={18} className="mt-1 shrink-0 text-muted" aria-hidden />}
    </div>
  );
  return to ? <Link to={to}>{inner}</Link> : inner;
}
