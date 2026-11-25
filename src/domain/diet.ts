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

export interface MealChange {
  mealId: string;
  items: string[];
  kcal: number;
  proteinG: number;
  description: string;
}

/** Turn a diet-coach card into a concrete meal edit (doc 06 §6). Pure. */
export function dietChangeFor(kind: 'stalled' | 'eat_more', meals: Pick<PlannedMeal, 'id' | 'meal' | 'items' | 'kcal' | 'proteinG'>[]): MealChange | undefined {
  const riceMeal = meals.find((m) => m.items.some((i) => /cooked rice/i.test(i)));
  const riceItem = riceMeal?.items.find((i) => /cooked rice/i.test(i));
  const reduced = !!riceItem && /\b50 g\b/.test(riceItem);
  if (kind === 'stalled') {
    if (!riceMeal || !riceItem || reduced) return undefined;
    return {
      mealId: riceMeal.id,
      items: riceMeal.items.map((i) => (i === riceItem ? i.replace(/\d+\s*g/, '50 g') : i)),
      kcal: riceMeal.kcal - 65,
      proteinG: riceMeal.proteinG - 1,
      description: `${riceMeal.meal}: rice → 50 g (−65 kcal)`,
    };
  }
  if (riceMeal && riceItem && reduced)
    return {
      mealId: riceMeal.id,
      items: riceMeal.items.map((i) => (i === riceItem ? i.replace(/50\s*g/, '100 g') : i)),
      kcal: riceMeal.kcal + 65,
      proteinG: riceMeal.proteinG + 1,
      description: `${riceMeal.meal}: rice back to 100 g (+65 kcal)`,
    };
  const breakfast = meals.find((m) => /breakfast/i.test(m.meal)) ?? meals[0];
  if (!breakfast || breakfast.items.some((i) => /multigrain toast/i.test(i))) return undefined;
  return {
    mealId: breakfast.id,
    items: [...breakfast.items, '1 slice multigrain toast'],
    kcal: breakfast.kcal + 70,
    proteinG: breakfast.proteinG + 3,
    description: `${breakfast.meal}: +1 slice multigrain toast (+70 kcal)`,
  };
}

export const riceReduced = (meals: Pick<PlannedMeal, 'items'>[]) => meals.some((m) => m.items.some((i) => /cooked rice/i.test(i) && /\b50 g\b/.test(i)));
