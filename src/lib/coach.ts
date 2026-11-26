/** App side of the AI coach: builds the request from local data, calls /api/coach, normalises the reply. */
import { db } from '@/data/db';
import { equipmentOf } from '@/data/plan-builder';
import { normaliseAiPlan, type CoachRequest, type CoachResponse, type NormPlan } from '@/domain/aiPlan';
import { isAvailable } from '@/domain/equipment';
import type { Exercise, Profile } from '@/domain/types';
import { WEEKDAYS } from '@/domain/types';
import { storedCode } from './access';

const ODD = /exercise ball|stability ball|bosu|\(v\d\)|arm blaster|stork|throw down|pov|on knees|towel|self assisted|pirate|side lying|with leg raised|with bicep curl|kipping|planche|maltese|flag|elevator|impossible|korean|skin the cat/i;
const MAX_LEVEL = { beginner: 3, intermediate: 4, advanced: 5 } as const;

/** Exercises the coach may choose from: what fits the gym, without odd variants, sensible for the level. */
export function coachExercises(lib: Exercise[], p: Profile): Exercise[] {
  const eq = equipmentOf(p);
  const max = MAX_LEVEL[p.experience ?? 'beginner'];
  return lib.filter((e) => isAvailable(e, eq) && (e.source !== 'dataset' || (!!e.pattern && !ODD.test(e.name) && (e.level ?? 2) <= max)));
}

/** Compact text of the current plan for "change my plan" requests. */
export async function currentPlanText(byId: Map<string, Exercise>): Promise<string | undefined> {
  const program = await db.programs.filter((x) => x.active).first();
  if (!program) return undefined;
  const days = (await db.programDays.where('programId').equals(program.id).toArray()).sort((a, b) => WEEKDAYS.indexOf(a.weekday) - WEEKDAYS.indexOf(b.weekday));
  const planned = await db.plannedExercises.where('dayId').anyOf(days.map((d) => d.id)).sortBy('order');
  const diet = await db.dietPlans.filter((x) => x.active).first();
  const meals = diet ? await db.plannedMeals.where('dietPlanId').equals(diet.id).sortBy('order') : [];
  const lines = days.map((d) => {
    const ex = planned
      .filter((p) => p.dayId === d.id)
      .map((p) => `${p.exerciseId} (${byId.get(p.exerciseId)?.name ?? ''}) ${p.sets}x${p.repsMin}-${p.repsMax}${p.unit === 'reps' ? '' : ' ' + p.unit}${p.supersetGroup ? ` ss${p.supersetGroup}` : ''}`);
    return `${d.weekday} ${d.type} "${d.title}"${d.durationMin ? ` ${d.durationMin}min` : ''}: ${ex.join('; ') || '-'}`;
  });
  if (diet) lines.push(`DIET ${diet.kcalTarget} kcal / ${diet.proteinTargetG} g protein:`, ...meals.map((m) => `${m.time} ${m.meal}: ${m.items.join(', ')} (${m.kcal} kcal, ${m.proteinG} g)`));
  return lines.join('\n').slice(0, 12000);
}

export class CoachError extends Error {
  constructor(
    message: string,
    public status?: number,
  ) {
    super(message);
  }
}

export interface CoachResult {
  plan: NormPlan;
  costUsd?: number;
  model: string;
}

export async function askCoach(opts: { mode: 'new' | 'change'; want: { workout: boolean; diet: boolean }; notes: string; code?: string; signal?: AbortSignal }): Promise<CoachResult> {
  const p = await db.profile.get('me');
  if (!p) throw new CoachError('Set up your profile first.');
  const code = opts.code ?? storedCode();
  if (!code) throw new CoachError('Enter your invite code to use the AI coach.', 401);
  const lib = await db.exercises.toArray();
  const byId = new Map(lib.map((e) => [e.id, e]));
  const allowed = coachExercises(lib, p);
  const body: CoachRequest = {
    code,
    mode: opts.mode,
    want: opts.want,
    profile: {
      sex: p.sex,
      age: Math.min(100, Math.max(13, new Date().getFullYear() - p.birthYear)),
      heightCm: p.heightCm,
      weightKg: (await db.bodyLogs.orderBy('dayKey').reverse().filter((b) => b.weightKg != null).first())?.weightKg ?? p.startWeightKg,
      goalWeightKg: p.goalWeightKg,
      goal: p.goal ?? 'lean',
      experience: p.experience ?? 'beginner',
      trainingDays: p.trainingDays,
      sessionMin: p.sessionMin ?? 60,
      sessionTime: p.sessionTime,
      equipment: equipmentOf(p),
      dietType: p.dietType,
      intolerances: p.intolerances,
      kcalTarget: p.kcalTarget || undefined,
      proteinTargetG: p.proteinTargetG || undefined,
    },
    notes: opts.notes.slice(0, 2000),
    exercises: opts.want.workout ? allowed.slice(0, 1500).map((e) => ({ id: e.id, name: e.name.slice(0, 90), pattern: e.pattern, unit: e.defaultUnit })) : [],
    current: opts.mode === 'change' ? await currentPlanText(byId) : undefined,
  };
  let r: Response;
  try {
    r = await fetch('/api/coach', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body), signal: opts.signal });
  } catch (e) {
    if ((e as Error).name === 'AbortError') throw e;
    throw new CoachError('No connection. The AI coach needs internet; your current plan still works offline.');
  }
  const data = (await r.json().catch(() => ({}))) as Partial<CoachResponse> & { error?: string };
  if (!r.ok) throw new CoachError(data.error ?? 'The coach is unavailable right now.', r.status);
  const plan = normaliseAiPlan(data.plan, new Map(allowed.map((e) => [e.id, { name: e.name }])));
  return { plan, costUsd: data.costUsd, model: data.model ?? '' };
}
