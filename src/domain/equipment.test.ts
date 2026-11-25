import { adaptToEquipment, bestReplacement, isAvailable, PRESETS, requiredEquipment } from './equipment';
import type { Exercise, PlannedExercise } from './types';

const ex = (id: string, name: string, equipment: string[], level = 3, extra: Partial<Exercise> = {}): Exercise => ({
  id, name, equipment, primaryMuscles: [], category: 'strength', custom: false, defaultUnit: 'reps', level, ...extra,
});

describe('required equipment', () => {
  it('maps free-exercise-db equipment and names', () => {
    expect(requiredEquipment(ex('a', 'Dumbbell goblet squat', ['dumbbell']))).toEqual(['dumbbells']);
    expect(requiredEquipment(ex('b', 'Trap-bar deadlift', ['other']))).toEqual(['trap_bar']);
    expect(requiredEquipment(ex('c', 'Lat pulldown', ['cable']))).toEqual(expect.arrayContaining(['cable', 'machines']));
    expect(requiredEquipment(ex('d', 'Leg press', ['machine']))).toEqual(['machines']);
    expect(requiredEquipment(ex('e', 'Bike intervals', ['machine']))).toEqual(['cardio_machines']);
    expect(requiredEquipment(ex('f', 'Front plank', ['body only']))).toEqual([]);
    expect(requiredEquipment(ex('g', 'Incline dumbbell press', ['dumbbell']))).toEqual(['dumbbells', 'bench']);
    expect(requiredEquipment(ex('h', 'Hanging knee raise', ['body only']))).toEqual(['pullup_bar']);
    expect(requiredEquipment(ex('i', 'Band face pull', ['bands']))).toEqual(['bands']);
    expect(requiredEquipment(ex('j', 'Low box jump (30–45 cm)', ['body only']))).toEqual(['box']);
    expect(requiredEquipment(ex('k', "Farmer's carry", ['other']))).toEqual(['dumbbells']);
  });
  it('checks availability; bodyweight is always available', () => {
    expect(isAvailable(ex('f', 'Push-ups', ['body only']), [])).toBe(true);
    expect(isAvailable(ex('a', 'Dumbbell row', ['dumbbell']), PRESETS.home)).toBe(false);
    expect(isAvailable(ex('a', 'Dumbbell row', ['dumbbell']), PRESETS.dumbbells_only)).toBe(true);
  });
});

describe('plan substitution', () => {
  const lat = ex('lat', 'Lat pulldown', ['cable'], 2, { alternates: ['band', 'pull', 'row'] });
  const band = ex('band', 'Band-assisted pull-up', ['bands'], 2);
  const pull = ex('pull', 'Pull-up', ['body only'], 4);
  const row = ex('row', 'One-arm dumbbell row', ['dumbbell'], 2);
  const map = new Map([lat, band, pull, row].map((e) => [e.id, e]));
  const pe: PlannedExercise = { id: 'p1', dayId: 'd', order: 0, slot: 'B1', exerciseId: 'lat', swapExerciseId: 'row', sets: 3, repsMin: 10, repsMax: 12, unit: 'reps', perSide: false, restSec: 60 };

  it('prefers the closest difficulty that is available', () => {
    expect(bestReplacement(lat, [row, band, pull], ['dumbbells', 'bands'])?.id).toBe('row');
    expect(bestReplacement(lat, [band, pull], ['bands', 'pullup_bar'])?.id).toBe('band');
    expect(bestReplacement(lat, [band, pull], ['bands'])).toBeUndefined(); // band-assisted pull-ups still need a bar
  });
  it('never keeps an unavailable exercise: replace main, then fix the swap', () => {
    const c = adaptToEquipment([pe], map, ['bands', 'pullup_bar']);
    expect(c).toEqual([
      { plannedExerciseId: 'p1', from: 'lat', to: 'band', kind: 'replaced' },
      { plannedExerciseId: 'p1', from: 'row', to: 'pull', kind: 'swap_replaced' },
    ]);
  });
  it('removes when nothing fits', () => {
    const lonely = ex('lonely', 'Leg press', ['machine'], 2, { alternates: [] });
    const c = adaptToEquipment([{ ...pe, exerciseId: 'lonely', swapExerciseId: undefined }], new Map([['lonely', lonely]]), []);
    expect(c[0].kind).toBe('removed');
  });
  it('keeps everything with a full gym', () => {
    expect(adaptToEquipment([pe], map, PRESETS.full_gym)).toEqual([]);
  });
});
