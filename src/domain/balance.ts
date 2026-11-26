/**
 * Plan check: weekly working sets per muscle group, gaps against a goal-based minimum, and
 * concrete fixes ("add X to Thursday"). Pure — the UI applies the suggestion.
 */
import { isAvailable } from './equipment';
import type { DayType, Exercise, Goal, PlannedExercise } from './types';

export type Group = 'chest' | 'back' | 'shoulders' | 'biceps' | 'triceps' | 'quads' | 'hamstrings' | 'glutes' | 'calves' | 'core';

export const GROUPS: { id: Group; label: string }[] = [
  { id: 'chest', label: 'Chest' },
  { id: 'back', label: 'Back' },
  { id: 'shoulders', label: 'Shoulders' },
  { id: 'biceps', label: 'Biceps' },
  { id: 'triceps', label: 'Triceps' },
  { id: 'quads', label: 'Quads' },
  { id: 'hamstrings', label: 'Hamstrings' },
  { id: 'glutes', label: 'Glutes' },
  { id: 'calves', label: 'Calves' },
  { id: 'core', label: 'Core' },
];

const MUSCLE_GROUP: Record<string, Group | undefined> = {
  chest: 'chest',
  lats: 'back',
  'middle back': 'back',
  traps: 'back',
  shoulders: 'shoulders',
  biceps: 'biceps',
  triceps: 'triceps',
  quadriceps: 'quads',
  hamstrings: 'hamstrings',
  glutes: 'glutes',
  calves: 'calves',
  abdominals: 'core',
};

/** Helper-muscle credit: stabilisers (calves in squats, abs in presses) don't count as training them. */
const SECONDARY_WEIGHT: Record<Group, number> = { chest: 0.5, back: 0.5, shoulders: 0.5, biceps: 0.5, triceps: 0.5, quads: 0.5, hamstrings: 0.5, glutes: 0.5, calves: 0, core: 0.25 };

export const groupOfMuscle = (m: string): Group | undefined => MUSCLE_GROUP[m];

/** Minimum weekly working sets that make a group "covered" for the goal (direct = 1, helper = ½). */
export function targets(goal: Goal | undefined): Record<Group, number> {
  const big = goal === 'muscle' ? 10 : goal === 'strength' ? 6 : 6;
  const small = goal === 'muscle' ? 6 : goal === 'strength' ? 3 : 4;
  return { chest: big, back: big, shoulders: small + 1, biceps: small, triceps: small, quads: big, hamstrings: big - 1, glutes: big - 1, calves: small, core: 6 };
}

export interface DayLite {
  id: string;
  title: string;
  weekday: string;
  type: DayType;
}

/** Weekly sets per group across strength, conditioning and core work (steady cardio doesn't count). */
export function weeklySets(days: DayLite[], planned: PlannedExercise[], exMap: Map<string, Exercise>): Record<Group, number> {
  const out = Object.fromEntries(GROUPS.map((g) => [g.id, 0])) as Record<Group, number>;
  const trainingDays = new Set(days.filter((d) => d.type === 'strength' || d.type === 'conditioning' || d.type === 'cardio').map((d) => d.id));
  for (const p of planned) {
    if (!trainingDays.has(p.dayId) || p.unit === 'minutes') continue;
    const ex = exMap.get(p.exerciseId);
    if (!ex) continue;
    const prim = new Set(ex.primaryMuscles.map(groupOfMuscle).filter((g): g is Group => !!g));
    if (ex.category === 'core' && !prim.size) prim.add('core');
    // hip-dominant compounds are real glute work even when the data lists glutes as a helper
    if (ex.pattern === 'hinge' || ex.pattern === 'lunge/single-leg' || ex.pattern === 'glute') prim.add('glutes');
    const sec = new Set((ex.secondaryMuscles ?? []).map(groupOfMuscle).filter((g): g is Group => !!g && !prim.has(g)));
    prim.forEach((g) => (out[g] += p.sets));
    sec.forEach((g) => (out[g] += p.sets * SECONDARY_WEIGHT[g]));
  }
  for (const g of GROUPS) out[g.id] = Math.round(out[g.id] * 2) / 2;
  return out;
}

/** Which movement patterns best fill a gap, in order of preference. */
const FIX_PATTERNS: Record<Group, string[]> = {
  chest: ['chest fly', 'horizontal push'],
  back: ['horizontal pull', 'vertical pull'],
  shoulders: ['lateral delt', 'vertical push'],
  biceps: ['elbow flexion'],
  triceps: ['elbow extension'],
  quads: ['knee extension', 'squat', 'lunge/single-leg'],
  hamstrings: ['knee flexion', 'hinge'],
  glutes: ['glute', 'hinge', 'lunge/single-leg'],
  calves: ['calves'],
  core: ['core flexion', 'core anti-extension', 'core anti-rotation'],
};
/** Where a group's extra work fits best: days already training a related area. */
const RELATED: Record<Group, Group[]> = {
  chest: ['chest', 'triceps', 'shoulders'],
  back: ['back', 'biceps'],
  shoulders: ['shoulders', 'chest'],
  biceps: ['back', 'biceps'],
  triceps: ['chest', 'triceps'],
  quads: ['quads', 'glutes'],
  hamstrings: ['hamstrings', 'glutes', 'quads'],
  glutes: ['glutes', 'hamstrings', 'quads'],
  calves: ['quads', 'hamstrings', 'glutes'],
  core: ['core'],
};

const ODD = /exercise ball|stability ball|bosu|\(v\d\)|arm blaster|stork|throw down|pov|on knees|towel|one leg|twisting|self assisted|kneeling jump|pirate|side lying|with leg raised|with bicep curl|lunge with|on floor\)/i;
const STAPLE = /^(machine (lying|seated) leg curl|machine leg extension|machine standing calf raise|dumbbell standing calf raise|bodyweight standing calf raise|machine seated calf raise|dumbbell fly|cable middle fly|machine seated fly|barbell glute bridge|glute bridge two legs on bench|cable standing hip extension|dumbbell incline fly|machine lateral raise|cable lateral raise|dumbbell lateral raise|dumbbell biceps curl|dumbbell hammer curl|ez-bar curl|rope triceps pushdown|cable pushdown|dumbbell standing triceps extension|seated cable row|chest-supported dumbbell row|cable crunch|crunch)$/i;

export interface Suggestion {
  group: Group;
  have: number;
  need: number;
  dayId: string;
  dayLabel: string;
  options: Exercise[];
  sets: number;
  repsMin: number;
  repsMax: number;
  restSec: number;
}

export function planCheck(input: {
  days: DayLite[];
  planned: PlannedExercise[];
  exMap: Map<string, Exercise>;
  library: Exercise[];
  equipment: readonly string[];
  goal?: Goal;
}): { sets: Record<Group, number>; targets: Record<Group, number>; suggestions: Suggestion[] } {
  const sets = weeklySets(input.days, input.planned, input.exMap);
  const tgt = targets(input.goal);
  const strengthDays = input.days.filter((d) => d.type === 'strength');
  const inPlan = new Set(input.planned.flatMap((p) => [p.exerciseId, p.swapExerciseId]).filter(Boolean) as string[]);
  const suggestions: Suggestion[] = [];
  if (!strengthDays.length) return { sets, targets: tgt, suggestions };

  // per-day group load, to place the fix next to related work
  const dayLoad = new Map<string, Record<Group, number>>();
  for (const d of strengthDays) dayLoad.set(d.id, weeklySets([d], input.planned.filter((p) => p.dayId === d.id), input.exMap));
  const dayCount = (id: string) => input.planned.filter((p) => p.dayId === id).length;
  const addedTo = new Map<string, number>();

  for (const g of GROUPS) {
    const have = sets[g.id];
    const need = tgt[g.id];
    if (have >= need) continue;
    const patterns = FIX_PATTERNS[g.id];
    const options = input.library
      .filter((e) => !inPlan.has(e.id) && e.defaultUnit !== 'minutes' && (e.category === 'strength' || e.category === 'core') && isAvailable(e, input.equipment))
      .filter((e) => e.pattern && patterns.includes(e.pattern) && e.primaryMuscles.some((m) => groupOfMuscle(m) === g.id || (g.id === 'core' && e.category === 'core')))
      .map((e) => ({
        e,
        score:
          patterns.indexOf(e.pattern!) * 1.5 +
          (e.source === 'dataset' ? 1 : 0) +
          (ODD.test(e.name) ? 5 : 0) -
          (STAPLE.test(e.name) ? 2 : 0) +
          Math.abs((e.level ?? 2) - 2),
      }))
      .sort((a, b) => a.score - b.score || a.e.name.localeCompare(b.e.name))
      .slice(0, 3)
      .map((x) => x.e);
    if (!options.length) continue;
    const rel = RELATED[g.id];
    const day = [...strengthDays].sort((a, b) => {
      const ra = rel.reduce((s, r) => s + dayLoad.get(a.id)![r], 0);
      const rb = rel.reduce((s, r) => s + dayLoad.get(b.id)![r], 0);
      const ca = dayCount(a.id) + (addedTo.get(a.id) ?? 0) * 1.5;
      const cb = dayCount(b.id) + (addedTo.get(b.id) ?? 0) * 1.5;
      return cb - ca + (rb - ra) * 0.4 || a.title.localeCompare(b.title);
    })[0];
    addedTo.set(day.id, (addedTo.get(day.id) ?? 0) + 1);
    const deficit = need - have;
    const small = g.id === 'calves' || g.id === 'biceps' || g.id === 'triceps' || g.id === 'core';
    suggestions.push({
      group: g.id,
      have,
      need,
      dayId: day.id,
      dayLabel: day.title,
      options,
      sets: Math.min(4, Math.max(2, Math.ceil(deficit))),
      repsMin: small ? 12 : 10,
      repsMax: small ? 15 : 12,
      restSec: small ? 45 : 60,
    });
  }
  return { sets, targets: tgt, suggestions };
}
