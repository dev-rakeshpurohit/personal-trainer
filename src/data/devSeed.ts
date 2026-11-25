/**
 * Dev-only: replaces logs with ~30 days of realistic demo data so every chart and coach card can be checked.
 * Lazy-loaded from Settings → Developer (hidden unless enabled). Never touches the plan or profile.
 */
import { addDays, addMinutes, startOfWeek } from 'date-fns';
import { db, setMeta, uid } from './db';
import { dayKey, getDayPlan } from '@/domain/schedule';
import { incrementFor } from '@/domain/progression';
import type { BodyLog, HabitLog, MealLog, Session, SetLog } from '@/domain/types';
import { isTrainingType } from '@/domain/types';

function rng(seed: number) {
  let s = seed;
  return () => {
    s = (s * 1664525 + 1013904223) % 4294967296;
    return s / 4294967296;
  };
}

export async function seedDemoData(days = 30, today = new Date()): Promise<{ sessions: number; sets: number; weighIns: number }> {
  const rand = rng(42);
  const profile = await db.profile.get('me');
  const program = await db.programs.filter((p) => p.active).first();
  if (!profile || !program) throw new Error('Finish onboarding first');
  const programDays = await db.programDays.where('programId').equals(program.id).toArray();
  const planned = await db.plannedExercises.where('dayId').anyOf(programDays.map((d) => d.id)).toArray();
  const exercises = new Map((await db.exercises.toArray()).map((e) => [e.id, e]));
  const diet = await db.dietPlans.filter((p) => p.active).first();
  const meals = diet ? await db.plannedMeals.where('dietPlanId').equals(diet.id).toArray() : [];
  const start = addDays(today, -days);

  await db.transaction('rw', [db.sessions, db.sets, db.mealLogs, db.habitLogs, db.bodyLogs, db.activeSession, db.programs, db.meta], async () => {
    await Promise.all([db.sessions.clear(), db.sets.clear(), db.mealLogs.clear(), db.habitLogs.clear(), db.bodyLogs.clear(), db.activeSession.clear()]);
    await db.programs.update(program.id, { startedOn: dayKey(startOfWeek(start, { weekStartsOn: 1 })) });
    await setMeta('onboardedAt', start.toISOString());
    await setMeta('lastBackupAt', addDays(today, -35).toISOString());

    const body: BodyLog[] = [];
    const sessions: Session[] = [];
    const sets: SetLog[] = [];
    const mealLogs: MealLog[] = [];
    const habits: HabitLog[] = [];
    const baseW = profile.startWeightKg + 0.8;
    const sessionCount = new Map<string, number>();

    for (let i = 0; i < days; i++) {
      const d = addDays(start, i);
      const k = dayKey(d);
      if (rand() < 0.8) body.push({ id: uid(), dayKey: k, weightKg: Math.round((baseW - 0.085 * i + (rand() - 0.5) * 0.6) * 10) / 10, waistCm: i % 14 === 0 ? Math.round((92 - i * 0.07) * 10) / 10 : undefined });
      else if (i % 14 === 0) body.push({ id: uid(), dayKey: k, waistCm: Math.round((92 - i * 0.07) * 10) / 10 });

      const day = getDayPlan(programDays, d);
      if (day && isTrainingType(day.type) && rand() < 0.9) {
        const n = sessionCount.get(day.id) ?? 0;
        sessionCount.set(day.id, n + 1);
        const startedAt = new Date(d);
        startedAt.setHours(9, 15, 0, 0);
        const s: Session = {
          id: uid(),
          dayKey: k,
          programDayId: day.id,
          title: day.title,
          startedAt: startedAt.toISOString(),
          endedAt: addMinutes(startedAt, 60 + Math.round(rand() * 20)).toISOString(),
          status: 'done',
          cycleWeek: Math.floor(i / 7) + 1,
          deload: false,
          mode: 'full',
          rpe: 6 + Math.round(rand() * 3),
          feedback: { rpe: 7, feel: rand() < 0.15 ? 'too_hard' : 'just_right', pain: [], disliked: [], ranOutOfTime: false, energy: 'ok' },
        };
        sessions.push(s);
        for (const pe of planned.filter((p) => p.dayId === day.id)) {
          const ex = exercises.get(pe.exerciseId);
          const inc = ex ? incrementFor(ex, profile.stepKg) : 2;
          const base = ex?.isBodyweight ? undefined : (/barbell|trap/i.test(ex?.name ?? '') ? 40 : /press|row|pulldown|leg/i.test(ex?.name ?? '') ? 14 : 10) + inc * Math.floor(n / 2);
          for (let si = 0; si < pe.sets; si++) {
            const t = addMinutes(startedAt, 6 + si * 3 + pe.order * 9).toISOString();
            const reps = Math.min(pe.repsMax, pe.repsMin + ((n + si) % (pe.repsMax - pe.repsMin + 1)));
            sets.push({
              id: uid(),
              sessionId: s.id,
              exerciseId: pe.exerciseId,
              plannedExerciseId: pe.id,
              setIndex: si,
              weightKg: base,
              reps: pe.unit === 'reps' ? reps : undefined,
              seconds: pe.unit === 'seconds' ? Math.min(60, pe.repsMin + n * 3) : pe.unit === 'minutes' ? pe.repsMin * 60 : undefined,
              meters: pe.unit === 'meters' ? pe.repsMin : undefined,
              rir: pe.unit === 'reps' ? 2 : undefined,
              completedAt: t,
              isWarmup: false,
            });
          }
        }
      }
      const rest = !day || !isTrainingType(day.type);
      for (const m of meals) {
        if (rest && m.skipOnRestDay) continue;
        if (m.optional && rand() < 0.7) continue;
        const r = rand();
        if (r < 0.82) mealLogs.push({ id: uid(), dayKey: k, plannedMealId: m.id, state: 'eaten', proteinG: m.proteinG, kcal: m.kcal, loggedAt: d.toISOString() });
        else if (r < 0.9) mealLogs.push({ id: uid(), dayKey: k, plannedMealId: m.id, state: 'swapped', label: 'Something similar', proteinG: Math.round(m.proteinG * 0.8), kcal: m.kcal, loggedAt: d.toISOString() });
        else if (r < 0.95) mealLogs.push({ id: uid(), dayKey: k, plannedMealId: m.id, state: 'skipped', proteinG: 0, kcal: 0, loggedAt: d.toISOString() });
      }
      habits.push({ id: uid(), dayKey: k, habitId: 'water', value: 2000 + Math.round(rand() * 6) * 250 });
      habits.push({ id: uid(), dayKey: k, habitId: 'steps', value: 5000 + Math.round(rand() * 12) * 500 });
      habits.push({ id: uid(), dayKey: k, habitId: 'sleep', value: 6 + Math.round(rand() * 4) / 2 });
      if (rand() < 0.85) habits.push({ id: uid(), dayKey: k, habitId: 'creatine', value: 1 });
      if (rand() < 0.75) habits.push({ id: uid(), dayKey: k, habitId: 'oil', value: 1 });
    }
    await db.bodyLogs.bulkAdd(body);
    await db.sessions.bulkAdd(sessions);
    await db.sets.bulkAdd(sets);
    await db.mealLogs.bulkAdd(mealLogs);
    await db.habitLogs.bulkAdd(habits);
  });
  return { sessions: await db.sessions.count(), sets: await db.sets.count(), weighIns: await db.bodyLogs.filter((b) => b.weightKg != null).count() };
}
