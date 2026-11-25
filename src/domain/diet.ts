import type { MealLog, PlannedMeal } from './types';

export const mealsForDay = <T extends Pick<PlannedMeal, 'skipOnRestDay'>>(meals: T[], restDay: boolean): T[] =>
  restDay ? meals.filter((m) => !m.skipOnRestDay) : meals;

export interface Totals {
  proteinG: number;
  kcal: number;
}

/** Planned totals for non-optional meals. */
export const plannedTotals = (meals: Pick<PlannedMeal, 'proteinG' | 'kcal' | 'optional'>[]): Totals =>
  meals.filter((m) => !m.optional).reduce((a, m) => ({ proteinG: a.proteinG + m.proteinG, kcal: a.kcal + m.kcal }), { proteinG: 0, kcal: 0 });

/** Day totals from logs: eaten/swapped count their logged values, skipped = 0. */
export const dayTotals = (logs: Pick<MealLog, 'state' | 'proteinG' | 'kcal'>[]): Totals =>
  logs
    .filter((l) => l.state !== 'skipped')
    .reduce((a, l) => ({ proteinG: a.proteinG + l.proteinG, kcal: a.kcal + l.kcal }), { proteinG: 0, kcal: 0 });

/** Adherence = eaten-or-swapped non-optional meals / planned non-optional meals (0–100). */
export function adherencePct(
  days: { meals: Pick<PlannedMeal, 'id' | 'optional'>[]; logs: Pick<MealLog, 'plannedMealId' | 'state'>[] }[],
): number | undefined {
  let planned = 0;
  let hit = 0;
  for (const d of days) {
    const req = d.meals.filter((m) => !m.optional);
    planned += req.length;
    for (const m of req) {
      const l = d.logs.find((x) => x.plannedMealId === m.id);
      if (l && l.state !== 'skipped') hit++;
    }
  }
  return planned ? Math.round((hit / planned) * 100) : undefined;
}

/** The next meal to show on Today: first unlogged non-optional meal at/after now, else first unlogged. */
export function nextMeal<T extends Pick<PlannedMeal, 'id' | 'time' | 'optional'>>(meals: T[], loggedIds: Set<string>, nowHHmm: string): T | undefined {
  const open = meals.filter((m) => !loggedIds.has(m.id) && !m.optional);
  return open.find((m) => m.time >= nowHHmm) ?? open[0];
}

/** Suggested targets (Mifflin-St Jeor, moderate activity, ~20% deficit) for users without a template. */
export function suggestTargets(p: { sex: 'male' | 'female' | 'other'; age: number; heightCm: number; weightKg: number; goalWeightKg: number }): Totals {
  const s = p.sex === 'male' ? 5 : p.sex === 'female' ? -161 : -78;
  const bmr = 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age + s;
  const tdee = bmr * 1.55;
  const floor = p.sex === 'female' ? 1400 : 1700;
  const kcal = Math.max(floor, Math.round((tdee * 0.8) / 50) * 50);
  const proteinG = Math.round((2 * Math.min(p.weightKg, Math.max(p.goalWeightKg, p.weightKg * 0.85))) / 5) * 5;
  return { kcal, proteinG };
}

export const kcalFloor = (sex: 'male' | 'female' | 'other') => (sex === 'female' ? 1400 : 1700);
