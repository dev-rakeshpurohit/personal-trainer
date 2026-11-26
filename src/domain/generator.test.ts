import { staticLibrary } from '@/data/plan-builder';
import { isAvailable, PRESETS } from './equipment';
import { generateProgram, type Experience, type Goal } from './generator';
import type { Weekday } from './types';

const library = staticLibrary();
const DAYS: Record<number, Weekday[]> = {
  2: ['TUE', 'FRI'],
  3: ['MON', 'WED', 'FRI'],
  4: ['MON', 'TUE', 'THU', 'FRI'],
  5: ['TUE', 'WED', 'THU', 'FRI', 'SAT'],
  6: ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'],
};
const goals: Goal[] = ['fat_loss', 'lean', 'muscle', 'strength', 'general'];
const exps: Experience[] = ['beginner', 'intermediate', 'advanced'];

describe('program generator', () => {
  it('library has patterns for generation', () => {
    expect(library.filter((e) => e.pattern).length).toBeGreaterThan(150);
  });

  for (const preset of ['full_gym', 'dumbbells_only', 'home'] as const)
    for (const goal of goals)
      for (const n of [2, 3, 4, 5, 6])
        it(`${preset} · ${goal} · ${n} days: valid, equipment-safe, no repeats in a day`, () => {
          const eq = PRESETS[preset];
          const p = generateProgram({ goal, experience: exps[n % 3], days: DAYS[n], sessionMin: 60, equipment: eq, library });
          expect(p.days).toHaveLength(7);
          const training = p.days.filter((d) => d.exercises.length);
          expect(training.length).toBeGreaterThanOrEqual(preset === 'home' ? n - 1 : n);
          const byId = new Map(library.map((e) => [e.id, e]));
          for (const d of training) {
            const ids = d.exercises.map((e) => e.exerciseId);
            expect(new Set(ids).size).toBe(ids.length);
            expect(d.exercises.length).toBeLessThanOrEqual(6);
            for (const e of d.exercises) {
              expect(isAvailable(byId.get(e.exerciseId)!, eq)).toBe(true);
              if (e.swapExerciseId) expect(isAvailable(byId.get(e.swapExerciseId)!, eq)).toBe(true);
              expect(e.repsMin).toBeLessThanOrEqual(e.repsMax);
              expect(e.sets).toBeGreaterThan(0);
            }
            if (d.type === 'strength' && preset !== 'home') expect(d.exercises.length).toBeGreaterThanOrEqual(4);
          }
        });

  it('session length limits strength slots', () => {
    const p30 = generateProgram({ goal: 'muscle', experience: 'intermediate', days: DAYS[3], sessionMin: 30, equipment: PRESETS.full_gym, library });
    const p90 = generateProgram({ goal: 'muscle', experience: 'intermediate', days: DAYS[3], sessionMin: 90, equipment: PRESETS.full_gym, library });
    expect(Math.max(...p30.days.map((d) => d.exercises.length))).toBe(4);
    expect(Math.max(...p90.days.map((d) => d.exercises.length))).toBeGreaterThan(4);
  });
  it('strength goal uses low reps on main lifts; muscle uses 8–12', () => {
    const s = generateProgram({ goal: 'strength', experience: 'advanced', days: DAYS[3], sessionMin: 75, equipment: PRESETS.full_gym, library });
    expect(s.days.find((d) => d.exercises.length)!.exercises[0].repsMax).toBe(6);
    const m = generateProgram({ goal: 'muscle', experience: 'intermediate', days: DAYS[3], sessionMin: 75, equipment: PRESETS.full_gym, library });
    expect(m.days.find((d) => d.exercises.length)!.exercises[0]).toMatchObject({ repsMin: 8, repsMax: 12 });
  });
  it('fat loss 5 days mirrors the proven structure with an active-recovery day', () => {
    const p = generateProgram({ goal: 'fat_loss', experience: 'beginner', days: DAYS[5], sessionMin: 75, equipment: PRESETS.full_gym, library });
    expect(p.days.map((d) => d.type)).toEqual(['rest', 'strength', 'cardio', 'strength', 'conditioning', 'strength', 'active_recovery']);
  });
  it('beginners get easier variations', () => {
    const b = generateProgram({ goal: 'muscle', experience: 'beginner', days: DAYS[3], sessionMin: 60, equipment: PRESETS.full_gym, library });
    const byId = new Map(library.map((e) => [e.id, e]));
    for (const d of b.days) for (const e of d.exercises) expect(byId.get(e.exerciseId)!.level ?? 1).toBeLessThanOrEqual(3);
  });
});

describe('isolation work from the 3D library', () => {
  it('lower days for muscle goals get a plain leg curl and calf raise, never odd variants', () => {
    const p = generateProgram({ goal: 'muscle', experience: 'intermediate', days: ['MON', 'TUE', 'THU', 'FRI'], sessionMin: 75, equipment: PRESETS.full_gym, library });
    const byId = new Map(library.map((e) => [e.id, e]));
    const names = p.days.flatMap((d) => d.exercises.map((e) => byId.get(e.exerciseId)!.name));
    expect(names.some((n) => /leg curl/i.test(n))).toBe(true);
    expect(names.some((n) => /calf raise/i.test(n))).toBe(true);
    expect(names.some((n) => /exercise ball|bosu|arm blaster|\(v\d\)/i.test(n))).toBe(false);
  });

  it('curated main lifts still win over dataset variants', () => {
    const p = generateProgram({ goal: 'lean', experience: 'beginner', days: ['TUE', 'THU', 'SAT'], sessionMin: 60, equipment: PRESETS.full_gym, library });
    const byId = new Map(library.map((e) => [e.id, e]));
    const mains = p.days.flatMap((d) => d.exercises.filter((e) => e.slot.startsWith('A')).map((e) => byId.get(e.exerciseId)!));
    expect(mains.every((e) => e.source === 'curated')).toBe(true);
  });
});
