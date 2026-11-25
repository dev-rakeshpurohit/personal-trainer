/**
 * Diet generator (pure). Targets from Mifflin–St Jeor × activity × goal; protein by g/kg.
 * Meals are built from an Indian-friendly food list filtered by diet type and intolerances,
 * then portions are scaled so the day hits the protein and calorie targets.
 * Values are typical label/IFCT approximations; good enough for planning, not medical nutrition.
 */
import type { DietType, Goal, Sex } from './types';

export type Tag = 'lactose' | 'paneer' | 'egg' | 'meat' | 'fish' | 'soy' | 'gluten' | 'nuts' | 'dairy';

interface Food {
  id: string;
  label: (q: number) => string;
  kcal: number; // per unit
  protein: number; // per unit
  unit: 'g' | 'ml' | 'pc' | 'scoop' | 'tsp' | 'serving';
  qty: number; // default quantity
  step: number; // rounding step
  min: number;
  max: number;
  role: 'protein' | 'carb' | 'fixed';
  tags: Tag[];
}

const F = (f: Food) => f;
const scoops = (q: number) => (q === 0.5 ? '½ scoop' : q === 1 ? '1 scoop' : q === 1.5 ? '1½ scoops' : `${q} scoops`);
const FOODS = {
  whey: F({ id: 'whey', label: (q) => `${scoops(q)} whey isolate in water`, kcal: 115, protein: 26, unit: 'scoop', qty: 1, step: 0.5, min: 0.5, max: 2, role: 'protein', tags: ['dairy'] }),
  pea: F({ id: 'pea', label: (q) => `${scoops(q)} pea/plant protein in water`, kcal: 120, protein: 24, unit: 'scoop', qty: 1, step: 0.5, min: 0.5, max: 2, role: 'protein', tags: [] }),
  eggs: F({ id: 'eggs', label: (q) => `${q} whole eggs`, kcal: 70, protein: 6, unit: 'pc', qty: 2, step: 1, min: 1, max: 3, role: 'fixed', tags: ['egg'] }),
  whites: F({ id: 'whites', label: (q) => `${q} egg white${q === 1 ? '' : 's'}`, kcal: 17, protein: 3.6, unit: 'pc', qty: 4, step: 1, min: 0, max: 8, role: 'protein', tags: ['egg'] }),
  besan: F({ id: 'besan', label: (q) => `Besan chilla (${q} g besan) with veggies`, kcal: 3.9, protein: 0.22, unit: 'g', qty: 60, step: 10, min: 40, max: 100, role: 'protein', tags: [] }),
  tofuB: F({ id: 'tofuB', label: (q) => `Tofu bhurji (${q} g firm tofu)`, kcal: 1.45, protein: 0.15, unit: 'g', qty: 150, step: 25, min: 100, max: 250, role: 'protein', tags: ['soy'] }),
  oats: F({ id: 'oats', label: (q) => `${q} g oats (cooked in water)`, kcal: 3.8, protein: 0.13, unit: 'g', qty: 40, step: 10, min: 20, max: 80, role: 'carb', tags: ['gluten'] }),
  poha: F({ id: 'poha', label: (q) => `${q} g poha with peas`, kcal: 3.6, protein: 0.07, unit: 'g', qty: 50, step: 10, min: 30, max: 90, role: 'carb', tags: [] }),
  toast: F({ id: 'toast', label: (q) => `${q} slice${q > 1 ? 's' : ''} multigrain toast`, kcal: 70, protein: 3, unit: 'pc', qty: 1, step: 1, min: 0, max: 3, role: 'carb', tags: ['gluten'] }),
  soya: F({ id: 'soya', label: (q) => `${q} g dry soya chunks (curry)`, kcal: 3.45, protein: 0.52, unit: 'g', qty: 50, step: 10, min: 30, max: 80, role: 'protein', tags: ['soy'] }),
  chicken: F({ id: 'chicken', label: (q) => `${q} g chicken breast (cooked)`, kcal: 1.65, protein: 0.31, unit: 'g', qty: 150, step: 25, min: 100, max: 250, role: 'protein', tags: ['meat'] }),
  fish: F({ id: 'fish', label: (q) => `${q} g fish (grilled / curry)`, kcal: 1.2, protein: 0.21, unit: 'g', qty: 150, step: 25, min: 100, max: 250, role: 'protein', tags: ['fish'] }),
  tofu: F({ id: 'tofu', label: (q) => `${q} g tofu (sabzi / tikka)`, kcal: 1.45, protein: 0.15, unit: 'g', qty: 150, step: 25, min: 100, max: 250, role: 'protein', tags: ['soy'] }),
  paneer: F({ id: 'paneer', label: (q) => `${q} g paneer`, kcal: 2.65, protein: 0.18, unit: 'g', qty: 80, step: 10, min: 50, max: 120, role: 'protein', tags: ['paneer', 'lactose', 'dairy'] }),
  dal: F({ id: 'dal', label: (q) => `${q} g cooked thick dal`, kcal: 1.05, protein: 0.07, unit: 'g', qty: 200, step: 50, min: 150, max: 300, role: 'fixed', tags: [] }),
  chana: F({ id: 'chana', label: (q) => `${q} g cooked chana / rajma`, kcal: 1.3, protein: 0.08, unit: 'g', qty: 150, step: 25, min: 100, max: 250, role: 'protein', tags: [] }),
  rice: F({ id: 'rice', label: (q) => `${q} g cooked rice`, kcal: 1.3, protein: 0.027, unit: 'g', qty: 100, step: 25, min: 50, max: 250, role: 'carb', tags: [] }),
  roti: F({ id: 'roti', label: (q) => `${q} medium roti${q > 1 ? 's' : ''}`, kcal: 120, protein: 4, unit: 'pc', qty: 2, step: 1, min: 1, max: 4, role: 'carb', tags: ['gluten'] }),
  jowar: F({ id: 'jowar', label: (q) => `${q} jowar/bajra roti${q > 1 ? 's' : ''}`, kcal: 110, protein: 3.5, unit: 'pc', qty: 2, step: 1, min: 1, max: 4, role: 'carb', tags: [] }),
  sabzi: F({ id: 'sabzi', label: () => '1 bowl non-starchy sabzi (1 tsp oil)', kcal: 90, protein: 3, unit: 'serving', qty: 1, step: 1, min: 1, max: 1, role: 'fixed', tags: [] }),
  salad: F({ id: 'salad', label: () => 'Salad', kcal: 30, protein: 1, unit: 'serving', qty: 1, step: 1, min: 1, max: 1, role: 'fixed', tags: [] }),
  soymilk: F({ id: 'soymilk', label: (q) => `${q} ml unsweetened soy milk`, kcal: 0.33, protein: 0.033, unit: 'ml', qty: 250, step: 50, min: 200, max: 400, role: 'fixed', tags: ['soy'] }),
  milk: F({ id: 'milk', label: (q) => `${q} ml toned milk`, kcal: 0.58, protein: 0.032, unit: 'ml', qty: 250, step: 50, min: 200, max: 400, role: 'fixed', tags: ['lactose', 'dairy'] }),
  curd: F({ id: 'curd', label: (q) => `${q} g hung curd / Greek yogurt`, kcal: 0.97, protein: 0.09, unit: 'g', qty: 150, step: 25, min: 100, max: 250, role: 'protein', tags: ['lactose', 'dairy'] }),
  chanaRoast: F({ id: 'chanaRoast', label: (q) => `${q} g roasted chana`, kcal: 3.6, protein: 0.2, unit: 'g', qty: 30, step: 10, min: 20, max: 60, role: 'fixed', tags: [] }),
  fruit: F({ id: 'fruit', label: () => '1 fruit (guava / apple / orange / papaya)', kcal: 80, protein: 1, unit: 'pc', qty: 1, step: 1, min: 1, max: 2, role: 'fixed', tags: [] }),
  almonds: F({ id: 'almonds', label: (q) => `${q} almonds`, kcal: 7, protein: 0.26, unit: 'pc', qty: 6, step: 2, min: 4, max: 12, role: 'fixed', tags: ['nuts'] }),
  dates: F({ id: 'dates', label: (q) => `${q} dates`, kcal: 23, protein: 0.2, unit: 'pc', qty: 2, step: 1, min: 1, max: 3, role: 'fixed', tags: [] }),
  banana: F({ id: 'banana', label: (q) => `${q} banana${q > 1 ? 's' : ''}`, kcal: 105, protein: 1.3, unit: 'pc', qty: 1, step: 1, min: 1, max: 2, role: 'fixed', tags: [] }),
  pb: F({ id: 'pb', label: (q) => `${q} tbsp peanut butter`, kcal: 95, protein: 4, unit: 'pc', qty: 1, step: 1, min: 1, max: 3, role: 'fixed', tags: ['nuts'] }),
  ghee: F({ id: 'ghee', label: (q) => `${q} tsp ghee on rotis/rice`, kcal: 45, protein: 0, unit: 'tsp', qty: 1, step: 1, min: 1, max: 3, role: 'fixed', tags: ['dairy'] }),
  seeds: F({ id: 'seeds', label: (q) => `${q} tbsp mixed seeds (pumpkin/sunflower)`, kcal: 55, protein: 2.5, unit: 'pc', qty: 1, step: 1, min: 1, max: 3, role: 'fixed', tags: [] }),
  coffee: F({ id: 'coffee', label: () => 'Tea or black coffee', kcal: 10, protein: 0, unit: 'serving', qty: 1, step: 1, min: 1, max: 1, role: 'fixed', tags: [] }),
} satisfies Record<string, Food>;
type FoodId = keyof typeof FOODS;

export interface DietInput {
  sex: Sex;
  age: number;
  heightCm: number;
  weightKg: number;
  goalWeightKg: number;
  goal: Goal;
  trainingDays: number;
  dietType: DietType;
  intolerances: string[];
  kcalOverride?: number;
  proteinOverride?: number;
}

export interface GenMeal {
  time: string;
  meal: string;
  items: string[];
  rotate?: string[];
  proteinG: number;
  kcal: number;
  optional?: boolean;
  skipOnRestDay?: boolean;
}

const GOAL_FACTOR: Record<Goal, number> = { fat_loss: 0.8, lean: 0.88, muscle: 1.1, strength: 1.05, general: 1 };
const PROTEIN_PER_KG: Record<Goal, number> = { fat_loss: 2.0, lean: 2.0, muscle: 1.8, strength: 1.8, general: 1.5 };
export const kcalFloorFor = (sex: Sex) => (sex === 'female' ? 1400 : sex === 'male' ? 1700 : 1500);

export function dietTargets(i: Pick<DietInput, 'sex' | 'age' | 'heightCm' | 'weightKg' | 'goalWeightKg' | 'goal' | 'trainingDays'>): { kcal: number; proteinG: number } {
  const s = i.sex === 'male' ? 5 : i.sex === 'female' ? -161 : -78;
  const bmr = 10 * i.weightKg + 6.25 * i.heightCm - 5 * i.age + s;
  const activity = i.trainingDays <= 2 ? 1.375 : i.trainingDays <= 4 ? 1.55 : 1.65;
  const kcal = Math.max(kcalFloorFor(i.sex), Math.round((bmr * activity * GOAL_FACTOR[i.goal]) / 50) * 50);
  // protein: per kg of goal weight when cutting (≈ lean-mass proxy), current weight otherwise; capped for very heavy users
  const ref = i.goal === 'fat_loss' || i.goal === 'lean' ? Math.min(i.weightKg, Math.max(i.goalWeightKg, i.weightKg * 0.85)) : i.weightKg;
  const proteinG = Math.min(220, Math.round((PROTEIN_PER_KG[i.goal] * ref) / 5) * 5);
  return { kcal, proteinG };
}

function blocked(i: DietInput): Set<Tag> {
  const b = new Set<Tag>();
  if (i.dietType !== 'nonveg') b.add('meat').add('fish');
  if (i.dietType === 'veg' || i.dietType === 'vegan') b.add('egg');
  if (i.dietType === 'vegan') b.add('dairy').add('lactose').add('paneer');
  for (const x of i.intolerances.map((t) => t.toLowerCase())) {
    if (x.includes('lactose')) b.add('lactose');
    if (x.includes('paneer')) b.add('paneer');
    if (x.includes('gluten')) b.add('gluten');
    if (x.includes('nut')) b.add('nuts');
    if (x.includes('soy')) b.add('soy');
    if (x.includes('egg')) b.add('egg');
    if (x.includes('dairy') || x.includes('milk')) b.add('dairy').add('lactose').add('paneer');
  }
  return b;
}

interface Part {
  food: Food;
  q: number;
}

export function generateDiet(i: DietInput): { kcalTarget: number; proteinTargetG: number; meals: GenMeal[] } {
  const t = dietTargets(i);
  const kcalTarget = i.kcalOverride ?? t.kcal;
  const proteinTargetG = i.proteinOverride ?? t.proteinG;
  const no = blocked(i);
  const ok = (id: FoodId) => !FOODS[id].tags.some((x) => no.has(x));
  const first = (...ids: FoodId[]) => ids.find(ok);
  const part = (id: FoodId | undefined, q?: number): Part[] => (id ? [{ food: FOODS[id], q: q ?? FOODS[id].qty }] : []);

  const shake = first('whey', 'pea');
  const shakeOk = shake === 'whey' ? !no.has('dairy') : true;
  const meals: { time: string; meal: string; parts: Part[]; rotate?: string[]; optional?: boolean; skipOnRestDay?: boolean }[] = [
    { time: '08:30', meal: 'Pre-workout', parts: [...part('coffee'), ...part(first('almonds', 'dates'))], skipOnRestDay: true },
    {
      time: '10:30',
      meal: 'Breakfast',
      parts: [
        ...(shakeOk ? part(shake) : []),
        ...(ok('eggs') ? [...part('eggs'), ...part('whites')] : part(first('tofuB', 'besan'))),
        ...part(first('oats', 'poha')),
      ],
    },
    {
      time: '13:00',
      meal: 'Lunch',
      parts: [...part(first('chicken', 'fish', 'soya', 'tofu', 'chana')), ...part('dal'), ...part('rice'), ...part('sabzi'), ...part('salad')],
    },
    {
      time: '16:00',
      meal: 'Snack',
      parts: part(first('soymilk', 'milk') ?? 'chanaRoast'),
      rotate: [!no.has('soy') ? '100 g edamame' : undefined, '30 g roasted chana', '1 cup sprouts chaat', !no.has('lactose') ? '150 g Greek yogurt' : undefined].filter(Boolean) as string[],
    },
    { time: '18:30', meal: 'Evening', parts: [...part('fruit'), ...(ok('curd') ? part('curd') : part('chanaRoast'))] },
    {
      time: '20:30',
      meal: 'Dinner',
      parts: [
        ...(i.dietType === 'nonveg' ? part(first('fish', 'chicken')) : ok('eggs') ? [...part('eggs'), ...part('whites', 3)] : part(first('paneer', 'tofu', 'chana'))),
        ...part(first('roti', 'jowar')),
        ...part('sabzi'),
      ],
    },
  ];

  const sum = (fn: (p: Part) => number) => meals.reduce((a, m) => a + m.parts.reduce((b, p) => b + fn(p), 0), 0);
  const P = () => sum((p) => p.food.protein * p.q);
  const K = () => sum((p) => p.food.kcal * p.q);
  const round = (p: Part, v: number) => Math.min(p.food.max, Math.max(p.food.min, Math.round(v / p.food.step) * p.food.step));
  const scaleRole = (role: Food['role'], factor: number) => meals.forEach((m) => m.parts.forEach((p) => p.food.role === role && (p.q = round(p, p.q * factor))));

  // 1) scale protein foods toward the protein target, 2) scale carbs toward the calorie target; iterate a few times
  for (let k = 0; k < 6; k++) {
    const pf = sum((p) => (p.food.role === 'protein' ? p.food.protein * p.q : 0));
    const need = proteinTargetG - (P() - pf);
    if (pf > 0) scaleRole('protein', Math.max(0.5, Math.min(2, need / pf)));
    const cf = sum((p) => (p.food.role === 'carb' ? p.food.kcal * p.q : 0));
    const kNeed = kcalTarget - (K() - cf);
    if (cf > 0) scaleRole('carb', Math.max(0.3, Math.min(2.5, kNeed / cf)));
  }

  // High targets (e.g. muscle gain): carbs hit their portion caps, so add energy boosters until within ~5%
  const boosters: [FoodId, number][] = [['banana', 0], ['pb', 0], ['banana', 0], ['seeds', 0], ['pb', 0], ['ghee', 5], ['seeds', 0], ['pb', 0], ['ghee', 5], ['ghee', 5]];
  for (const [id, mealIdx] of boosters) {
    if (K() >= kcalTarget * 0.95) break;
    if (!ok(id)) continue;
    const m = meals[mealIdx || 3];
    const existing = m.parts.find((p) => p.food.id === id);
    if (existing) {
      if (existing.q < existing.food.max) existing.q += existing.food.step;
    } else m.parts.push({ food: FOODS[id], q: FOODS[id].qty });
  }

  const out: GenMeal[] = meals
    .filter((m) => m.parts.length)
    .map((m) => ({
      time: m.time,
      meal: m.meal,
      items: m.parts.filter((p) => p.q > 0).map((p) => p.food.label(p.q)),
      rotate: m.rotate?.length ? m.rotate : undefined,
      proteinG: Math.round(m.parts.reduce((a, p) => a + p.food.protein * p.q, 0)),
      kcal: Math.round(m.parts.reduce((a, p) => a + p.food.kcal * p.q, 0) / 5) * 5,
      skipOnRestDay: m.skipOnRestDay,
    }));
  // optional protein top-up
  if (shake && shakeOk) out.push({ time: '22:00', meal: 'Only if needed', items: [`½ scoop ${shake === 'whey' ? 'whey' : 'plant protein'} in water, only if protein is short`], proteinG: 12, kcal: 60, optional: true });
  return { kcalTarget, proteinTargetG, meals: out };
}
