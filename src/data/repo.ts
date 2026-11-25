import { db, uid } from './db';
import type { BodyLog, MealLog, PlannedMeal } from '@/domain/types';

export async function upsertBody(dayKey: string, patch: Partial<Omit<BodyLog, 'id' | 'dayKey'>>): Promise<void> {
  const existing = await db.bodyLogs.where('dayKey').equals(dayKey).first();
  if (existing) await db.bodyLogs.update(existing.id, patch);
  else await db.bodyLogs.add({ id: uid(), dayKey, ...patch });
}

export async function lastWeight(): Promise<number | undefined> {
  const logs = await db.bodyLogs.orderBy('dayKey').reverse().toArray();
  return logs.find((l) => l.weightKg != null)?.weightKg;
}
export async function lastWaist(): Promise<number | undefined> {
  const logs = await db.bodyLogs.orderBy('dayKey').reverse().toArray();
  return logs.find((l) => l.waistCm != null)?.waistCm;
}

export async function setHabit(dayKey: string, habitId: string, value: number): Promise<void> {
  const existing = await db.habitLogs.where('[dayKey+habitId]').equals([dayKey, habitId]).first();
  if (existing) await db.habitLogs.update(existing.id, { value });
  else await db.habitLogs.add({ id: uid(), dayKey, habitId, value });
}

export async function getHabit(dayKey: string, habitId: string): Promise<number> {
  return (await db.habitLogs.where('[dayKey+habitId]').equals([dayKey, habitId]).first())?.value ?? 0;
}

/** Log a meal state; returns an undo function restoring the previous state. */
export async function logMeal(
  dayKey: string,
  meal: PlannedMeal,
  state: MealLog['state'],
  extra: Partial<Pick<MealLog, 'label' | 'proteinG' | 'kcal' | 'chosenRotation'>> = {},
): Promise<() => Promise<void>> {
  const prev = await db.mealLogs.where('[dayKey+plannedMealId]').equals([dayKey, meal.id]).first();
  const row: MealLog = {
    id: prev?.id ?? uid(),
    dayKey,
    plannedMealId: meal.id,
    state,
    label: extra.label,
    proteinG: state === 'skipped' ? 0 : (extra.proteinG ?? meal.proteinG),
    kcal: state === 'skipped' ? 0 : (extra.kcal ?? meal.kcal),
    chosenRotation: extra.chosenRotation ?? prev?.chosenRotation,
    loggedAt: new Date().toISOString(),
  };
  await db.mealLogs.put(row);
  return async () => {
    if (prev) await db.mealLogs.put(prev);
    else await db.mealLogs.delete(row.id);
  };
}

export async function clearMeal(dayKey: string, mealId: string): Promise<() => Promise<void>> {
  const prev = await db.mealLogs.where('[dayKey+plannedMealId]').equals([dayKey, mealId]).first();
  if (prev) await db.mealLogs.delete(prev.id);
  return async () => {
    if (prev) await db.mealLogs.put(prev);
  };
}
