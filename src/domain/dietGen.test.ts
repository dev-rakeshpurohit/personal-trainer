import { dietTargets, generateDiet, kcalFloorFor } from './dietGen';
import { plannedTotals } from './diet';
import type { DietType } from './types';
import type { Goal } from './generator';

const base = { sex: 'male' as const, age: 37, heightCm: 178, weightKg: 79, goalWeightKg: 73, trainingDays: 5, intolerances: [] as string[] };

describe('diet targets', () => {
  it('fat loss for the reference user lands near the hand-made plan (≈2,000–2,300 kcal, ~150 g)', () => {
    const t = dietTargets({ ...base, goal: 'fat_loss' });
    expect(t.kcal).toBeGreaterThanOrEqual(1950);
    expect(t.kcal).toBeLessThanOrEqual(2350);
    expect(t.proteinG).toBeGreaterThanOrEqual(140);
    expect(t.proteinG).toBeLessThanOrEqual(160);
  });
  it('muscle gain is a surplus; floors are respected', () => {
    expect(dietTargets({ ...base, goal: 'muscle' }).kcal).toBeGreaterThan(dietTargets({ ...base, goal: 'general' }).kcal);
    const tiny = dietTargets({ ...base, sex: 'female', weightKg: 45, goalWeightKg: 42, heightCm: 150, age: 60, trainingDays: 2, goal: 'fat_loss' });
    expect(tiny.kcal).toBe(kcalFloorFor('female'));
  });
});

const diets: DietType[] = ['veg', 'veg_egg', 'nonveg', 'vegan'];
const goals: Goal[] = ['fat_loss', 'lean', 'muscle', 'strength', 'general'];
const intol = [[], ['lactose'], ['lactose', 'paneer'], ['gluten'], ['soy', 'nuts']];

describe('diet generator', () => {
  for (const d of diets)
    for (const g of goals)
      for (const x of intol)
        it(`${d} · ${g} · [${x.join(',')}] hits targets and respects restrictions`, () => {
          const r = generateDiet({ ...base, goal: g, dietType: d, intolerances: x });
          const t = plannedTotals(r.meals);
          expect(Math.abs(t.kcal - r.kcalTarget) / r.kcalTarget).toBeLessThan(0.12);
          expect(t.proteinG).toBeGreaterThanOrEqual(r.proteinTargetG * (d === 'vegan' && x.includes('soy') ? 0.7 : 0.85));
          const text = r.meals.flatMap((m) => [...m.items, ...(m.rotate ?? [])]).join(' ').toLowerCase();
          if (d !== 'nonveg') expect(text).not.toMatch(/chicken|fish/);
          if (d === 'veg' || d === 'vegan') expect(text).not.toMatch(/\beggs?\b|egg white/);
          if (d === 'vegan') expect(text).not.toMatch(/whey|toned milk|curd|yogurt|paneer/);
          if (x.includes('lactose')) expect(text).not.toMatch(/toned milk|curd|yogurt|paneer/);
          if (x.includes('gluten')) expect(text).not.toMatch(/oats|medium roti|toast/);
          if (x.includes('soy')) expect(text).not.toMatch(/soya|tofu|soy milk|edamame/);
          if (x.includes('nuts')) expect(text).not.toMatch(/almond/);
          expect(r.meals.find((m) => m.meal === 'Pre-workout')?.skipOnRestDay).toBe(true);
        });
});
