import { buildPrompt, extractJson, normaliseAiPlan, type CoachRequest } from './aiPlan';

const allowed = new Map([
  ['dumbbell-goblet-squat', { name: 'Dumbbell goblet squat' }],
  ['dumbbell-bench-press', { name: 'Dumbbell bench press' }],
  ['lat-pulldown', { name: 'Lat pulldown' }],
  ['dumbbell-biceps-curl', { name: 'Dumbbell biceps curl' }],
  ['rope-triceps-pushdown', { name: 'Rope triceps pushdown' }],
]);

const req: CoachRequest = {
  code: 'RPM-AAAA-BBBB',
  mode: 'new',
  want: { workout: true, diet: true },
  profile: {
    sex: 'male', age: 35, heightCm: 175, weightKg: 82, goalWeightKg: 75, goal: 'lean', experience: 'beginner',
    trainingDays: ['TUE', 'THU', 'SAT'], sessionMin: 60, equipment: ['dumbbells', 'cable'], dietType: 'veg_egg', intolerances: ['peanuts'],
  },
  notes: 'Bad left knee, no jumping. Love paneer.',
  exercises: [...allowed].map(([id, v]) => ({ id, name: v.name, pattern: 'x', unit: 'reps' })),
};

describe('AI coach prompt', () => {
  it('carries the person, notes and only the allowed exercises', () => {
    const { system, user } = buildPrompt(req);
    expect(system).toMatch(/ONLY exercise ids/);
    expect(user).toContain('Bad left knee');
    expect(user).toContain('avoid peanuts');
    expect(user).toContain('dumbbell-goblet-squat | Dumbbell goblet squat');
    expect(user).toContain('trains TUE, THU, SAT');
  });
  it('omits the exercise list for diet-only requests', () => {
    expect(buildPrompt({ ...req, want: { workout: false, diet: true } }).user).not.toContain('EXERCISES');
  });
});

describe('extractJson', () => {
  it('handles fences and stray text', () => {
    expect(extractJson('Sure!\n```json\n{"a":1}\n```')).toEqual({ a: 1 });
    expect(() => extractJson('no plan here')).toThrow(/did not return/);
  });
});

describe('normaliseAiPlan', () => {
  const raw = {
    summary: 'Three full-body days.',
    workout: {
      name: 'Lean 3-day',
      days: [
        {
          weekday: 'TUE', type: 'strength', title: 'Full body A', durationMin: 60,
          exercises: [
            { id: 'dumbbell-goblet-squat', sets: 3, repsMin: 12, repsMax: 8, unit: 'reps', restSec: 92 },
            { id: 'box-jump-made-up', sets: 3, repsMin: 5, repsMax: 5, unit: 'reps', restSec: 60 },
            { id: 'dumbbell-biceps-curl', sets: 2, repsMin: 10, repsMax: 12, unit: 'reps', restSec: 45, superset: 'a' },
            { id: 'rope-triceps-pushdown', sets: 2, repsMin: 10, repsMax: 12, unit: 'reps', restSec: 45, superset: 'a' },
            { id: 'dumbbell-goblet-squat', sets: 3, repsMin: 8, repsMax: 10, unit: 'reps', restSec: 90 },
          ],
        },
        { weekday: 'THU', type: 'strength', title: 'Full body B', exercises: [{ id: 'nope', sets: 3, repsMin: 8, repsMax: 10, unit: 'reps', restSec: 60 }] },
        { weekday: 'SAT', type: 'strength', title: 'Full body C', exercises: [{ id: 'lat-pulldown', sets: 99, repsMin: 10, repsMax: 12, unit: 'reps', restSec: 60 }] },
      ],
    },
    diet: {
      kcalTarget: 2000,
      proteinTargetG: 150,
      meals: [
        { time: '13:00', meal: 'Lunch', items: ['Paneer bhurji 150 g', '2 roti'], kcal: 700, proteinG: 45 },
        { time: '7:30', meal: 'Breakfast', items: ['4 egg whites + 1 egg'], kcal: 600, proteinG: 40 },
      ],
    },
  };

  it('drops unknown ids, dedupes, fixes rep order, rounds rest and fills the week', () => {
    const n = normaliseAiPlan(raw, allowed);
    expect(n.workout!.days).toHaveLength(7);
    const tue = n.workout!.days.find((d) => d.weekday === 'TUE')!;
    expect(tue.exercises.map((e) => e.exerciseId)).toEqual(['dumbbell-goblet-squat', 'dumbbell-biceps-curl', 'rope-triceps-pushdown']);
    expect(tue.exercises[0]).toMatchObject({ repsMin: 8, repsMax: 12, restSec: 90, slot: 'A' });
    expect(tue.exercises[1]).toMatchObject({ slot: 'B1', supersetGroup: 'B' });
    expect(tue.exercises[2]).toMatchObject({ slot: 'B2', supersetGroup: 'B' });
    // a training day with nothing valid becomes rest
    expect(n.workout!.days.find((d) => d.weekday === 'THU')).toMatchObject({ type: 'rest', exercises: [] });
    expect(n.workout!.days.find((d) => d.weekday === 'MON')!.type).toBe('rest');
    expect(n.warnings.some((w) => w.includes('box-jump-made-up'))).toBe(true);
  });

  it('clamps silly numbers instead of failing', () => {
    const sat = normaliseAiPlan(raw, allowed).workout!.days.find((d) => d.weekday === 'SAT')!;
    expect(sat.exercises[0].sets).toBeLessThanOrEqual(8);
  });

  it('sorts meals by time and warns when totals miss the target', () => {
    const n = normaliseAiPlan(raw, allowed);
    expect(n.diet!.meals[0].meal).toBe('Breakfast');
    expect(n.warnings.some((w) => /1300 kcal/.test(w))).toBe(true);
  });

  it('rejects replies with no usable plan', () => {
    expect(() => normaliseAiPlan({ summary: 'x' }, allowed)).toThrow(/empty plan/);
    expect(() => normaliseAiPlan({ summary: 'x', workout: { name: 'w', days: [{ weekday: 'MON', type: 'strength', title: 'A', exercises: [{ id: 'nope', sets: 3, repsMin: 5, repsMax: 5, unit: 'reps', restSec: 60 }] }] } }, allowed)).toThrow(/without exercises/);
    expect(() => normaliseAiPlan('garbage', allowed)).toThrow(/unexpected format/);
  });
});
