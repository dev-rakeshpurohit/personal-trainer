import { addDays, differenceInCalendarDays, format, parseISO, startOfISOWeek } from 'date-fns';
import { useLiveQuery } from 'dexie-react-hooks';
import { ArrowDownRight, ArrowUpRight, ChevronRight, Flame, Image as ImageIcon, Trophy } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Segmented } from '@/components/Segmented';
import { Sparkline } from '@/components/Sparkline';
import { Card, Chip, Empty, PageHeader, SectionTitle } from '@/components/ui';
import { db } from '@/data/db';
import { mediaToBlob } from '@/data/media';
import { useProfile, useProgram } from '@/data/hooks';
import { adherencePct, mealsForDay } from '@/domain/diet';
import { detectPRs, e1rm } from '@/domain/progression';
import { allCoveredDates } from '@/domain/replan';
import { dayKey, getDayPlan, weekdayOf } from '@/domain/schedule';
import { current7dAvg, movingAverage7, pctChange, projectedGoalDate, rateKgPerWeek, trainingStreak, weeklyAverage, weeklyLossChecks } from '@/domain/stats';
import { isTrainingType, type Pose, type Profile, type SetLog } from '@/domain/types';
import { displayWeight, toUserUnits } from '@/domain/units';
import { SimpleLine, WeekBars, WeightChart, type WeightRow } from './Charts';
import { DietCoachCard } from './DietCoachCard';

type Tab = 'body' | 'strength' | 'consistency';

export default function Progress() {
  const profile = useProfile();
  const [tab, setTab] = useState<Tab>('body');
  if (!profile) return null;
  return (
    <div className="animate-fade-in pb-6">
      <PageHeader title="Progress" />
      <div className="px-4">
        <Segmented
          label="Progress section"
          value={tab}
          onChange={setTab}
          options={[
            { value: 'body', label: 'Body' },
            { value: 'strength', label: 'Strength' },
            { value: 'consistency', label: 'Consistency' },
          ]}
        />
        <div className="mt-4">
          {tab === 'body' && <Body profile={profile} />}
          {tab === 'strength' && <Strength profile={profile} />}
          {tab === 'consistency' && <Consistency />}
        </div>
      </div>
    </div>
  );
}

function useLiftTrends() {
  return useLiveQuery(async () => {
    const sessions = (await db.sessions.where('status').equals('done').toArray()).sort((a, b) => a.startedAt.localeCompare(b.startedAt));
    const sets = await db.sets.filter((s) => !s.isWarmup).toArray();
    const exercises = new Map((await db.exercises.toArray()).map((e) => [e.id, e]));
    const planned = await db.plannedExercises.toArray();
    const mainIds = new Set(planned.filter((p) => /^[AB]/.test(p.slot)).map((p) => p.exerciseId));
    const order = new Map(sessions.map((s, i) => [s.id, i]));
    const byEx = new Map<string, SetLog[]>();
    sets.filter((s) => order.has(s.sessionId)).forEach((s) => byEx.set(s.exerciseId, [...(byEx.get(s.exerciseId) ?? []), s]));
    return { sessions, byEx, exercises, mainIds, order };
  }, []);
}

/** Per-session best metric for an exercise: e1RM if weighted, else best reps/seconds. */
function seriesFor(sets: SetLog[], sessions: { id: string; startedAt: string }[]) {
  const by = new Map<string, SetLog[]>();
  sets.forEach((s) => by.set(s.sessionId, [...(by.get(s.sessionId) ?? []), s]));
  return sessions
    .filter((s) => by.has(s.id))
    .map((s) => {
      const list = by.get(s.id)!;
      const best = Math.max(0, ...list.map((x) => e1rm(x.weightKg, x.reps) ?? 0));
      const alt = Math.max(0, ...list.map((x) => x.seconds ?? x.reps ?? 0));
      return { t: parseISO(s.startedAt).getTime(), v: best || alt, kind: best ? 'e1rm' : 'reps' };
    });
}

function Body({ profile }: { profile: Profile }) {
  const now = new Date();
  const units = profile.units;
  const data = useLiveQuery(async () => {
    const body = await db.bodyLogs.orderBy('dayKey').toArray();
    const since = dayKey(addDays(now, -14));
    const mealLogs = await db.mealLogs.where('dayKey').aboveOrEqual(since).toArray();
    const plan = await db.dietPlans.filter((p) => p.active).first();
    const meals = plan ? await db.plannedMeals.where('dietPlanId').equals(plan.id).toArray() : [];
    return { body, mealLogs, meals };
     
  }, []);
  const bundle = useProgram();
  const lifts = useLiftTrends();

  const pts = useMemo(() => (data?.body ?? []).filter((b) => b.weightKg != null).map((b) => ({ dayKey: b.dayKey, value: b.weightKg! })), [data]);
  if (!data) return null;
  if (!pts.length) return <Empty title="No weigh-ins yet" body="Log your weight from Today. After a week you'll see your trend here." />;

  const rate = rateKgPerWeek(pts, now);
  const avg7 = current7dAvg(pts, now);
  const proj = projectedGoalDate(avg7, profile.goalWeightKg, rate?.lossPerWeek, now);
  const week = weeklyAverage(pts, now);
  const ma = movingAverage7(pts);
  const recent = pts.filter((p) => differenceInCalendarDays(now, parseISO(p.dayKey)) <= 60);
  const u = (kg: number) => toUserUnits(kg, units);
  const rows: WeightRow[] = recent.map((p) => ({ t: parseISO(p.dayKey).getTime(), raw: u(p.value), avg: u(ma.find((m) => m.dayKey === p.dayKey)!.value) }));
  if (proj && avg7 != null && differenceInCalendarDays(proj, now) < 120) {
    rows.push({ t: now.getTime(), proj: u(avg7) }, { t: proj.getTime(), proj: u(profile.goalWeightKg) });
  }
  const waist = data.body.filter((b) => b.waistCm != null).map((b) => ({ t: parseISO(b.dayKey).getTime(), v: b.waistCm! }));

  // diet coach inputs
  const firstDay = parseISO(pts[0].dayKey);
  const daysOfData = differenceInCalendarDays(now, firstDay);
  const checks = weeklyLossChecks(pts, now);
  const adherence = bundle
    ? adherencePct(
        Array.from({ length: 14 }, (_, i) => addDays(now, -i - 1)).map((d) => {
          const day = getDayPlan(bundle.days, d);
          return { meals: mealsForDay(data.meals, !day || !isTrainingType(day.type)), logs: data.mealLogs.filter((l) => l.dayKey === dayKey(d)) };
        }),
      )
    : undefined;
  let liftsDown = 0;
  if (lifts) {
    for (const id of lifts.mainIds) {
      const s = seriesFor(lifts.byEx.get(id) ?? [], lifts.sessions).filter((x) => x.kind === 'e1rm' && now.getTime() - x.t < 21 * 864e5);
      const c = pctChange(s.map((x) => x.v));
      if (c != null && c < -5) liftsDown++;
    }
  }

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-2">
        <Tile label="7-day average" value={avg7 != null ? `${displayWeight(avg7, units)} ${units}` : '–'} sub={`Goal ${displayWeight(profile.goalWeightKg, units)} ${units}`} />
        <Tile
          label="Rate"
          value={rate ? `${rate.lossPerWeek >= 0 ? '−' : '+'}${Math.abs(units === 'kg' ? rate.lossPerWeek : rate.lossPerWeek * 2.2046).toFixed(2)} ${units}/wk` : '–'}
          sub={rate ? (rate.lossPerWeek >= 0.5 && rate.lossPerWeek <= 0.75 ? 'In the sweet spot ✅' : rate.lossPerWeek > 1 ? 'Fast: watch strength' : rate.lossPerWeek < 0.3 ? 'Slow: check adherence' : 'Steady') : 'Needs ~10 weigh-ins'}
          Icon={rate && rate.lossPerWeek >= 0 ? ArrowDownRight : ArrowUpRight}
        />
        <Tile label="To go" value={avg7 != null ? `${displayWeight(Math.max(0, avg7 - profile.goalWeightKg), units)} ${units}` : '–'} sub={proj ? `Around ${format(proj, 'MMM d')}` : 'Projection needs a steady trend'} />
        <Tile label="This week" value={`${week.count} weigh-in${week.count === 1 ? '' : 's'}`} sub={week.valid ? `Avg ${displayWeight(week.avg, units)} ${units}` : `Need ${week.needed} more for an average`} />
      </div>

      <DietCoachCard profile={profile} rate={rate?.lossPerWeek} checks={checks} adherence={adherence} liftsDown={liftsDown} daysOfData={daysOfData} />

      <Card>
        <p className="mb-1 font-semibold">Weight</p>
        <WeightChart rows={rows} goal={u(profile.goalWeightKg)} targetDate={profile.targetDate ? parseISO(profile.targetDate).getTime() : undefined} unit={units} />
        <p className="mt-1 text-caption text-muted">Dots: daily weigh-ins · line: 7-day average · dashed: projection · green: goal</p>
      </Card>
      {waist.length > 0 && (
        <Card>
          <p className="mb-1 font-semibold">Waist</p>
          <SimpleLine rows={waist} label="Waist trend" unit="cm" />
        </Card>
      )}
      <Photos />
    </div>
  );
}

function Tile({ label, value, sub, Icon }: { label: string; value: string; sub?: string; Icon?: typeof Flame }) {
  return (
    <div className="rounded-card border border-line/50 bg-surface p-3">
      <p className="text-caption font-semibold text-muted">{label}</p>
      <p className="mt-0.5 flex items-center gap-1 text-[20px] font-bold tnum">
        {Icon && <Icon size={18} className="text-primary-ink" aria-hidden />}
        {value}
      </p>
      {sub && <p className="text-caption text-muted">{sub}</p>}
    </div>
  );
}

function Photos() {
  const photos = useLiveQuery(() => db.photos.orderBy('dayKey').toArray(), []);
  const [pose, setPose] = useState<Pose>('front');
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [pick, setPick] = useState<string[]>([]);
  useEffect(() => {
    if (!photos) return;
    let made: string[] = [];
    void (async () => {
      const m: Record<string, string> = {};
      for (const p of photos) {
        const b = await db.media.get(p.blobId);
        if (b) m[p.id] = URL.createObjectURL(mediaToBlob(b));
      }
      made = Object.values(m);
      setUrls(m);
    })();
    return () => made.forEach((u) => URL.revokeObjectURL(u));
  }, [photos]);
  const list = (photos ?? []).filter((p) => p.pose === pose);
  const compare = pick.length === 2 ? pick.map((id) => list.find((p) => p.id === id)).filter(Boolean) : list.length >= 2 ? [list[0], list[list.length - 1]] : [];
  return (
    <>
      <SectionTitle>Photos</SectionTitle>
      <div className="mb-2 flex gap-2">
        {(['front', 'side', 'back'] as Pose[]).map((p) => (
          <Chip key={p} active={pose === p} onClick={() => setPose(p)} className="capitalize">
            {p}
          </Chip>
        ))}
      </div>
      {list.length === 0 ? (
        <Empty title="No photos yet" body="Add one from Today → Photo. They stay on this phone." />
      ) : (
        <>
          {compare.length === 2 && (
            <div className="grid grid-cols-2 gap-2">
              {compare.map((p) => (
                <figure key={p!.id} className="overflow-hidden rounded-card bg-surface2">
                  <img src={urls[p!.id]} alt={`${pose} on ${p!.dayKey}`} className="aspect-[3/4] w-full object-cover" />
                  <figcaption className="p-2 text-center text-caption text-muted">{format(parseISO(p!.dayKey), 'd MMM yyyy')}</figcaption>
                </figure>
              ))}
            </div>
          )}
          <div className="no-scrollbar -mx-4 mt-2 flex gap-2 overflow-x-auto px-4" role="list" aria-label="Photo timeline">
            {list.map((p) => (
              <button
                key={p.id}
                type="button"
                onClick={() => setPick((s) => (s.includes(p.id) ? s.filter((x) => x !== p.id) : [...s.slice(-1), p.id]))}
                aria-pressed={pick.includes(p.id)}
                aria-label={`Compare photo from ${p.dayKey}`}
                className={`h-24 w-[72px] shrink-0 overflow-hidden rounded-btn border-2 ${pick.includes(p.id) ? 'border-primary' : 'border-transparent'}`}
              >
                {urls[p.id] ? <img src={urls[p.id]} alt="" className="h-full w-full object-cover" /> : <ImageIcon className="m-auto text-muted" aria-hidden />}
              </button>
            ))}
          </div>
          <p className="mt-1 text-caption text-muted">Tap two photos to compare.</p>
        </>
      )}
    </>
  );
}

function Strength({ profile }: { profile: Profile }) {
  const lifts = useLiftTrends();
  if (!lifts) return null;
  const now = Date.now();
  const rows = [...lifts.byEx.entries()]
    .map(([id, sets]) => {
      const s = seriesFor(sets, lifts.sessions);
      const window = s.filter((x) => now - x.t <= 28 * 864e5);
      return { id, ex: lifts.exercises.get(id), s, delta: pctChange((window.length >= 2 ? window : s).map((x) => x.v)), main: lifts.mainIds.has(id) };
    })
    .filter((r) => r.ex && r.s.length)
    .sort((a, b) => Number(b.main) - Number(a.main) || b.s.length - a.s.length);

  const prs: { id: string; t: string; types: string[] }[] = [];
  for (const [id, sets] of lifts.byEx) {
    const chron = [...sets].sort((a, b) => a.completedAt.localeCompare(b.completedAt));
    const seen: SetLog[] = [];
    const firstSession = chron[0]?.sessionId;
    for (const s of chron) {
      if (s.sessionId !== firstSession) {
        const t = detectPRs(s, seen);
        if (t.length) prs.push({ id, t: s.completedAt, types: t });
      }
      seen.push(s);
    }
  }
  const recentPrs = prs.sort((a, b) => b.t.localeCompare(a.t)).filter((p, i, arr) => arr.findIndex((x) => x.id === p.id && x.t.slice(0, 10) === p.t.slice(0, 10)) === i).slice(0, 8);

  if (!rows.length) return <Empty title="No lifts logged yet" body="Finish a session and your strength trends appear here." />;
  return (
    <div className="space-y-2">
      {recentPrs.length > 0 && (
        <Card className="border-warning/30 bg-warning/[0.06]">
          <p className="flex items-center gap-2 font-bold text-warning">
            <Trophy size={18} aria-hidden /> Recent PRs
          </p>
          <ul className="mt-1 space-y-0.5 text-[15px]">
            {recentPrs.map((p) => (
              <li key={p.id + p.t} className="flex justify-between gap-2">
                <span className="truncate">{lifts.exercises.get(p.id)?.name}</span>
                <span className="shrink-0 text-muted">{format(parseISO(p.t), 'd MMM')}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}
      <SectionTitle>Lifts · 4-week change</SectionTitle>
      {rows.map((r) => {
        const last = r.s[r.s.length - 1];
        return (
          <Link key={r.id} to={`/train/library/${r.id}`} className="flex items-center gap-3 rounded-card border border-line/50 bg-surface p-3">
            <div className="min-w-0 flex-1">
              <p className="truncate font-semibold">
                {r.ex!.name} {r.main && <span className="ml-1 rounded bg-primary/15 px-1.5 py-0.5 text-[11px] font-bold text-primary-ink">MAIN</span>}
              </p>
              <p className="text-caption text-muted tnum">
                {last.kind === 'e1rm' ? `e1RM ${displayWeight(last.v, profile.units)} ${profile.units}` : `best ${last.v}`} · {r.s.length} sessions
              </p>
            </div>
            <div className="w-24">
              <Sparkline values={r.s.map((x) => x.v)} width={96} height={36} dots={false} label={`${r.ex!.name} trend`} />
            </div>
            <span className={`w-14 text-right text-[15px] font-bold tnum ${r.delta == null ? 'text-muted' : r.delta >= 0 ? 'text-success' : 'text-danger'}`}>{r.delta == null ? '–' : `${r.delta >= 0 ? '+' : ''}${r.delta.toFixed(0)}%`}</span>
            <ChevronRight size={18} className="text-muted" aria-hidden />
          </Link>
        );
      })}
    </div>
  );
}

function Consistency() {
  const bundle = useProgram();
  const now = new Date();
  const data = useLiveQuery(async () => {
    const since = dayKey(addDays(now, -56));
    return {
      sessions: await db.sessions.where('status').equals('done').toArray(),
      mealLogs: await db.mealLogs.where('dayKey').aboveOrEqual(since).toArray(),
      habitLogs: await db.habitLogs.where('dayKey').aboveOrEqual(since).toArray(),
      defs: await db.habitDefs.toArray(),
      plan: await db.dietPlans.filter((p) => p.active).first(),
      meals: await db.plannedMeals.toArray(),
    };
     
  }, []);
  if (!data || !bundle) return null;
  const plannedPerWeek = bundle.days.filter((d) => isTrainingType(d.type)).length;
  const weeks = Array.from({ length: 8 }, (_, i) => startOfISOWeek(addDays(now, -7 * (7 - i))));
  const bars = weeks.map((w) => ({ week: dayKey(w), done: data.sessions.filter((s) => s.dayKey >= dayKey(w) && s.dayKey < dayKey(addDays(w, 7))).length }));
  const meals = data.plan ? data.meals.filter((m) => m.dietPlanId === data.plan!.id) : [];
  const adh = (n: number) =>
    adherencePct(
      Array.from({ length: n }, (_, i) => addDays(now, -i)).map((d) => {
        const day = getDayPlan(bundle.days, d);
        return { meals: mealsForDay(meals, !day || !isTrainingType(day.type)), logs: data.mealLogs.filter((l) => l.dayKey === dayKey(d)) };
      }),
    );
  const covered = allCoveredDates(bundle.days, data.sessions.map((s) => ({ programDayId: s.programDayId, dayKey: s.dayKey })));
  const streak = trainingStreak((d) => {
    const p = bundle.days.find((x) => x.weekday === weekdayOf(d));
    return !!p && isTrainingType(p.type);
  }, covered, now);
  const habitStreak = (id: string, target?: number) => {
    let n = 0;
    for (let i = 0; i < 56; i++) {
      const k = dayKey(addDays(now, -i));
      const v = data.habitLogs.find((h) => h.dayKey === k && h.habitId === id)?.value ?? 0;
      const hit = target ? v >= target : v > 0;
      if (hit) n++;
      else if (i === 0) continue;
      else break;
    }
    return n;
  };
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-3 gap-2">
        <div className="rounded-card border border-line/50 bg-surface p-3 text-center">
          <Flame size={20} className="mx-auto text-warning" aria-hidden />
          <p className="text-[22px] font-bold tnum">{streak}</p>
          <p className="text-caption text-muted">Session streak</p>
        </div>
        <div className="rounded-card border border-line/50 bg-surface p-3 text-center">
          <p className="text-[22px] font-bold tnum">{adh(7) ?? '–'}%</p>
          <p className="text-caption text-muted">Meals · 7 days</p>
        </div>
        <div className="rounded-card border border-line/50 bg-surface p-3 text-center">
          <p className="text-[22px] font-bold tnum">{adh(28) ?? '–'}%</p>
          <p className="text-caption text-muted">Meals · 28 days</p>
        </div>
      </div>
      <Card>
        <p className="mb-1 font-semibold">Sessions per week</p>
        <WeekBars rows={bars} target={plannedPerWeek} />
        <p className="text-caption text-muted">Dashed line: {plannedPerWeek} planned per week</p>
      </Card>
      <SectionTitle>Habit streaks</SectionTitle>
      <div className="divide-y divide-line/50 rounded-card border border-line/50 bg-surface">
        {data.defs
          .sort((a, b) => a.order - b.order)
          .map((h) => (
            <div key={h.id} className="flex min-h-[52px] items-center justify-between px-4">
              <span className="font-medium">{h.label}</span>
              <span className="text-[17px] font-bold tnum">{habitStreak(h.id, h.kind === 'number' ? h.target : undefined)} days</span>
            </div>
          ))}
      </div>
    </div>
  );
}
