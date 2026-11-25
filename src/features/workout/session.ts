import { db, uid } from '@/data/db';
import { adaptFromFeedback, buildSessionPlan, estimateMinutes, hiitLevel, targetsForUnit, type Adaptation } from '@/domain/sessionPlan';
import { cycleWeek, dayKey, isDeloadWeek, targetRir } from '@/domain/schedule';
import type { ActiveSessionState, ProgramDay, Session, SessionExercise, SessionFeedback, SessionMode, SetLog, WeekFocus } from '@/domain/types';
import { cancelRestNotification } from '@/lib/notify';

export interface Prepared {
  day: ProgramDay;
  plan: SessionExercise[];
  adaptation: Adaptation;
  hiit?: 1 | 2 | 3;
  week?: WeekFocus;
  cycleWeek: number;
  deload: boolean;
  estMin: number;
}

async function recentFeedback(programDayId: string, n = 3): Promise<SessionFeedback[]> {
  const s = await db.sessions.where('programDayId').equals(programDayId).filter((x) => x.status === 'done' && !!x.feedback).toArray();
  return s
    .sort((a, b) => b.startedAt.localeCompare(a.startedAt))
    .slice(0, n)
    .map((x) => x.feedback!);
}

async function conditioningHistory(): Promise<{ feel?: SessionFeedback['feel'] }[]> {
  const condDays = await db.programDays.filter((d) => d.type === 'conditioning').toArray();
  const ids = new Set(condDays.map((d) => d.id));
  const s = await db.sessions.filter((x) => x.status === 'done' && !!x.programDayId && ids.has(x.programDayId)).toArray();
  return s.sort((a, b) => b.startedAt.localeCompare(a.startedAt)).map((x) => ({ feel: x.feedback?.feel }));
}

export async function prepareSession(dayId: string, mode: SessionMode, date = new Date()): Promise<Prepared | undefined> {
  const day = await db.programDays.get(dayId);
  if (!day) return undefined;
  const program = await db.programs.get(day.programId);
  if (!program) return undefined;
  const planned = await db.plannedExercises.where('dayId').equals(dayId).sortBy('order');
  const cw = cycleWeek(date, program.startedOn);
  const deload = isDeloadWeek(cw, program.progression.cycle);
  const week = program.progression.weeks?.find((w) => w.week === cw);
  const adaptation = adaptFromFeedback(await recentFeedback(dayId));
  const hiit = day.type === 'conditioning' ? hiitLevel(await conditioningHistory()) : undefined;
  const plan = buildSessionPlan({
    planned,
    dayType: day.type,
    mode,
    deload,
    week,
    fallbackRir: targetRir(cw, program.progression.cycle),
    hiit,
    adaptation,
  });
  return { day, plan, adaptation, hiit, week, cycleWeek: cw, deload, estMin: estimateMinutes(plan) };
}

export async function startSession(p: Prepared, mode: SessionMode, date = new Date()): Promise<string> {
  const existing = await db.activeSession.get('current');
  if (existing) {
    const s = await db.sessions.get(existing.sessionId);
    if (s?.status === 'active') return s.id;
  }
  const session: Session = {
    id: uid(),
    dayKey: dayKey(date),
    programDayId: p.day.id,
    title: p.day.title,
    startedAt: date.toISOString(),
    status: 'active',
    cycleWeek: p.cycleWeek,
    deload: p.deload,
    mode,
  };
  const active: ActiveSessionState = {
    id: 'current',
    sessionId: session.id,
    exerciseIdx: 0,
    setIdx: 0,
    swaps: {},
    plan: p.plan,
    prShown: [],
    hold: p.adaptation.holdProgression,
    pain: p.adaptation.pain,
  };
  await db.transaction('rw', db.sessions, db.activeSession, async () => {
    await db.sessions.add(session);
    await db.activeSession.put(active);
  });
  return session.id;
}

export async function patchActive(patch: Partial<ActiveSessionState>) {
  await db.activeSession.update('current', patch);
}

/** Log one set: written to IndexedDB immediately (never lose a log). */
export async function logSet(sessionId: string, se: SessionExercise, setIndex: number, v: Pick<SetLog, 'weightKg' | 'reps' | 'seconds' | 'meters' | 'rir'>): Promise<SetLog> {
  const row: SetLog = {
    id: uid(),
    sessionId,
    exerciseId: se.exerciseId,
    plannedExerciseId: se.plannedExerciseId,
    swappedFromExerciseId: se.exerciseId !== se.originalExerciseId ? se.originalExerciseId : undefined,
    setIndex,
    ...v,
    completedAt: new Date().toISOString(),
    isWarmup: false,
  };
  await db.sets.add(row);
  return row;
}

export async function updateSet(id: string, patch: Partial<SetLog>) {
  await db.sets.update(id, patch);
}

export async function deleteSet(id: string): Promise<() => Promise<void>> {
  const prev = await db.sets.get(id);
  await db.sets.delete(id);
  return async () => {
    if (prev) await db.sets.put(prev);
  };
}

/** Swap an exercise for today (active session) and optionally make it permanent in the plan. */
export async function swapExercise(active: ActiveSessionState, idx: number, exerciseId: string, always: boolean) {
  const plan = [...(active.plan ?? [])];
  const cur = plan[idx];
  const ex = await db.exercises.get(exerciseId);
  const unit = ex?.defaultUnit ?? cur.unit;
  const planned = await db.plannedExercises.get(cur.plannedExerciseId);
  const base = planned ? { unit: planned.unit, repsMin: planned.repsMin, repsMax: planned.repsMax } : cur;
  const t = targetsForUnit(base, unit);
  plan[idx] = { ...cur, exerciseId, ...(unit === base.unit ? { unit: cur.unit, repsMin: cur.repsMin, repsMax: cur.repsMax } : t) };
  const swaps = { ...active.swaps };
  if (exerciseId === cur.originalExerciseId) delete swaps[cur.plannedExerciseId];
  else swaps[cur.plannedExerciseId] = exerciseId;
  await patchActive({ plan, swaps });
  if (always && planned) await makePermanentSwap(planned.id, exerciseId);
}

export async function makePermanentSwap(plannedExerciseId: string, exerciseId: string) {
  const pe = await db.plannedExercises.get(plannedExerciseId);
  if (!pe || pe.exerciseId === exerciseId) return;
  const ex = await db.exercises.get(exerciseId);
  const patch: Record<string, unknown> = { exerciseId, swapExerciseId: pe.swapExerciseId === exerciseId ? pe.exerciseId : pe.swapExerciseId };
  if (ex && ex.defaultUnit !== pe.unit) Object.assign(patch, targetsForUnit(pe, ex.defaultUnit));
  await db.plannedExercises.update(pe.id, patch);
  // keep the alternates list on the new exercise so it can be swapped back
  const orig = await db.exercises.get(pe.exerciseId);
  if (ex && orig?.alternates && !ex.alternates?.length) await db.exercises.update(ex.id, { alternates: [orig.id, ...orig.alternates.filter((a) => a !== ex.id)], pattern: ex.pattern ?? orig.pattern });
}

export async function finishSession(sessionId: string, notes?: string) {
  cancelRestNotification();
  await db.transaction('rw', db.sessions, db.activeSession, async () => {
    await db.sessions.update(sessionId, { status: 'done', endedAt: new Date().toISOString(), ...(notes ? { notes } : {}) });
    await db.activeSession.delete('current');
  });
}

export async function discardSession(sessionId: string) {
  cancelRestNotification();
  await db.transaction('rw', db.sessions, db.activeSession, db.sets, async () => {
    await db.sets.where('sessionId').equals(sessionId).delete();
    await db.sessions.delete(sessionId);
    await db.activeSession.delete('current');
  });
}

export async function saveFeedback(sessionId: string, fb: SessionFeedback) {
  await db.sessions.update(sessionId, { feedback: fb, rpe: fb.rpe, notes: fb.note });
}
