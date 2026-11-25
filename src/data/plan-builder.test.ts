import { db } from './db';
import { adaptActivePlanToEquipment, applySetup, saveGeneratedDiet, saveGeneratedProgram } from './plan-builder';
import { importProgramTemplate } from './seed-import';
import { isAvailable, PRESETS } from '@/domain/equipment';
import type { Profile } from '@/domain/types';

const profile: Profile = {
  id: 'me', name: 'T', sex: 'female', birthYear: 1995, heightCm: 165, startWeightKg: 68, goalWeightKg: 62, units: 'kg', theme: 'dark',
  dietType: 'veg', intolerances: ['lactose'], kcalTarget: 0, proteinTargetG: 0, trainingDays: ['MON', 'WED', 'FRI'], sessionTime: '07:00',
  restTimer: { sound: true, vibrate: true, notify: false }, stepKg: { dumbbell: 2, barbell: 5, machine: 5 }, weekStart: 'mon', createdAt: '',
  goal: 'muscle', experience: 'beginner', sessionMin: 45, equipment: PRESETS.dumbbells_only, planSource: 'generated', dietSource: 'generated',
};

beforeEach(async () => {
  await db.delete();
  await db.open();
});

async function plannedExercises() {
  const prog = await db.programs.filter((p) => p.active).first();
  const days = await db.programDays.where('programId').equals(prog!.id).toArray();
  return { days, planned: await db.plannedExercises.where('dayId').anyOf(days.map((d) => d.id)).toArray() };
}

describe('plan builder', () => {
  it('saves a generated program that only uses available equipment', async () => {
    await saveGeneratedProgram(profile);
    const { days, planned } = await plannedExercises();
    expect(days).toHaveLength(7);
    expect(days.filter((d) => d.type === 'strength')).toHaveLength(3);
    const ex = new Map((await db.exercises.toArray()).map((e) => [e.id, e]));
    for (const p of planned) expect(isAvailable(ex.get(p.exerciseId)!, PRESETS.dumbbells_only)).toBe(true);
  });
  it('saves a generated diet with targets', async () => {
    const d = await saveGeneratedDiet(profile);
    expect(d.kcalTarget).toBeGreaterThan(1400);
    expect(await db.plannedMeals.count()).toBeGreaterThanOrEqual(6);
    expect(await db.habitDefs.count()).toBeGreaterThan(0);
  });
  it('adapts the template to a dumbbells-only gym: nothing unavailable remains', async () => {
    await importProgramTemplate();
    const changes = await adaptActivePlanToEquipment(PRESETS.dumbbells_only);
    expect(changes.length).toBeGreaterThan(3);
    const { planned } = await plannedExercises();
    const ex = new Map((await db.exercises.toArray()).map((e) => [e.id, e]));
    for (const p of planned) {
      expect(isAvailable(ex.get(p.exerciseId)!, PRESETS.dumbbells_only)).toBe(true);
      if (p.swapExerciseId) expect(isAvailable(ex.get(p.swapExerciseId)!, PRESETS.dumbbells_only)).toBe(true);
    }
  });
  it('applySetup keeps history and rebuilds on request', async () => {
    await saveGeneratedProgram(profile);
    await db.sessions.add({ id: 's1', dayKey: '2026-12-01', title: 'x', startedAt: '2026-12-01T07:00:00Z', status: 'done', cycleWeek: 1, deload: false });
    const notes = await applySetup({ ...profile, goal: 'strength', trainingDays: ['TUE', 'THU'] }, { rebuildWorkout: true, rebuildDiet: true });
    expect(notes[0]).toMatch(/rebuilt/);
    expect(await db.sessions.count()).toBe(1);
    const { days } = await plannedExercises();
    expect(days.filter((d) => d.type === 'strength').map((d) => d.weekday).sort()).toEqual(['THU', 'TUE']);
  });
});
