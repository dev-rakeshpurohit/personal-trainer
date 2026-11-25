import { db } from './db';
import ids from '../../seed/free-exercise-db-ids.json';
import { importDietTemplate, importProgramTemplate, parseMediaIndex, remapDays, parseSeedProgram, slugify } from './seed-import';

beforeEach(async () => {
  await db.delete();
  await db.open();
});

describe('seed import', () => {
  it('imports the program: 7 days, 5 with exercises, 42 media ids', async () => {
    const r = await importProgramTemplate({ today: new Date(2026, 11, 1) });
    expect(r.days).toBe(7);
    expect(r.daysWithExercises).toBe(5);
    expect(ids).toHaveLength(42);
    const mediaIds = new Set(parseMediaIndex().map((m) => m.id));
    expect(ids.every((i: string) => mediaIds.has(i))).toBe(true);
    expect(r.mediaIds).toBeGreaterThanOrEqual(42);
    expect(await db.programDays.count()).toBe(7);
    const tue = await db.programDays.where('weekday').equals('TUE').first();
    expect(tue?.title).toMatch(/Strength A/);
    const pes = await db.plannedExercises.where('dayId').equals(tue!.id).sortBy('order');
    expect(pes).toHaveLength(6);
    expect(pes[1].swapExerciseId).toBe('dumbbell-floor-press');
    const prog = await db.programs.get(r.programId);
    expect(prog?.startedOn).toBe('2026-11-30');
  });
  it('every exercise with a freeDbId has local media', async () => {
    await importProgramTemplate();
    const mediaIds = new Set(parseMediaIndex().map((m) => m.id));
    const exs = await db.exercises.toArray();
    for (const e of exs) if (e.freeDbId) expect(mediaIds.has(e.freeDbId)).toBe(true);
    const goblet = await db.exercises.get('dumbbell-goblet-squat');
    expect(goblet?.isBodyweight).toBe(false);
    expect((await db.exercises.get('front-plank'))?.isBodyweight).toBe(true);
  });
  it('adds research alternates, patterns and the weekly wave', async () => {
    const r = await importProgramTemplate();
    const goblet = await db.exercises.get('dumbbell-goblet-squat');
    expect(goblet?.pattern).toBe('squat');
    expect(goblet?.alternates?.length).toBeGreaterThanOrEqual(3);
    const alt = await db.exercises.get(goblet!.alternates![0]);
    expect(alt?.freeDbId).toBeTruthy();
    expect(alt?.level).toBe(1);
    expect((await db.exercises.get('band-face-pull'))?.freeDbId).toBe('Band_Pull_Apart');
    const prog = await db.programs.get(r.programId);
    expect(prog?.progression.weeks).toHaveLength(8);
    expect(prog?.progression.weeks?.[7].deload).toBe(true);
  });
  it('imports the diet with habits', async () => {
    const r = await importDietTemplate();
    expect(r.meals).toBe(7);
    expect(r.habits).toBe(5);
    expect((await db.habitDefs.get('water'))?.target).toBe(3000);
    expect((await db.habitDefs.get('creatine'))?.kind).toBe('check');
  });
  it('remaps training days to the chosen weekdays', () => {
    const days = parseSeedProgram().days;
    expect(remapDays(days, ['TUE', 'WED', 'THU', 'FRI', 'SAT'])).toBe(days);
    const r = remapDays(days, ['MON', 'WED', 'FRI']);
    expect(r).toHaveLength(7);
    expect(r.find((d) => d.weekday === 'MON')?.title).toMatch(/Strength A/);
    expect(r.find((d) => d.weekday === 'TUE')?.type).toBe('rest');
    expect(r.find((d) => d.weekday === 'SUN')?.type).toBe('active_recovery');
  });
  it('slugifies names', () => expect(slugify("Farmer's carry")).toBe('farmers-carry'));
});
