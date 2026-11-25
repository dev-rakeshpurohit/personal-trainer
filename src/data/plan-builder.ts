/** Writes generated plans to the DB, adapts plans to equipment, and applies setup changes (history is never touched). */
import { db, setMeta, uid } from './db';
import { buildExercises, DEFAULT_HABITS, importDietTemplate, importProgramTemplate, parseMediaIndex, parseResearch, parseSeedProgram } from './seed-import';
import { adaptToEquipment, PRESETS } from '@/domain/equipment';
import { generateDiet } from '@/domain/dietGen';
import { generateProgram } from '@/domain/generator';
import { dayKey, weekStartOf } from '@/domain/schedule';
import type { Exercise, PlannedExercise, Profile } from '@/domain/types';

export const equipmentOf = (p: Pick<Profile, 'equipment'>): string[] => p.equipment ?? PRESETS.full_gym;

/** Static exercise library (seed + research alternates); pure, used for previews before anything is saved. */
let cachedLibrary: Exercise[] | undefined;
export function staticLibrary(): Exercise[] {
  cachedLibrary ??= [...buildExercises(parseSeedProgram(), parseMediaIndex(), parseResearch()).values()];
  return cachedLibrary;
}

/** Make sure every library exercise exists (keeps the user's own edits and custom exercises). */
export async function ensureLibrary() {
  const lib = staticLibrary();
  const have = new Set(await db.exercises.toCollection().primaryKeys());
  const missing = lib.filter((e) => !have.has(e.id));
  if (missing.length) await db.exercises.bulkAdd(missing);
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
  const seed = parseSeedProgram();
  const research = parseResearch();
  const eq = equipmentOf(p);
  const programId = uid();
  const days = gen.days.map((d, i) => ({ id: uid(), programId, weekday: d.weekday, type: d.type, title: d.title, durationMin: d.durationMin, notes: d.notes, order: i }));
  const planned: PlannedExercise[] = gen.days.flatMap((d, i) => d.exercises.map((e, j) => ({ id: uid(), dayId: days[i].id, order: j, ...e })));
  await db.transaction('rw', [db.programs, db.programDays, db.plannedExercises], async () => {
    await db.programs.toCollection().modify({ active: false });
    await db.programs.add({
      id: programId,
      name: gen.name,
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
      templateId: `generated:${p.goal ?? 'lean'}`,
    });
    await db.programDays.bulkAdd(days);
    await db.plannedExercises.bulkAdd(planned);
  });
  return programId;
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
