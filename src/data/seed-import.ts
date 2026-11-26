import programJson from '../../seed/program.lean-athletic-v2.json';
import dietJson from '../../seed/diet.lean-veg-egg-2000.json';
import mediaIndexJson from '../../public/media/exercises/index.json';
import researchJson from '../../seed/alternates.research.json';
import demoMapJson from '../../seed/demo-map.json';
import curatedMetaJson from '../../seed/library.curated-meta.json';
import { slugify } from '@/lib/slug';
import { db, setMeta, uid } from './db';
import { mediaIndexSchema, researchSchema, seedDietSchema, seedProgramSchema, type MediaIndex, type Research, type SeedDiet, type SeedProgram } from './schemas';
import { dayKey, weekStartOf } from '@/domain/schedule';
import type { Category, DayType, Exercise, HabitDef, PlannedExercise, PlannedMeal, Program, ProgramDay, Unit, Weekday } from '@/domain/types';
import { WEEKDAYS, isTrainingType } from '@/domain/types';

export { slugify } from '@/lib/slug';

export const parseSeedProgram = (): SeedProgram => seedProgramSchema.parse(programJson);
export const parseSeedDiet = (): SeedDiet => seedDietSchema.parse(dietJson);
export const parseMediaIndex = (): MediaIndex => mediaIndexSchema.parse(mediaIndexJson);
export const parseResearch = (): Research => researchSchema.parse(researchJson);

/** Seed swaps that have no free-exercise-db id get the closest available demo (doc 09 notes). */
const NULL_SWAP_IMAGES: Record<string, string> = {
  'Outdoor brisk walk later in the day': 'Trail_Running_Walking',
  'Weighted plate crunch': 'Weighted_Crunches',
  'Band face pull': 'Band_Pull_Apart',
  'Dumbbell swing': 'Vertical_Swing',
  "Farmer's march in place, 40 s": 'Farmers_Walk',
};

const BODYWEIGHT_EQUIP = new Set(['body only', 'bands', 'none', 'foam roll', 'exercise ball']);

function category(dbCat: string | undefined, muscles: string[], unit: Unit): Category {
  if (unit === 'minutes' || dbCat === 'cardio') return 'cardio';
  if (dbCat === 'stretching') return 'mobility';
  if (dbCat === 'plyometrics' || dbCat === 'olympic weightlifting') return 'power';
  if (muscles.includes('abdominals')) return 'core';
  return 'strength';
}

/** Build library entries for every exercise/swap/warm-up item in the seed (upsert by slug). */
export function buildExercises(program: SeedProgram, media: MediaIndex, research?: Research): Map<string, Exercise> {
  const byDb = new Map(media.map((m) => [m.id, m]));
  const out = new Map<string, Exercise>();
  const add = (name: string, rawId: string | null | undefined, unit: Unit, extra: { cue?: string; youtubeQuery?: string; level?: number; pattern?: string; equipment?: string }) => {
    const id = slugify(name);
    const freeDbId = rawId ?? NULL_SWAP_IMAGES[name];
    const m = freeDbId ? byDb.get(freeDbId) : undefined;
    const equipment = m?.equipment?.length ? m.equipment : extra.equipment ? [extra.equipment === 'bodyweight' ? 'body only' : extra.equipment] : [];
    const cat = category(m?.category, m?.primaryMuscles ?? [], unit);
    const prev = out.get(id);
    const ex: Exercise = {
      id,
      name,
      freeDbId: freeDbId ?? undefined,
      primaryMuscles: m?.primaryMuscles ?? [],
      equipment,
      category: cat,
      cue: prev?.cue ?? extra.cue,
      instructions: m?.instructions,
      youtubeQuery: prev?.youtubeQuery ?? extra.youtubeQuery,
      custom: false,
      isBodyweight: cat === 'cardio' || cat === 'mobility' || !m || equipment.every((e) => BODYWEIGHT_EQUIP.has(e)),
      defaultUnit: prev?.defaultUnit ?? unit,
      level: prev?.level ?? extra.level,
      pattern: prev?.pattern ?? extra.pattern,
      alternates: prev?.alternates,
    };
    out.set(id, prev ? { ...ex, cue: prev.cue ?? ex.cue } : ex);
    return id;
  };
  const addAlternates = (name: string) => {
    const alts = research?.alternates[name];
    if (!alts) return;
    const pattern = research?.patterns[name];
    const ids = alts.map((a) => add(a.name, a.freeDbId, a.unit, { level: a.level, pattern, equipment: a.equipment }));
    const parent = out.get(slugify(name))!;
    out.set(parent.id, { ...parent, pattern: parent.pattern ?? pattern, alternates: ids.filter((x) => x !== parent.id) });
  };
  for (const w of program.warmup.items) if (w.freeDbId !== undefined) add(w.name, w.freeDbId, 'reps', { youtubeQuery: w.youtubeQuery });
  for (const d of program.days)
    for (const e of d.exercises ?? []) {
      add(e.name, e.freeDbId, e.target.unit, { cue: e.cue, youtubeQuery: e.youtubeQuery });
      if (e.swap) add(e.swap.name, e.swap.freeDbId, e.target.unit, { youtubeQuery: e.swap.youtubeQuery });
    }
  for (const d of program.days)
    for (const e of d.exercises ?? []) {
      addAlternates(e.name);
      if (e.swap) addAlternates(e.swap.name);
    }
  // Curated exercises that share a 3D demo get its helper muscles and matching instructions.
  const demoMap = demoMapJson.map as Record<string, string | null>;
  const meta = curatedMetaJson.meta as Record<string, { secondaryMuscles?: string[]; bodyPart: string; instructions: string[] }>;
  for (const [id, ex] of out) {
    const demoId = demoMap[id] ?? undefined;
    const m = demoId ? meta[demoId] : undefined;
    out.set(id, {
      ...ex,
      source: 'curated',
      demoId,
      secondaryMuscles: m?.secondaryMuscles?.filter((x) => !ex.primaryMuscles.includes(x)),
      bodyPart: m?.bodyPart,
      instructions: m?.instructions.length ? m.instructions : ex.instructions,
    });
  }
  return out;
}

/**
 * Remap template training days onto the user's chosen weekdays (in order).
 * Unchosen weekdays become rest, except the template's active-recovery day which is kept.
 */
export function remapDays<T extends { weekday: Weekday; type: DayType; title: string }>(days: T[], chosen?: Weekday[]): T[] {
  if (!chosen?.length) return days;
  const order = (w: Weekday) => WEEKDAYS.indexOf(w);
  const training = days.filter((d) => isTrainingType(d.type)).sort((a, b) => order(a.weekday) - order(b.weekday));
  const picks = [...chosen].sort((a, b) => order(a) - order(b));
  const same = training.length === picks.length && training.every((t, i) => t.weekday === picks[i]);
  if (same) return days;
  const result: T[] = [];
  training.slice(0, picks.length).forEach((t, i) => result.push({ ...t, weekday: picks[i] }));
  for (const w of WEEKDAYS) {
    if (result.some((r) => r.weekday === w)) continue;
    const orig = days.find((d) => d.weekday === w && !isTrainingType(d.type));
    if (orig?.type === 'active_recovery') result.push(orig);
    else result.push({ ...(orig ?? (days.find((d) => d.type === 'rest') as T)), weekday: w, type: 'rest', title: 'Rest' } as T);
  }
  return result.sort((a, b) => order(a.weekday) - order(b.weekday));
}

export interface ImportResult {
  programId: string;
  days: number;
  daysWithExercises: number;
  exercises: number;
  mediaIds: number;
}

export async function importProgramTemplate(opts: { trainingDays?: Weekday[]; today?: Date } = {}): Promise<ImportResult> {
  const program = parseSeedProgram();
  const media = parseMediaIndex();
  const research = parseResearch();
  const exercises = buildExercises(program, media, research);
  const today = opts.today ?? new Date();
  const programId = uid();
  const p: Program = {
    id: programId,
    name: program.name,
    active: true,
    startedOn: dayKey(weekStartOf(today, 'mon')),
    warmup: program.warmup.items.map((w) => ({
      name: w.name,
      minutes: w.minutes,
      reps: w.reps,
      exerciseId: w.freeDbId !== undefined ? slugify(w.name) : undefined,
    })),
    cooldown: program.cooldown,
    rules: program.rules,
    progression: {
      ...program.progression,
      weeks: research.periodization.weeks.map((w) => ({ ...w, setsDelta: w.setsDelta ?? 0 })),
    },
    templateId: program.id,
  };
  const mapped = remapDays(program.days, opts.trainingDays);
  const days: ProgramDay[] = [];
  const planned: PlannedExercise[] = [];
  mapped.forEach((d, i) => {
    const dayId = uid();
    days.push({ id: dayId, programId, weekday: d.weekday, type: d.type, title: d.title, durationMin: d.durationMin, notes: d.notes, order: i });
    (d.exercises ?? []).forEach((e, j) =>
      planned.push({
        id: uid(),
        dayId,
        order: j,
        slot: e.slot,
        exerciseId: slugify(e.name),
        swapExerciseId: e.swap ? slugify(e.swap.name) : undefined,
        supersetGroup: e.supersetGroup,
        sets: e.target.sets,
        repsMin: e.target.repsMin,
        repsMax: e.target.repsMax,
        unit: e.target.unit,
        perSide: e.target.perSide,
        restSec: e.restSec,
        cue: e.cue,
      }),
    );
  });
  await db.transaction('rw', [db.programs, db.programDays, db.plannedExercises, db.exercises], async () => {
    await db.programs.toCollection().modify({ active: false });
    await db.exercises.bulkPut([...exercises.values()]);
    await db.programs.add(p);
    await db.programDays.bulkAdd(days);
    await db.plannedExercises.bulkAdd(planned);
  });
  return {
    programId,
    days: days.length,
    daysWithExercises: new Set(planned.map((x) => x.dayId)).size,
    exercises: exercises.size,
    mediaIds: media.length,
  };
}

export async function importDietTemplate(): Promise<{ dietPlanId: string; meals: number; habits: number }> {
  const diet = parseSeedDiet();
  const dietPlanId = uid();
  const meals: PlannedMeal[] = diet.trainingDay.map((m, i) => ({
    id: uid(),
    dietPlanId,
    order: i,
    time: m.time,
    meal: m.meal,
    items: m.items,
    rotate: m.rotate,
    proteinG: m.proteinG,
    kcal: m.kcal,
    optional: m.optional,
    skipOnRestDay: m.skipOnRestDay,
  }));
  const habits: HabitDef[] = diet.habits.map((h, i) =>
    h.unit === 'L'
      ? { id: h.id, label: h.label, kind: 'number', target: Math.round((h.target ?? 3) * 1000), unit: 'ml', order: i }
      : { id: h.id, label: h.label, kind: h.target != null ? 'number' : 'check', target: h.target, unit: h.unit, order: i },
  );
  await db.transaction('rw', [db.dietPlans, db.plannedMeals, db.habitDefs, db.meta], async () => {
    await db.dietPlans.toCollection().modify({ active: false });
    await db.dietPlans.add({ id: dietPlanId, name: diet.name, active: true, kcalTarget: diet.kcalTarget, proteinTargetG: diet.proteinTargetG });
    await db.plannedMeals.bulkAdd(meals);
    await db.habitDefs.bulkPut(habits);
    await setMeta('adjustmentRules', diet.adjustmentRules ?? []);
    await setMeta('annualChecks', diet.annualChecks ?? []);
    await setMeta('dietConstraints', diet.constraints ?? []);
  });
  return { dietPlanId, meals: meals.length, habits: habits.length };
}

export const DEFAULT_HABITS: HabitDef[] = [
  { id: 'water', label: 'Water', kind: 'number', target: 3000, unit: 'ml', order: 0 },
  { id: 'steps', label: 'Steps', kind: 'number', target: 8000, unit: 'steps', order: 1 },
  { id: 'sleep', label: 'Sleep', kind: 'number', target: 7, unit: 'h', order: 2 },
];

/** Blank program for "Start blank": one empty workout per chosen day, rest otherwise. */
export async function createBlankProgram(trainingDays: Weekday[], kcal: number, protein: number, today = new Date()) {
  const programId = uid();
  const prog = parseSeedProgram();
  await db.transaction('rw', [db.programs, db.programDays, db.dietPlans, db.habitDefs], async () => {
    await db.programs.add({
      id: programId,
      name: 'My plan',
      active: true,
      startedOn: dayKey(weekStartOf(today, 'mon')),
      warmup: [],
      cooldown: '5 min walk + stretch',
      rules: [],
      progression: prog.progression,
    });
    await db.programDays.bulkAdd(
      WEEKDAYS.map((w, i) => ({
        id: uid(),
        programId,
        weekday: w,
        type: trainingDays.includes(w) ? ('strength' as const) : ('rest' as const),
        title: trainingDays.includes(w) ? 'Workout' : 'Rest',
        order: i,
      })),
    );
    await db.dietPlans.add({ id: uid(), name: 'My diet', active: true, kcalTarget: kcal, proteinTargetG: protein });
    await db.habitDefs.bulkPut(DEFAULT_HABITS);
  });
}
