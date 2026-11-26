import { db } from './db';
import { addExerciseToDay } from './plan-edit';
import { ensureLibrary, staticLibrary } from './plan-builder';
import { importProgramTemplate } from './seed-import';
import { planCheck, weeklySets } from '@/domain/balance';
import { isAvailable, PRESETS } from '@/domain/equipment';

beforeEach(async () => {
  await db.delete();
  await db.open();
});

async function load() {
  const program = await db.programs.filter((p) => p.active).first();
  const days = await db.programDays.where('programId').equals(program!.id).sortBy('order');
  const planned = await db.plannedExercises.where('dayId').anyOf(days.map((d) => d.id)).toArray();
  const exMap = new Map((await db.exercises.toArray()).map((e) => [e.id, e]));
  return { days, planned, exMap };
}

describe('plan check on the default lean-athletic template', () => {
  it('finds the calf gap and suggests a plain, available calf raise on a strength day', async () => {
    await importProgramTemplate({ trainingDays: ['TUE', 'WED', 'THU', 'FRI', 'SAT'] });
    await ensureLibrary();
    const { days, planned, exMap } = await load();
    const res = planCheck({ days, planned, exMap, library: staticLibrary(), equipment: PRESETS.full_gym, goal: 'lean' });
    expect(res.sets.calves).toBeLessThan(res.targets.calves);
    const calves = res.suggestions.find((s) => s.group === 'calves')!;
    expect(calves).toBeTruthy();
    expect(calves.options[0].name).toMatch(/calf raise/i);
    expect(days.find((d) => d.id === calves.dayId)!.type).toBe('strength');
    for (const s of res.suggestions) for (const o of s.options) expect(isAvailable(o, PRESETS.full_gym)).toBe(true);
    // big compound groups are already covered
    expect(res.suggestions.some((s) => s.group === 'quads' || s.group === 'back')).toBe(false);
  });

  it('applying a suggestion closes the gap', async () => {
    await importProgramTemplate({ trainingDays: ['TUE', 'WED', 'THU', 'FRI', 'SAT'] });
    await ensureLibrary();
    let { days, planned, exMap } = await load();
    const res = planCheck({ days, planned, exMap, library: staticLibrary(), equipment: PRESETS.full_gym, goal: 'lean' });
    for (const s of res.suggestions) await addExerciseToDay(s.dayId, s.options[0].id, { sets: s.sets, repsMin: s.repsMin, repsMax: s.repsMax, restSec: s.restSec });
    ({ days, planned, exMap } = await load());
    const after = planCheck({ days, planned, exMap, library: staticLibrary(), equipment: PRESETS.full_gym, goal: 'lean' });
    expect(after.suggestions.length).toBeLessThan(res.suggestions.length);
    expect(weeklySets(days, planned, exMap).calves).toBeGreaterThanOrEqual(after.targets.calves);
  });

  it('dumbbells-only gym never gets machine suggestions', async () => {
    await importProgramTemplate({ trainingDays: ['TUE', 'WED', 'THU', 'FRI', 'SAT'] });
    await ensureLibrary();
    const { days, planned, exMap } = await load();
    const res = planCheck({ days, planned, exMap, library: staticLibrary(), equipment: PRESETS.dumbbells_only, goal: 'muscle' });
    for (const s of res.suggestions) for (const o of s.options) expect(isAvailable(o, PRESETS.dumbbells_only)).toBe(true);
  });
});

describe('library upgrade', () => {
  it('adds dataset exercises and refreshes curated metadata without touching user edits', async () => {
    await importProgramTemplate();
    await db.exercises.update('dumbbell-goblet-squat', { isBodyweight: true, cue: 'my cue', demoId: undefined, instructions: ['old'] });
    const r = await ensureLibrary();
    expect(r.added).toBeGreaterThan(1000);
    const ex = await db.exercises.get('dumbbell-goblet-squat');
    expect(ex!.isBodyweight).toBe(true);
    expect(ex!.cue).toBe('my cue');
    expect(ex!.demoId).toBe('1760');
    expect(ex!.instructions![0]).toMatch(/dumbbell/i);
    expect(ex!.secondaryMuscles).toContain('glutes');
    // idempotent
    expect((await ensureLibrary()).added).toBe(0);
  });
});
