/** Small, shared edits to the active plan (used by the day editor, library, Plan check and the AI coach). */
import { db, uid } from './db';
import type { PlannedExercise, Unit } from '@/domain/types';

export interface AddOpts {
  sets?: number;
  repsMin?: number;
  repsMax?: number;
  restSec?: number;
  perSide?: boolean;
}

const PER_SIDE = /single|one-arm|one arm|lunge|split squat|step-?up|side plank|bulgarian|suitcase|one leg/i;

export async function addExerciseToDay(dayId: string, exerciseId: string, opts: AddOpts = {}): Promise<PlannedExercise> {
  const ex = await db.exercises.get(exerciseId);
  const day = await db.programDays.get(dayId);
  const planned = await db.plannedExercises.where('dayId').equals(dayId).toArray();
  const unit: Unit = ex?.defaultUnit ?? 'reps';
  const pe: PlannedExercise = {
    id: uid(),
    dayId,
    order: planned.length ? Math.max(...planned.map((p) => p.order)) + 1 : 0,
    slot: String(planned.length + 1),
    exerciseId,
    sets: opts.sets ?? 3,
    repsMin: opts.repsMin ?? (unit === 'reps' ? 8 : unit === 'seconds' ? 30 : unit === 'minutes' ? 20 : 30),
    repsMax: opts.repsMax ?? (unit === 'reps' ? 12 : unit === 'seconds' ? 45 : unit === 'minutes' ? 20 : 30),
    unit,
    perSide: opts.perSide ?? PER_SIDE.test(ex?.name ?? ''),
    restSec: opts.restSec ?? (unit === 'minutes' ? 0 : 75),
  };
  await db.transaction('rw', [db.plannedExercises, db.programDays], async () => {
    await db.plannedExercises.add(pe);
    if (day && (day.type === 'rest' || day.type === 'active_recovery')) await db.programDays.update(dayId, { type: 'strength' });
  });
  return pe;
}

/** Days of the active program, in week order. */
export async function activeDays() {
  const program = await db.programs.filter((p) => p.active).first();
  if (!program) return [];
  return db.programDays.where('programId').equals(program.id).sortBy('order');
}
