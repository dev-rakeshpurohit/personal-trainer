import { addDays, format, isToday } from 'date-fns';
import { useLiveQuery } from 'dexie-react-hooks';
import { ChevronLeft, ChevronRight, Moon } from 'lucide-react';
import { useMemo, useState } from 'react';
import { Empty, PageHeader, SectionTitle } from '@/components/ui';
import { db } from '@/data/db';
import { useDiet, useProfile, useProgram, useWeekPlan } from '@/data/hooks';
import { adherencePct, dayTotals, mealsForDay, plannedTotals } from '@/domain/diet';
import { dayKey, getDayPlan, weekDates } from '@/domain/schedule';
import { isTrainingType } from '@/domain/types';
import { Habits } from './Habits';
import { MealCard } from './MealCard';

export default function Eat() {
  const [date, setDate] = useState(() => new Date());
  const k = dayKey(date);
  const profile = useProfile();
  const diet = useDiet();
  const bundle = useProgram();
  const week = useWeekPlan(new Date(), bundle);
  const data = useLiveQuery(
    async () => ({
      logs: await db.mealLogs.where('dayKey').equals(k).toArray(),
      habits: await db.habitLogs.where('dayKey').equals(k).toArray(),
      defs: await db.habitDefs.toArray(),
      weekLogs: await db.mealLogs.where('dayKey').between(dayKey(weekDates(date)[0]), dayKey(weekDates(date)[6]), true, true).toArray(),
    }),
    [k],
  );

  const day = week?.byDate[k] ?? (bundle ? getDayPlan(bundle.days, date) : undefined);
  const restDay = !day || !isTrainingType(day.type);
  const meals = useMemo(() => (diet ? mealsForDay(diet.meals, restDay) : []), [diet, restDay]);
  const totals = dayTotals(data?.logs ?? []);
  const plan = plannedTotals(meals);
  const pTarget = diet?.plan.proteinTargetG ?? profile?.proteinTargetG ?? 150;
  const kTarget = diet?.plan.kcalTarget ?? profile?.kcalTarget ?? 2000;
  const weekAdherence = useMemo(() => {
    if (!diet || !data) return undefined;
    const days = weekDates(date)
      .filter((d) => d <= new Date())
      .map((d) => ({ meals: diet.meals, logs: data.weekLogs.filter((l) => l.dayKey === dayKey(d)) }));
    return adherencePct(days);
  }, [diet, data, date]);

  return (
    <div className="animate-fade-in">
      <PageHeader title="Eat" sub={diet?.plan.name} />
      <div className="flex items-center justify-between px-4">
        <button type="button" onClick={() => setDate(addDays(date, -1))} className="flex h-12 w-12 items-center justify-center rounded-full bg-surface2" aria-label="Previous day">
          <ChevronLeft size={22} aria-hidden />
        </button>
        <div className="text-center">
          <p className="text-[17px] font-bold">{isToday(date) ? 'Today' : format(date, 'EEEE')}</p>
          <p className="text-caption text-muted">
            {format(date, 'd MMM')} · {restDay ? 'rest-day menu' : day?.title.split(' –')[0]}
          </p>
        </div>
        <button type="button" onClick={() => setDate(addDays(date, 1))} disabled={isToday(date)} className="flex h-12 w-12 items-center justify-center rounded-full bg-surface2 disabled:opacity-30" aria-label="Next day">
          <ChevronRight size={22} aria-hidden />
        </button>
      </div>

      <div className="space-y-3 px-4 pb-24 pt-3">
        {restDay && (
          <p className="flex items-center gap-2 rounded-btn bg-surface2 px-3 py-2 text-[14px] text-muted">
            <Moon size={16} aria-hidden /> Rest day: the pre-gym snack is hidden ({plan.kcal.toLocaleString()} kcal planned).
          </p>
        )}
        {!diet && <Empty title="No diet plan yet" body="Add meals in More → Plan editor → Diet." />}
        {meals.map((m) => (
          <MealCard key={m.id} meal={m} log={data?.logs.find((l) => l.plannedMealId === m.id)} dayKey={k} />
        ))}

        <SectionTitle>Habits</SectionTitle>
        {data && <Habits defs={data.defs} logs={data.habits} dayKey={k} />}
        {weekAdherence != null && (
          <p className="px-1 pt-2 text-caption text-muted">
            This week you've hit <span className="font-bold text-text">{weekAdherence}%</span> of planned meals. Aim for 80%+.
          </p>
        )}
      </div>

      {/* Sticky running totals */}
      <div role="status" aria-label="Day totals" className="glass fixed inset-x-0 bottom-[calc(64px+env(safe-area-inset-bottom))] z-20 border-t border-line/50 px-4 py-2.5">
        <div className="flex items-center justify-between gap-3 text-[15px] font-semibold tnum">
          <span>
            Protein <span className={totals.proteinG >= pTarget * 0.95 ? 'text-success' : 'text-primary-ink'}>{totals.proteinG}</span>
            <span className="text-muted">/{pTarget} g</span>
          </span>
          <span>
            <span className={totals.kcal > kTarget * 1.05 ? 'text-warning' : ''}>{totals.kcal.toLocaleString()}</span>
            <span className="text-muted">/{kTarget.toLocaleString()} kcal</span>
          </span>
        </div>
        <div className="mt-1.5 flex gap-1.5" aria-hidden>
          <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface2">
            <div className="h-full rounded-full bg-primary transition-[width] duration-300" style={{ width: `${Math.min(100, (totals.proteinG / pTarget) * 100)}%` }} />
          </div>
          <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface2">
            <div className="h-full rounded-full bg-warning transition-[width] duration-300" style={{ width: `${Math.min(100, (totals.kcal / kTarget) * 100)}%` }} />
          </div>
        </div>
      </div>
    </div>
  );
}

