/** Writes generated plans to the DB, adapts plans to equipment, and applies setup changes (history is never touched). */
import { db, getMeta, setMeta, uid } from './db';
import datasetJson from '../../seed/library.dataset.json';
import { buildExercises, DEFAULT_HABITS, importDietTemplate, importProgramTemplate, parseMediaIndex, parseResearch, parseSeedProgram } from './seed-import';
import { adaptToEquipment, bestReplacement, PRESETS } from '@/domain/equipment';
import type { NormDay, NormPlan } from '@/domain/aiPlan';
import { generateDiet } from '@/domain/dietGen';
import { generateProgram, type GenDay } from '@/domain/generator';
import { dayKey, weekStartOf } from '@/domain/schedule';
import type { Exercise, PlannedExercise, Profile } from '@/domain/types';

export const equipmentOf = (p: Pick<Profile, 'equipment'>): string[] => p.equipment ?? PRESETS.full_gym;

/** Bump when the bundled library changes so existing installs pick up new exercises and metadata. */
export const LIBRARY_VERSION = 2;

/** Curated plan exercises (seed + research alternates), enriched with 3D demo metadata. */
let cachedCurated: Exercise[] | undefined;
export function curatedLibrary(): Exercise[] {
  cachedCurated ??= [...buildExercises(parseSeedProgram(), parseMediaIndex(), parseResearch()).values()];
  return cachedCurated;
}

/** Full static library: curated + ~1,100 exercises from the 3D dataset. Pure, used for previews before anything is saved. */
let cachedLibrary: Exercise[] | undefined;
export function staticLibrary(): Exercise[] {
  cachedLibrary ??= [...curatedLibrary(), ...(datasetJson.exercises as Exercise[])];
  return cachedLibrary;
}

/** Library metadata we own and may refresh on existing rows (never the user's own settings like Track weight). */
const REFRESH_FIELDS = ['demoId', 'secondaryMuscles', 'bodyPart', 'source', 'instructions', 'pattern', 'level', 'primaryMuscles'] as const;

/**
 * Make sure every library exercise exists and carries current metadata.
 * Keeps custom exercises and user-edited fields (cue, Track weight, alternates) untouched.
 */
export async function ensureLibrary(): Promise<{ added: number; updated: number }> {
  const lib = staticLibrary();
  const existing = new Map((await db.exercises.toArray()).map((e) => [e.id, e]));
  const missing = lib.filter((e) => !existing.has(e.id));
  const updates: Exercise[] = [];
  for (const e of lib) {
    const cur = existing.get(e.id);
    if (!cur || cur.custom) continue;
    const next = { ...cur };
    let changed = false;
    for (const k of REFRESH_FIELDS) {
      const v = e[k];
      if (v !== undefined && JSON.stringify(cur[k]) !== JSON.stringify(v)) {
        (next as Record<string, unknown>)[k] = v;
        changed = true;
      }
    }
    if (changed) updates.push(next);
  }
  await db.transaction('rw', [db.exercises, db.meta], async () => {
    if (missing.length) await db.exercises.bulkAdd(missing);
    if (updates.length) await db.exercises.bulkPut(updates);
    await setMeta('libraryVersion', LIBRARY_VERSION);
  });
  return { added: missing.length, updated: updates.length };
}

/** Run once per library version on existing installs (called lazily from the app shell). */
export async function upgradeLibraryIfNeeded(): Promise<boolean> {
  if (((await getMeta<number>('libraryVersion')) ?? 0) >= LIBRARY_VERSION) return false;
  if (!(await db.profile.get('me'))) return false;
  await ensureLibrary();
  return true;
}

export function previewProgram(p: Pick<Profile, 'goal' | 'experience' | 'trainingDays' | 'sessionMin' | 'equipment'>) {
  return generateProgram({
    goal: p.goal ?? 'lean',
    experience: p.experience ?? 'beginner',
    days: p.trainingDays,
    sessionMin: p.sessionMin ?? 60,
    equipment: equipmentOf(p),
    library: staticLibrary(),
  });
}

export async function saveGeneratedProgram(p: Profile, today = new Date()): Promise<string> {
  await ensureLibrary();
  const gen = previewProgram(p);
  return saveProgramDays(p, gen.name, gen.days, `generated:${p.goal ?? 'lean'}`, today);
}

/** Write a full week (generated or AI) as the new active program. History is never touched. */
export async function saveProgramDays(p: Profile, name: string, genDays: GenDay[], templateId: string, today = new Date()): Promise<string> {
  const seed = parseSeedProgram();
  const research = parseResearch();
  const eq = equipmentOf(p);
  const programId = uid();
  const days = genDays.map((d, i) => ({ id: uid(), programId, weekday: d.weekday, type: d.type, title: d.title, durationMin: d.durationMin, notes: d.notes, order: i }));
  const planned: PlannedExercise[] = genDays.flatMap((d, i) => d.exercises.map((e, j) => ({ id: uid(), dayId: days[i].id, order: j, ...e })));
  await db.transaction('rw', [db.programs, db.programDays, db.plannedExercises], async () => {
    await db.programs.toCollection().modify({ active: false });
    await db.programs.add({
      id: programId,
      name,
      active: true,
      startedOn: dayKey(weekStartOf(today, 'mon')),
      warmup: [
        { name: 'Easy cardio or brisk walk', minutes: 5 },
        { name: "World's greatest stretch", reps: '4 / side', exerciseId: 'worlds-greatest-stretch' },
        { name: 'Glute bridge', reps: '10', exerciseId: 'glute-bridge' },
        ...(eq.includes('bands') ? [{ name: 'Band pull-apart', reps: '15', exerciseId: 'band-pull-apart' }] : []),
        { name: '2 light sets of the first exercise', reps: '–' },
      ],
      cooldown: '5 min walk + stretch hips, hamstrings, chest, calves',
      rules: seed.rules.filter((r) => eq.includes('bands') || !/band/i.test(r)),
      progression: { ...seed.progression, weeks: research.periodization.weeks.map((w) => ({ ...w, setsDelta: w.setsDelta ?? 0 })) },
      templateId,
    });
    await db.programDays.bulkAdd(days);
    await db.plannedExercises.bulkAdd(planned);
  });
  return programId;
}

/** Save an AI coach workout: adds a gym-safe swap for each exercise from its alternates or same-pattern lifts. */
export async function saveAiWorkout(p: Profile, w: { name: string; days: NormDay[] }): Promise<string> {
  await ensureLibrary();
  const eq = equipmentOf(p);
  const lib = await db.exercises.toArray();
  const byId = new Map(lib.map((e) => [e.id, e]));
  const days: GenDay[] = w.days.map((d) => {
    const used = d.exercises.map((e) => e.exerciseId);
    return {
      weekday: d.weekday,
      type: d.type,
      title: d.title,
      durationMin: d.durationMin ?? p.sessionMin,
      notes: d.notes,
      exercises: d.exercises.map((e) => {
        const ex = byId.get(e.exerciseId);
        const cands = ex ? [...(ex.alternates ?? []).map((id) => byId.get(id)), ...lib.filter((x) => x.pattern && x.pattern === ex.pattern && x.source === 'curated')] : [];
        const swap = ex ? bestReplacement(ex, cands, eq, used) : undefined;
        return { ...e, swapExerciseId: swap?.id, cue: e.cue ?? ex?.cue };
      }),
    };
  });
  return saveProgramDays(p, w.name, days, 'ai-coach');
}

/** Save an AI coach diet as the active diet plan. */
export async function saveAiDiet(diet: NonNullable<NormPlan['diet']>) {
  const dietPlanId = uid();
  await db.transaction('rw', [db.dietPlans, db.plannedMeals, db.habitDefs], async () => {
    await db.dietPlans.toCollection().modify({ active: false });
    await db.dietPlans.add({ id: dietPlanId, name: `AI coach · ${diet.kcalTarget.toLocaleString()} kcal`, active: true, kcalTarget: diet.kcalTarget, proteinTargetG: diet.proteinTargetG });
    await db.plannedMeals.bulkAdd(
      diet.meals.map((m, i) => ({
        id: uid(),
        dietPlanId,
        order: i,
        time: m.time.padStart(5, '0'),
        meal: m.meal,
        items: m.items,
        rotate: m.rotate,
        kcal: Math.round(m.kcal),
        proteinG: Math.round(m.proteinG),
        optional: m.optional,
      })),
    );
    if (!(await db.habitDefs.count())) await db.habitDefs.bulkPut(DEFAULT_HABITS);
  });
  return dietPlanId;
}

export async function saveGeneratedDiet(p: Profile, kcal?: number, protein?: number) {
  const age = new Date().getFullYear() - p.birthYear;
  const d = generateDiet({
    sex: p.sex,
    age,
    heightCm: p.heightCm,
    weightKg: p.startWeightKg,
    goalWeightKg: p.goalWeightKg,
    goal: p.goal ?? 'lean',
    trainingDays: p.trainingDays.length,
    dietType: p.dietType,
    intolerances: p.intolerances,
    kcalOverride: kcal,
    proteinOverride: protein,
  });
  const dietPlanId = uid();
  await db.transaction('rw', [db.dietPlans, db.plannedMeals, db.habitDefs], async () => {
    await db.dietPlans.toCollection().modify({ active: false });
    await db.dietPlans.add({ id: dietPlanId, name: `My ${d.kcalTarget.toLocaleString()} kcal plan`, active: true, kcalTarget: d.kcalTarget, proteinTargetG: d.proteinTargetG });
    await db.plannedMeals.bulkAdd(d.meals.map((m, i) => ({ id: uid(), dietPlanId, order: i, ...m })));
    if (!(await db.habitDefs.count())) await db.habitDefs.bulkPut(DEFAULT_HABITS);
  });
  return d;
}

/** Replace/remove planned exercises that need equipment the user doesn't have. Returns readable changes. */
export async function adaptActivePlanToEquipment(equipment: readonly string[]): Promise<string[]> {
  const program = await db.programs.filter((p) => p.active).first();
  if (!program) return [];
  await ensureLibrary();
  const days = await db.programDays.where('programId').equals(program.id).toArray();
  const exMap = new Map((await db.exercises.toArray()).map((e) => [e.id, e]));
  const out: string[] = [];
  for (const d of days) {
    const planned = await db.plannedExercises.where('dayId').equals(d.id).sortBy('order');
    const changes = adaptToEquipment(planned, exMap, equipment);
    for (const c of changes) {
      const from = exMap.get(c.from)?.name ?? c.from;
      const to = c.to ? exMap.get(c.to)?.name : undefined;
      if (c.kind === 'replaced') {
        await db.plannedExercises.update(c.plannedExerciseId, { exerciseId: c.to });
        out.push(`${d.title}: ${from} → ${to}`);
      } else if (c.kind === 'removed') {
        await db.plannedExercises.delete(c.plannedExerciseId);
        out.push(`${d.title}: removed ${from} (no equipment for it or its alternates)`);
      } else if (c.kind === 'swap_replaced') await db.plannedExercises.update(c.plannedExerciseId, { swapExerciseId: c.to });
      else await db.plannedExercises.update(c.plannedExerciseId, { swapExerciseId: undefined });
    }
  }
  return out;
}

export async function applyTemplateProgram(p: Profile) {
  await importProgramTemplate({ trainingDays: p.trainingDays });
  return adaptActivePlanToEquipment(equipmentOf(p));
}

/** Apply a changed setup. History (sessions, sets, meals, body) is always kept. */
export async function applySetup(next: Profile, opts: { rebuildWorkout: boolean; rebuildDiet: boolean }): Promise<string[]> {
  const notes: string[] = [];
  await db.profile.put(next);
  if (opts.rebuildWorkout) {
    if (next.planSource === 'template') notes.push(...(await applyTemplateProgram(next)));
    else {
      await saveGeneratedProgram({ ...next, planSource: 'generated' });
      await db.profile.update('me', { planSource: 'generated' });
    }
    notes.unshift('Workout plan rebuilt from your settings');
  } else {
    const changed = await adaptActivePlanToEquipment(equipmentOf(next));
    if (changed.length) notes.push(...changed);
  }
  if (opts.rebuildDiet) {
    if (next.dietSource === 'template') await importDietTemplate();
    else {
      await saveGeneratedDiet(next);
      await db.profile.update('me', { dietSource: 'generated' });
    }
    notes.push('Diet plan rebuilt');
  }
  await setMeta('setupChangedAt', new Date().toISOString());
  return notes;
}
