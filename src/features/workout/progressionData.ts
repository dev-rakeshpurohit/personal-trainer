import { db } from '@/data/db';
import { incrementFor, suggestNext, type History, type Suggestion } from '@/domain/progression';
import { cycleWeek, effectiveSets, isDeloadWeek, targetRir } from '@/domain/schedule';
import type { Exercise, PlannedExercise, Profile, Program, SetLog } from '@/domain/types';

/** Past *completed* sessions' working sets for an exercise, latest session first. */
export async function loadHistory(exerciseId: string, excludeSessionId?: string, limit = 3): Promise<History> {
  const sets = await db.sets.where('exerciseId').equals(exerciseId).filter((s) => !s.isWarmup && s.sessionId !== excludeSessionId).toArray();
  if (!sets.length) return [];
  const sessionIds = [...new Set(sets.map((s) => s.sessionId))];
  const sessions = (await db.sessions.bulkGet(sessionIds)).filter((s) => s && s.status !== 'abandoned');
  const order = sessions.sort((a, b) => b!.startedAt.localeCompare(a!.startedAt)).map((s) => s!.id);
  return order.slice(0, limit).map((id) => sets.filter((s) => s.sessionId === id).sort((a, b) => a.setIndex - b.setIndex));
}

export async function allSetsFor(exerciseId: string): Promise<SetLog[]> {
  return db.sets.where('exerciseId').equals(exerciseId).filter((s) => !s.isWarmup).toArray();
}

export interface PlannedSuggestion extends Suggestion {
  exerciseId: string;
  sets: number;
  last?: History[number];
}

export async function suggestionFor(
  pe: PlannedExercise,
  exerciseId: string,
  ex: Exercise | undefined,
  profile: Profile,
  program: Program,
  date: Date,
  excludeSessionId?: string,
): Promise<PlannedSuggestion> {
  const week = cycleWeek(date, program.startedOn);
  const deload = isDeloadWeek(week, program.progression.cycle);
  const sets = effectiveSets(pe.sets, deload);
  const history = await loadHistory(exerciseId, excludeSessionId);
  const s = suggestNext({
    planned: pe,
    sets,
    history,
    targetRir: targetRir(week, program.progression.cycle),
    increment: ex ? incrementFor(ex, profile.stepKg) : profile.stepKg.dumbbell,
    bodyweight: ex?.isBodyweight,
  });
  return { ...s, exerciseId, sets, last: history[0] };
}

/** Count of planned exercises (main exercise) ready to go heavier for a day. */
export async function goHeavierFor(
  planned: PlannedExercise[],
  exMap: Map<string, Exercise>,
  profile: Profile,
  program: Program,
  date: Date,
): Promise<{ name: string; message: string }[]> {
  const out: { name: string; message: string }[] = [];
  for (const pe of planned) {
    const s = await suggestionFor(pe, pe.exerciseId, exMap.get(pe.exerciseId), profile, program, date);
    if (s.kind === 'increase' || s.kind === 'time_increase') out.push({ name: exMap.get(pe.exerciseId)?.name ?? pe.exerciseId, message: s.message });
  }
  return out;
}
