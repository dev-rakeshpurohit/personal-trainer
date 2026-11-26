/**
 * AI coach contract, shared by the app and the /api/coach function.
 * Keep this file free of '@/…' imports and browser APIs: the serverless function bundles it.
 *
 * The model only ever chooses exercises by id from a list the app sends (already filtered to the
 * user's equipment); `normaliseAiPlan` drops anything else, clamps numbers and fills the week.
 */
import { z } from 'zod';

export const WEEK = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'] as const;
export type Wd = (typeof WEEK)[number];

/* ---------- request (app → function) ---------- */

export const coachProfileSchema = z.object({
  sex: z.enum(['male', 'female', 'other']),
  age: z.number().int().min(13).max(100),
  heightCm: z.number().min(120).max(230),
  weightKg: z.number().min(30).max(300),
  goalWeightKg: z.number().min(30).max(300),
  goal: z.enum(['fat_loss', 'lean', 'muscle', 'strength', 'general']),
  experience: z.enum(['beginner', 'intermediate', 'advanced']),
  trainingDays: z.array(z.enum(WEEK)).max(7),
  sessionMin: z.number().int().min(20).max(120),
  sessionTime: z.string().max(10).optional(),
  equipment: z.array(z.string().max(30)).max(20),
  dietType: z.enum(['veg', 'veg_egg', 'nonveg', 'vegan']),
  intolerances: z.array(z.string().max(40)).max(12),
  kcalTarget: z.number().int().min(1000).max(5000).optional(),
  proteinTargetG: z.number().int().min(40).max(350).optional(),
});
export type CoachProfile = z.infer<typeof coachProfileSchema>;

export const coachExerciseSchema = z.object({ id: z.string().max(80), name: z.string().max(90), pattern: z.string().max(30).optional(), unit: z.string().max(8) });

export const coachRequestSchema = z.object({
  code: z.string().max(20),
  mode: z.enum(['new', 'change']),
  want: z.object({ workout: z.boolean(), diet: z.boolean() }),
  profile: coachProfileSchema,
  notes: z.string().max(2000),
  exercises: z.array(coachExerciseSchema).max(1500),
  /** Compact text of the current plan, for "change my plan". */
  current: z.string().max(12000).optional(),
});
export type CoachRequest = z.infer<typeof coachRequestSchema>;

/* ---------- response (model → app) ---------- */

const num = (min: number, max: number) => z.coerce.number().min(min).max(max).catch(min);

export const aiExerciseSchema = z.object({
  id: z.string(),
  sets: num(1, 8),
  repsMin: num(1, 120),
  repsMax: num(1, 120),
  unit: z.enum(['reps', 'seconds', 'minutes', 'meters']).catch('reps'),
  restSec: num(0, 300),
  perSide: z.boolean().optional().catch(undefined),
  superset: z.string().max(2).optional().catch(undefined),
  cue: z.string().max(140).optional().catch(undefined),
});
export const aiDaySchema = z.object({
  weekday: z.enum(WEEK),
  type: z.enum(['strength', 'cardio', 'conditioning', 'rest', 'active_recovery']).catch('strength'),
  title: z.string().max(60).catch('Session'),
  durationMin: num(10, 150).optional(),
  notes: z.string().max(200).optional().catch(undefined),
  exercises: z.array(aiExerciseSchema).max(14).catch([]),
});
export const aiMealSchema = z.object({
  time: z.string().regex(/^\d{1,2}:\d{2}$/).catch('12:00'),
  meal: z.string().max(40),
  items: z.array(z.string().max(120)).min(1).max(8),
  rotate: z.array(z.string().max(160)).max(4).optional().catch(undefined),
  kcal: num(0, 2000),
  proteinG: num(0, 150),
  optional: z.boolean().optional().catch(undefined),
});
export const aiPlanSchema = z.object({
  summary: z.string().max(900).catch(''),
  workout: z.object({ name: z.string().max(60).catch('AI coach plan'), days: z.array(aiDaySchema).max(7) }).optional(),
  diet: z
    .object({
      kcalTarget: num(1000, 5000),
      proteinTargetG: num(40, 350),
      meals: z.array(aiMealSchema).min(2).max(8),
      tips: z.array(z.string().max(200)).max(6).optional().catch(undefined),
    })
    .optional(),
});
export type AiPlan = z.infer<typeof aiPlanSchema>;

export interface CoachResponse {
  plan: unknown;
  model: string;
  costUsd?: number;
}

/* ---------- prompt ---------- */

const GOAL_TEXT: Record<CoachProfile['goal'], string> = {
  fat_loss: 'lose fat while keeping muscle',
  lean: 'get leaner, stronger and more athletic',
  muscle: 'build muscle (small calorie surplus)',
  strength: 'get stronger on the main lifts',
  general: 'general fitness and feeling good',
};
const DIET_TEXT: Record<CoachProfile['dietType'], string> = {
  veg: 'vegetarian (no eggs, no meat, no fish)',
  veg_egg: 'vegetarian plus eggs',
  nonveg: 'eats meat, fish and eggs',
  vegan: 'vegan',
};

export function buildPrompt(r: CoachRequest): { system: string; user: string } {
  const p = r.profile;
  const system = [
    'You are an experienced strength & conditioning coach and sports nutritionist building a plan for a gym app.',
    'Reply with ONE JSON object only, no prose, no markdown fences. Schema:',
    '{"summary": string (2-4 friendly sentences: what you built and why),',
    ' "workout"?: {"name": string, "days": [{"weekday": "MON".."SUN", "type": "strength"|"cardio"|"conditioning"|"rest"|"active_recovery", "title": string, "durationMin": number, "notes"?: string,',
    '   "exercises": [{"id": string (MUST be an id from the EXERCISES list), "sets": int, "repsMin": int, "repsMax": int, "unit": "reps"|"seconds"|"minutes"|"meters", "restSec": int, "perSide"?: bool, "superset"?: "A"|"B"|"C", "cue"?: string (one short coaching cue)}]}]},',
    ' "diet"?: {"kcalTarget": int, "proteinTargetG": int, "meals": [{"time": "HH:MM", "meal": string, "items": [string with quantity], "rotate"?: [string alternatives], "kcal": int, "proteinG": int, "optional"?: bool}], "tips"?: [string]}}',
    'Rules:',
    '- Use ONLY exercise ids from EXERCISES (they already match the gym equipment). Never invent ids.',
    '- Include all 7 weekdays in workout.days; non-training days are "rest" or "active_recovery" with no exercises.',
    '- Train only on the given training days. Respect session length: roughly 5-8 exercises for 60-75 min incl. warm-up, fewer for shorter sessions.',
    '- Balance the week: squat, hinge, single-leg, horizontal & vertical push and pull, core; add calves/arms/isolation only if time allows.',
    '- Beginners: 2-3 sets, moderate reps, conservative intervals. Use supersets (same letter) for accessories to save time.',
    '- Use unit "minutes" for steady cardio, "seconds" for holds/intervals.',
    '- Do NOT add warm-up, mobility-flow or cool-down items to training days: the app adds its own warm-up. A short cardio finisher is fine when it serves the goal.',
    '- Honour every injury, dislike, preference and schedule detail in the notes. Safety first: when in doubt choose the joint-friendlier option.',
    '- Diet: meals must fit the diet type and intolerances, use realistic everyday foods (Indian home food is a good default unless the notes say otherwise), give quantities, and make meal kcal/protein sum to within 5% of the targets.',
  ].join('\n');
  const lines = [
    `MODE: ${r.mode === 'new' ? 'Build a new plan.' : 'Change the CURRENT plan as the notes ask; keep everything else the same.'}`,
    `BUILD: ${[r.want.workout && 'workout', r.want.diet && 'diet'].filter(Boolean).join(' + ')}`,
    `PERSON: ${p.sex}, ${p.age} y, ${p.heightCm} cm, ${p.weightKg} kg → goal weight ${p.goalWeightKg} kg. Goal: ${GOAL_TEXT[p.goal]}. Experience: ${p.experience}.`,
    `SCHEDULE: trains ${p.trainingDays.join(', ') || 'no fixed days'}; ${p.sessionMin} min per session${p.sessionTime ? ` at ${p.sessionTime}` : ''}.`,
    `EQUIPMENT: ${p.equipment.join(', ') || 'bodyweight only'}.`,
    `FOOD: ${DIET_TEXT[p.dietType]}${p.intolerances.length ? `; avoid ${p.intolerances.join(', ')}` : ''}.${p.kcalTarget ? ` Current targets ${p.kcalTarget} kcal, ${p.proteinTargetG} g protein (adjust only if clearly wrong for the goal).` : ''}`,
    `NOTES FROM THE PERSON: ${r.notes.trim() || '(none)'}`,
  ];
  if (r.current) lines.push('CURRENT PLAN:', r.current);
  if (r.want.workout) lines.push('EXERCISES (id | name | pattern | unit):', ...r.exercises.map((e) => `${e.id} | ${e.name} | ${e.pattern ?? '-'} | ${e.unit}`));
  return { system, user: lines.join('\n') };
}

/** Pull the JSON object out of a model reply (tolerates code fences and stray text). */
export function extractJson(text: string): unknown {
  const t = text.replace(/```(?:json)?/gi, '').trim();
  const a = t.indexOf('{');
  const b = t.lastIndexOf('}');
  if (a < 0 || b <= a) throw new Error('The coach did not return a plan. Please try again.');
  return JSON.parse(t.slice(a, b + 1));
}

/* ---------- normalise (app side) ---------- */

export interface NormDay {
  weekday: Wd;
  type: 'strength' | 'cardio' | 'conditioning' | 'rest' | 'active_recovery';
  title: string;
  durationMin?: number;
  notes?: string;
  exercises: {
    slot: string;
    exerciseId: string;
    supersetGroup?: string;
    sets: number;
    repsMin: number;
    repsMax: number;
    unit: 'reps' | 'seconds' | 'minutes' | 'meters';
    perSide: boolean;
    restSec: number;
    cue?: string;
  }[];
}

export interface NormPlan {
  summary: string;
  workout?: { name: string; days: NormDay[] };
  diet?: AiPlan['diet'];
  warnings: string[];
}

/**
 * Validate and repair a model reply. `allowed` = exercise ids the person can do (equipment-filtered).
 * Unknown ids are dropped with a warning; empty training days become rest.
 */
export function normaliseAiPlan(raw: unknown, allowed: Map<string, { name: string }>): NormPlan {
  const parsed = aiPlanSchema.safeParse(raw);
  if (!parsed.success) throw new Error('The coach replied in an unexpected format. Please try again.');
  const plan = parsed.data;
  const warnings: string[] = [];
  let workout: NormPlan['workout'];
  if (plan.workout) {
    const byDay = new Map<Wd, NormDay>();
    for (const d of plan.workout.days) {
      if (byDay.has(d.weekday)) continue;
      const seen = new Set<string>();
      const exercises: NormDay['exercises'] = [];
      for (const e of d.exercises) {
        if (!allowed.has(e.id)) {
          warnings.push(`Skipped an exercise the coach suggested that isn't in your gym's list (${e.id}).`);
          continue;
        }
        if (seen.has(e.id)) continue;
        seen.add(e.id);
        const lo = Math.round(Math.min(e.repsMin, e.repsMax));
        const hi = Math.round(Math.max(e.repsMin, e.repsMax));
        exercises.push({
          slot: '',
          exerciseId: e.id,
          supersetGroup: e.superset?.toUpperCase() || undefined,
          sets: Math.round(e.sets),
          repsMin: lo,
          repsMax: hi,
          unit: e.unit,
          perSide: !!e.perSide,
          restSec: Math.round(e.restSec / 5) * 5,
          cue: e.cue,
        });
      }
      // superset letters need two partners
      for (const x of exercises) if (x.supersetGroup && exercises.filter((y) => y.supersetGroup === x.supersetGroup).length < 2) x.supersetGroup = undefined;
      // slots: A1/A2 for supersets, otherwise letters in order
      let letter = 0;
      const groupLetter = new Map<string, string>();
      const groupCount = new Map<string, number>();
      for (const x of exercises) {
        if (x.supersetGroup) {
          if (!groupLetter.has(x.supersetGroup)) groupLetter.set(x.supersetGroup, String.fromCharCode(65 + letter++));
          const L = groupLetter.get(x.supersetGroup)!;
          const n = (groupCount.get(L) ?? 0) + 1;
          groupCount.set(L, n);
          x.slot = `${L}${n}`;
          x.supersetGroup = L;
        } else x.slot = String.fromCharCode(65 + letter++);
      }
      const training = d.type === 'strength' || d.type === 'cardio' || d.type === 'conditioning';
      byDay.set(d.weekday, {
        weekday: d.weekday,
        type: training && !exercises.length ? 'rest' : d.type,
        title: training && !exercises.length ? 'Rest' : d.title,
        durationMin: d.durationMin ? Math.round(d.durationMin) : undefined,
        notes: d.notes,
        exercises: training ? exercises : [],
      });
    }
    const days = WEEK.map((w) => byDay.get(w) ?? { weekday: w, type: 'rest' as const, title: 'Rest', exercises: [] });
    if (!days.some((d) => d.exercises.length)) throw new Error('The coach returned a plan without exercises. Please try again.');
    workout = { name: plan.workout.name, days };
  }
  let diet = plan.diet;
  if (diet) {
    const kcal = diet.meals.reduce((s, m) => s + m.kcal, 0);
    const protein = diet.meals.reduce((s, m) => s + m.proteinG, 0);
    if (Math.abs(kcal - diet.kcalTarget) > diet.kcalTarget * 0.1) warnings.push(`Meals add up to ${Math.round(kcal)} kcal vs the ${diet.kcalTarget} kcal target.`);
    if (protein < diet.proteinTargetG * 0.85) warnings.push(`Meals give ${Math.round(protein)} g protein vs the ${diet.proteinTargetG} g target.`);
    diet = { ...diet, meals: [...diet.meals].sort((a, b) => a.time.padStart(5, '0').localeCompare(b.time.padStart(5, '0'))) };
  }
  if (!workout && !diet) throw new Error('The coach returned an empty plan. Please try again.');
  return { summary: plan.summary, workout, diet, warnings: [...new Set(warnings)].slice(0, 6) };
}
