import { useLiveQuery } from 'dexie-react-hooks';
import { useMemo } from 'react';
import { db, getMeta } from './db';
import { dayKey, weekDates, weekStartOf } from '@/domain/schedule';
import { replanWeek, type WeekPlan } from '@/domain/replan';
import type { Exercise, PlannedExercise, Profile, Program, ProgramDay, DietPlan, PlannedMeal } from '@/domain/types';
import { WEEKDAYS } from '@/domain/types';

/** undefined = loading, null = none */
export function useProfile(): Profile | null | undefined {
  return useLiveQuery(async () => (await db.profile.get('me')) ?? null, []);
}

export interface ProgramBundle {
  program: Program;
  days: ProgramDay[];
  planned: PlannedExercise[];
}

export function useProgram(): ProgramBundle | null | undefined {
  return useLiveQuery(async () => {
    const program = (await db.programs.filter((p) => p.active).first()) ?? null;
    if (!program) return null;
    const days = (await db.programDays.where('programId').equals(program.id).toArray()).sort(
      (a, b) => WEEKDAYS.indexOf(a.weekday) - WEEKDAYS.indexOf(b.weekday),
    );
    const dayIds = days.map((d) => d.id);
    const planned = (await db.plannedExercises.where('dayId').anyOf(dayIds).toArray()).sort((a, b) => a.order - b.order);
    return { program, days, planned };
  }, []);
}

export function useExerciseMap(): Map<string, Exercise> {
  const list = useLiveQuery(() => db.exercises.toArray(), []);
  return useMemo(() => new Map((list ?? []).map((e) => [e.id, e])), [list]);
}

export function useDiet(): { plan: DietPlan; meals: PlannedMeal[] } | null | undefined {
  return useLiveQuery(async () => {
    const plan = (await db.dietPlans.filter((p) => p.active).first()) ?? null;
    if (!plan) return null;
    const meals = (await db.plannedMeals.where('dietPlanId').equals(plan.id).toArray()).sort((a, b) => a.time.localeCompare(b.time) || a.order - b.order);
    return { plan, meals };
  }, []);
}

export const replanOffKey = (date: Date) => `replanOff:${dayKey(weekStartOf(date))}`;

/** This week's plan with the missed-session auto re-plan applied (unless the user kept the original). */
export function useWeekPlan(date: Date, bundle: ProgramBundle | null | undefined): (WeekPlan<ProgramDay> & { off: boolean }) | undefined {
  const k = dayKey(date);
  const data = useLiveQuery(async () => {
    const dates = weekDates(date).map(dayKey);
    const sessions = await db.sessions.where('dayKey').between(dates[0], dates[6], true, true).toArray();
    const off = !!(await getMeta<boolean>(replanOffKey(date)));
    const since = await getMeta<string>('onboardedAt');
    return { since, done: sessions.filter((s) => s.status === 'done').map((s) => ({ programDayId: s.programDayId, dayKey: s.dayKey })), off };
  }, [k]);
  return useMemo(() => {
    if (!bundle || !data) return undefined;
    const plan = replanWeek({ days: bundle.days, today: date, done: data.done, since: data.since ? new Date(data.since) : undefined });
    if (data.off) return { ...plan, byDate: plan.original, adjusted: false, off: true, missed: plan.missed, dropped: [] };
    return { ...plan, off: false };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bundle, data, k]);
}

export function useActiveSession() {
  return useLiveQuery(async () => {
    const a = await db.activeSession.get('current');
    if (!a) return null;
    const s = await db.sessions.get(a.sessionId);
    if (!s || s.status !== 'active') return null;
    return { active: a, session: s };
  }, []);
}
