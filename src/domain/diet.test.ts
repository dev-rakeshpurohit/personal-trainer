import seed from '../../seed/diet.lean-veg-egg-2000.json';
import { adherencePct, dayTotals, mealsForDay, nextMeal, plannedTotals, suggestTargets } from './diet';
import { dietAdjustment } from './coach';

const meals = seed.trainingDay.map((m, i) => ({ ...m, id: `m${i}`, optional: 'optional' in m ? m.optional : false }));

describe('diet totals', () => {
  it('training day ≈ 150 g protein / ≈ 2,000 kcal', () => {
    const t = plannedTotals(mealsForDay(meals, false));
    expect(t.proteinG).toBeGreaterThanOrEqual(145);
    expect(t.proteinG).toBeLessThanOrEqual(160);
    expect(Math.abs(t.kcal - 2000)).toBeLessThanOrEqual(50);
  });
  it('rest day hides pre-gym snack (≈ 1,950 kcal)', () => {
    const rest = mealsForDay(meals, true);
    expect(rest.find((m) => m.meal === 'Pre-gym')).toBeUndefined();
    expect(Math.abs(plannedTotals(rest).kcal - 1950)).toBeLessThanOrEqual(50);
  });
  it('skipped meals count zero', () => {
    expect(dayTotals([{ state: 'eaten', proteinG: 10, kcal: 100 }, { state: 'skipped', proteinG: 50, kcal: 500 }])).toEqual({ proteinG: 10, kcal: 100 });
  });
  it('adherence ignores optional meals', () => {
    const ms = [{ id: 'a' }, { id: 'b' }, { id: 'c', optional: true }];
    expect(adherencePct([{ meals: ms, logs: [{ plannedMealId: 'a', state: 'eaten' }, { plannedMealId: 'b', state: 'skipped' }] }])).toBe(50);
    expect(adherencePct([])).toBeUndefined();
  });
  it('next meal is the first unlogged one from now', () => {
    expect(nextMeal(meals, new Set(['m0']), '07:00')?.meal).toBe('Breakfast');
    expect(nextMeal(meals, new Set(), '13:00')?.meal).toBe('Snack');
    expect(nextMeal(meals, new Set(), '23:00')?.meal).toBe('Pre-gym');
  });
  it('suggests targets with a kcal floor', () => {
    const t = suggestTargets({ sex: 'male', age: 37, heightCm: 178, weightKg: 79, goalWeightKg: 73 });
    expect(t.kcal).toBeGreaterThanOrEqual(1700);
    expect(t.proteinG).toBeGreaterThan(120);
  });
});

describe('diet adjustment coach', () => {
  const base = { daysOfData: 21, liftsDown: 0, sex: 'male' as const, kcalTarget: 2000, riceReduced: false };
  it('needs 14 days', () => expect(dietAdjustment({ ...base, daysOfData: 10, checks: [0.6] })).toBeUndefined());
  it('on track', () => expect(dietAdjustment({ ...base, checks: [0.6, 0.6], adherence: 90 })?.kind).toBe('on_track'));
  it('stalled 2 checks with good adherence', () => {
    const c = dietAdjustment({ ...base, checks: [0.2, 0.1], adherence: 85 })!;
    expect(c.kind).toBe('stalled');
    expect(c.kcalDelta).toBe(-65);
  });
  it('stalled with poor adherence → adherence first', () =>
    expect(dietAdjustment({ ...base, checks: [0.2, 0.1], adherence: 60 })?.kind).toBe('adherence'));
  it('losing too fast → eat more', () => expect(dietAdjustment({ ...base, checks: [1.2], adherence: 90 })?.kind).toBe('eat_more'));
  it('lifts down → eat more', () => expect(dietAdjustment({ ...base, checks: [0.6], adherence: 90, liftsDown: 2 })?.kind).toBe('eat_more'));
  it('warns below the kcal floor', () =>
    expect(dietAdjustment({ ...base, kcalTarget: 1750, checks: [0.1, 0.1], adherence: 90 })?.floorWarning).toBe(true));
});

describe('diet changes', () => {
  it('stalled → lunch rice 100 g → 50 g, then eat_more puts it back', async () => {
    const { dietChangeFor, riceReduced } = await import('./diet');
    const c = dietChangeFor('stalled', meals)!;
    expect(c.description).toMatch(/Lunch: rice → 50 g/);
    expect(c.kcal).toBe(680 - 65);
    const after = meals.map((m) => (m.id === c.mealId ? { ...m, items: c.items, kcal: c.kcal } : m));
    expect(riceReduced(after)).toBe(true);
    expect(dietChangeFor('stalled', after)).toBeUndefined();
    const back = dietChangeFor('eat_more', after)!;
    expect(back.items.some((i) => i.includes('100 g cooked rice'))).toBe(true);
  });
  it('eat_more without reduced rice adds toast at breakfast', async () => {
    const { dietChangeFor } = await import('./diet');
    const c = dietChangeFor('eat_more', meals)!;
    expect(c.description).toMatch(/Breakfast: \+1 slice multigrain toast/);
    expect(c.kcal).toBe(390 + 70);
  });
});
