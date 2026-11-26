/**
 * Rule-based program generator (pure). Builds a weekly plan from goal, experience, training days,
 * session length and available equipment, using the movement-pattern library (doc 09).
 * Never includes an exercise whose equipment isn't available.
 */
import { isAvailable } from './equipment';
import type { DayType, Exercise, Experience, Goal, Unit, Weekday } from './types';
import { WEEKDAYS } from './types';

export type { Goal, Experience };

export const GOALS: { id: Goal; label: string; sub: string; emoji: string }[] = [
  { id: 'fat_loss', label: 'Lose fat', sub: 'Drop weight, keep muscle', emoji: '🔥' },
  { id: 'lean', label: 'Lean & athletic', sub: 'Leaner, stronger, fitter', emoji: '⚡' },
  { id: 'muscle', label: 'Build muscle', sub: 'Size with a small surplus', emoji: '💪' },
  { id: 'strength', label: 'Get stronger', sub: 'Heavier lifts, lower reps', emoji: '🏋️' },
  { id: 'general', label: 'General fitness', sub: 'Feel good, move well', emoji: '🌿' },
];

const P = {
  squat: 'squat', hinge: 'hinge', lunge: 'lunge/single-leg', hpush: 'horizontal push', vpush: 'vertical push',
  hpull: 'horizontal pull', vpull: 'vertical pull', curl: 'elbow flexion', ext: 'elbow extension', lat: 'lateral delt',
  rear: 'rear delt/scap', antiExt: 'core anti-extension', antiRot: 'core anti-rotation', flex: 'core flexion',
  carry: 'carry', power: 'power/plyometric', cardio: 'conditioning/cardio', mobility: 'mobility',
  kneeFlex: 'knee flexion', kneeExt: 'knee extension', calves: 'calves', fly: 'chest fly', glute: 'glute',
} as const;
type PKey = keyof typeof P;
type Role = 'main' | 'acc' | 'core' | 'steady' | 'interval' | 'power' | 'carry' | 'mobility';

interface SlotT {
  slot: string;
  p: PKey;
  role: Role;
  group?: string;
}
interface DayT {
  key: string;
  title: string;
  type: DayType;
  slots: SlotT[];
}

const s = (slot: string, p: PKey, role: Role, group?: string): SlotT => ({ slot, p, role, group });
const T: Record<string, DayT> = {
  FB_A: { key: 'FB_A', title: 'Full body A', type: 'strength', slots: [s('A1', 'squat', 'main', 'A'), s('A2', 'hpush', 'main', 'A'), s('B1', 'vpull', 'main', 'B'), s('B2', 'hinge', 'main', 'B'), s('C', 'vpush', 'acc'), s('D', 'antiExt', 'core'), s('E', 'flex', 'core'), s('F', 'calves', 'acc')] },
  FB_B: { key: 'FB_B', title: 'Full body B', type: 'strength', slots: [s('A1', 'squat', 'main', 'A'), s('A2', 'hpush', 'main', 'A'), s('B1', 'hpull', 'main', 'B'), s('B2', 'lunge', 'main', 'B'), s('C', 'rear', 'acc'), s('D1', 'curl', 'acc', 'D'), s('D2', 'ext', 'acc', 'D'), s('E', 'kneeFlex', 'acc')] },
  FB_C: { key: 'FB_C', title: 'Full body C – heavier', type: 'strength', slots: [s('A', 'hinge', 'main'), s('B1', 'vpull', 'main', 'B'), s('B2', 'hpush', 'main', 'B'), s('C', 'lunge', 'acc'), s('D1', 'lat', 'acc', 'D'), s('D2', 'antiRot', 'core', 'D'), s('E', 'carry', 'carry'), s('F', 'glute', 'acc')] },
  UA: { key: 'UA', title: 'Upper A', type: 'strength', slots: [s('A1', 'hpush', 'main', 'A'), s('A2', 'hpull', 'main', 'A'), s('B1', 'vpush', 'main', 'B'), s('B2', 'vpull', 'main', 'B'), s('C1', 'lat', 'acc', 'C'), s('C2', 'rear', 'acc', 'C'), s('D1', 'curl', 'acc', 'D'), s('D2', 'ext', 'acc', 'D')] },
  UB: { key: 'UB', title: 'Upper B', type: 'strength', slots: [s('A1', 'vpull', 'main', 'A'), s('A2', 'hpush', 'main', 'A'), s('B1', 'hpull', 'main', 'B'), s('B2', 'vpush', 'main', 'B'), s('C1', 'rear', 'acc', 'C'), s('C2', 'lat', 'acc', 'C'), s('D1', 'ext', 'acc', 'D'), s('D2', 'curl', 'acc', 'D')] },
  LA: { key: 'LA', title: 'Lower A', type: 'strength', slots: [s('A', 'squat', 'main'), s('B', 'hinge', 'main'), s('C', 'lunge', 'acc'), s('D1', 'kneeFlex', 'acc', 'D'), s('D2', 'calves', 'acc', 'D'), s('E', 'antiExt', 'core'), s('F', 'flex', 'core'), s('G', 'carry', 'carry')] },
  LB: { key: 'LB', title: 'Lower B', type: 'strength', slots: [s('A', 'hinge', 'main'), s('B', 'squat', 'main'), s('C', 'lunge', 'acc'), s('D1', 'kneeExt', 'acc', 'D'), s('D2', 'glute', 'acc', 'D'), s('E', 'antiRot', 'core'), s('F', 'calves', 'acc'), s('G', 'carry', 'carry')] },
  PUSH: { key: 'PUSH', title: 'Push', type: 'strength', slots: [s('A', 'hpush', 'main'), s('B', 'vpush', 'main'), s('C', 'hpush', 'acc'), s('D1', 'lat', 'acc', 'D'), s('D2', 'ext', 'acc', 'D'), s('E', 'fly', 'acc'), s('F', 'antiExt', 'core')] },
  PULL: { key: 'PULL', title: 'Pull', type: 'strength', slots: [s('A', 'vpull', 'main'), s('B', 'hpull', 'main'), s('C', 'hpull', 'acc'), s('D1', 'rear', 'acc', 'D'), s('D2', 'curl', 'acc', 'D'), s('E', 'carry', 'carry')] },
  LEGS: { key: 'LEGS', title: 'Legs', type: 'strength', slots: [s('A', 'squat', 'main'), s('B', 'hinge', 'main'), s('C', 'lunge', 'acc'), s('D1', 'kneeFlex', 'acc', 'D'), s('D2', 'kneeExt', 'acc', 'D'), s('E', 'calves', 'acc'), s('F', 'flex', 'core'), s('G', 'antiRot', 'core')] },
  CARDIO: { key: 'CARDIO', title: 'Steady cardio + core', type: 'cardio', slots: [s('1', 'cardio', 'steady'), s('2', 'flex', 'core'), s('3', 'antiExt', 'core'), s('4', 'antiRot', 'core'), s('5', 'mobility', 'mobility')] },
  COND: { key: 'COND', title: 'Athletic power + intervals', type: 'conditioning', slots: [s('1', 'power', 'power'), s('2', 'power', 'power'), s('3a', 'hinge', 'power', 'C'), s('3b', 'carry', 'carry', 'C'), s('4', 'cardio', 'interval')] },
};

const SPLITS: Record<Goal, Record<number, string[]>> = {
  fat_loss: { 1: ['FB_A'], 2: ['FB_A', 'FB_B'], 3: ['FB_A', 'FB_B', 'FB_C'], 4: ['FB_A', 'CARDIO', 'FB_B', 'FB_C'], 5: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C'], 6: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C', 'CARDIO'] },
  lean: { 1: ['FB_A'], 2: ['FB_A', 'FB_B'], 3: ['FB_A', 'FB_B', 'FB_C'], 4: ['FB_A', 'COND', 'FB_B', 'FB_C'], 5: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C'], 6: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C', 'CARDIO'] },
  muscle: { 1: ['FB_A'], 2: ['FB_A', 'FB_B'], 3: ['FB_A', 'FB_B', 'FB_C'], 4: ['UA', 'LA', 'UB', 'LB'], 5: ['UA', 'LA', 'PUSH', 'PULL', 'LEGS'], 6: ['PUSH', 'PULL', 'LEGS', 'PUSH', 'PULL', 'LEGS'] },
  strength: { 1: ['FB_C'], 2: ['FB_A', 'FB_C'], 3: ['FB_A', 'FB_B', 'FB_C'], 4: ['UA', 'LA', 'UB', 'LB'], 5: ['UA', 'LA', 'UB', 'LB', 'FB_C'], 6: ['UA', 'LA', 'UB', 'LB', 'UA', 'LB'] },
  general: { 1: ['FB_A'], 2: ['FB_A', 'FB_B'], 3: ['FB_A', 'CARDIO', 'FB_B'], 4: ['FB_A', 'CARDIO', 'FB_B', 'FB_C'], 5: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C'], 6: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C', 'CARDIO'] },
};

export const SLOTS_FOR_MINUTES: Record<number, number> = { 30: 4, 45: 5, 60: 6, 75: 7, 90: 8 };

export interface GenInput {
  goal: Goal;
  experience: Experience;
  days: Weekday[];
  sessionMin: number;
  equipment: readonly string[];
  library: Exercise[];
}

export interface GenExercise {
  slot: string;
  exerciseId: string;
  swapExerciseId?: string;
  supersetGroup?: string;
  sets: number;
  repsMin: number;
  repsMax: number;
  unit: Unit;
  perSide: boolean;
  restSec: number;
  cue?: string;
}
export interface GenDay {
  weekday: Weekday;
  type: DayType;
  title: string;
  durationMin?: number;
  notes?: string;
  exercises: GenExercise[];
}

interface Presc {
  sets: number;
  repsMin: number;
  repsMax: number;
  restSec: number;
}

export function prescription(goal: Goal, exp: Experience, role: Role, unit: Unit, sessionMin: number): Presc {
  const beginner = exp === 'beginner';
  if (role === 'steady') return { sets: 1, repsMin: sessionMin <= 45 ? 20 : 30, repsMax: sessionMin <= 45 ? 20 : 30, restSec: 0 };
  if (role === 'mobility') return { sets: 1, repsMin: 8, repsMax: 8, restSec: 0 };
  if (role === 'interval') return { sets: 6, repsMin: 30, repsMax: 30, restSec: 90 };
  if (role === 'power') return { sets: beginner ? 3 : 4, repsMin: 5, repsMax: 6, restSec: 60 };
  if (role === 'carry') return unit === 'meters' ? { sets: 3, repsMin: 30, repsMax: 30, restSec: 60 } : { sets: 3, repsMin: 30, repsMax: 40, restSec: 60 };
  if (role === 'core') {
    if (unit === 'seconds') return beginner ? { sets: 2, repsMin: 20, repsMax: 30, restSec: 45 } : { sets: 3, repsMin: 30, repsMax: 45, restSec: 45 };
    return { sets: beginner ? 2 : 3, repsMin: 10, repsMax: 15, restSec: 45 };
  }
  const main = role === 'main';
  switch (goal) {
    case 'strength':
      return main ? { sets: beginner ? 3 : 4, repsMin: beginner ? 6 : 4, repsMax: beginner ? 8 : 6, restSec: 150 } : { sets: 3, repsMin: 8, repsMax: 10, restSec: 75 };
    case 'muscle':
      return main ? { sets: beginner ? 3 : 4, repsMin: 8, repsMax: 12, restSec: 90 } : { sets: beginner ? 2 : 3, repsMin: 10, repsMax: 15, restSec: 60 };
    case 'general':
      return main ? { sets: 3, repsMin: 8, repsMax: 12, restSec: 75 } : { sets: 2, repsMin: 10, repsMax: 15, restSec: 45 };
    default: // fat_loss, lean
      return main ? { sets: 3, repsMin: 8, repsMax: 10, restSec: 75 } : { sets: beginner ? 2 : 3, repsMin: 10, repsMax: 12, restSec: 45 };
  }
}

/** Variants that confuse more than they help in a generated plan (still available to pick by hand). */
const ODD_VARIANT = /exercise ball|stability ball|bosu|\(v\d\)|arm blaster|stork|throw down|pov|on knees|towel|wall\)|one leg|single leg platform|twisting|lying femoral|rotary|donkey|self assisted|kneeling jump|pirate|side lying/i;
/** Plain gym staples for the isolation patterns. */
const STAPLE = /^(machine (lying|seated) leg curl|machine leg extension|machine standing calf raise|dumbbell standing calf raise|bodyweight standing calf raise|machine seated calf raise|dumbbell fly|cable middle fly|machine seated fly|barbell glute bridge|glute bridge two legs on bench|cable standing hip extension|dumbbell incline fly)$/i;

const TARGET_LEVEL: Record<Experience, number> = { beginner: 2, intermediate: 3, advanced: 4 };
const MAX_LEVEL: Record<Experience, number> = { beginner: 3, intermediate: 4, advanced: 5 };

function candidatesFor(lib: Exercise[], p: PKey, role: Role, exp: Experience, equipment: readonly string[]): Exercise[] {
  const wantUnit: Unit | undefined = role === 'steady' ? 'minutes' : role === 'interval' ? 'seconds' : undefined;
  const target = TARGET_LEVEL[exp];
  let list = lib.filter((e) => e.pattern === P[p] && isAvailable(e, equipment) && (e.level ?? target) <= MAX_LEVEL[exp]);
  if (wantUnit) {
    const exact = list.filter((e) => e.defaultUnit === wantUnit);
    if (exact.length) list = exact;
  } else if (role === 'main' || role === 'acc' || role === 'power') {
    const reps = list.filter((e) => e.defaultUnit === 'reps');
    if (reps.length) list = reps;
  }
  // main lifts: prefer loaded, proven compound movements (the library's "parent" exercises carry alternates).
  // The 3D dataset fills patterns the curated list lacks; prefer its plain gym staples over odd variants.
  const score = (e: Exercise) =>
    Math.abs((e.level ?? target) - target) +
    (role === 'main' && e.isBodyweight ? 1.5 : 0) -
    ((role === 'main' || role === 'acc') && e.alternates?.length ? 1 : 0) +
    (role === 'main' && /assisted|machine|back extension|hyperextension/i.test(e.name) ? 0.75 : 0) +
    (e.source === 'dataset' ? 1.5 : 0) +
    (ODD_VARIANT.test(e.name) ? 3 : 0) -
    (STAPLE.test(e.name) ? 2 : 0) +
    (role === 'main' && /pullover/i.test(e.name) ? 2 : 0);
  return [...list].sort((a, b) => score(a) - score(b) || a.name.localeCompare(b.name));
}

export function generateProgram(input: GenInput): { name: string; days: GenDay[] } {
  const chosen = [...new Set(input.days)].sort((a, b) => WEEKDAYS.indexOf(a) - WEEKDAYS.indexOf(b));
  const n = Math.min(6, Math.max(1, chosen.length || 3));
  const split = SPLITS[input.goal][n];
  const maxSlots = SLOTS_FOR_MINUTES[input.sessionMin] ?? 6;
  const variant = new Map<string, number>();
  const usedWeek = new Map<string, number>();
  const days: GenDay[] = [];

  chosen.slice(0, n).forEach((wd, i) => {
    const t = T[split[i % split.length]];
    const exercises: GenExercise[] = [];
    const usedToday = new Set<string>();
    const slots = t.type === 'strength' ? t.slots.slice(0, maxSlots) : t.slots.slice(0, Math.max(3, maxSlots - 1));
    for (const sl of slots) {
      const cands = candidatesFor(input.library, sl.p, sl.role, input.experience, input.equipment).filter((c) => !usedToday.has(c.id));
      if (!cands.length) continue;
      const v = variant.get(`${sl.p}:${sl.role}`) ?? 0;
      variant.set(`${sl.p}:${sl.role}`, v + 1);
      // prefer exercises not used yet this week for variety (main lifts may repeat across days)
      const fresh = sl.role === 'main' ? cands : cands.filter((c) => !usedWeek.has(c.id));
      const pool = fresh.length ? fresh : cands;
      const pick = pool[v % pool.length];
      usedToday.add(pick.id);
      usedWeek.set(pick.id, (usedWeek.get(pick.id) ?? 0) + 1);
      const swap = cands.find((c) => c.id !== pick.id && c.equipment.join() !== pick.equipment.join()) ?? cands.find((c) => c.id !== pick.id);
      const unit: Unit = sl.role === 'steady' ? 'minutes' : sl.role === 'interval' ? 'seconds' : pick.defaultUnit;
      const pr = prescription(input.goal, input.experience, sl.role, unit, input.sessionMin);
      exercises.push({
        slot: sl.slot,
        exerciseId: pick.id,
        swapExerciseId: swap?.id,
        supersetGroup: sl.group,
        sets: pr.sets,
        repsMin: pr.repsMin,
        repsMax: pr.repsMax,
        unit,
        perSide: /single|one-arm|one arm|lunge|split squat|step-?up|side plank|bulgarian|suitcase/i.test(pick.name),
        restSec: pr.restSec,
        cue: pick.cue,
      });
    }
    // superset partners must both exist; otherwise drop the group label
    for (const e of exercises) if (e.supersetGroup && exercises.filter((x) => x.supersetGroup === e.supersetGroup).length < 2) e.supersetGroup = undefined;
    days.push({ weekday: wd, type: t.type, title: t.title, durationMin: input.sessionMin, exercises });
  });

  // non-training days: rest, with one active-recovery day for fat loss / lean / general
  const free = WEEKDAYS.filter((w) => !days.some((d) => d.weekday === w));
  const recovery = input.goal === 'muscle' || input.goal === 'strength' ? undefined : free.includes('SUN') ? 'SUN' : free[free.length - 1];
  for (const w of free)
    days.push(
      w === recovery
        ? { weekday: w, type: 'active_recovery', title: 'Active recovery', notes: '30–45 min brisk walk + 10 min mobility.', exercises: [] }
        : { weekday: w, type: 'rest', title: 'Rest', notes: 'Aim for 7,000+ steps.', exercises: [] },
    );
  days.sort((a, b) => WEEKDAYS.indexOf(a.weekday) - WEEKDAYS.indexOf(b.weekday));
  const g = GOALS.find((x) => x.id === input.goal)!;
  return { name: `${g.label} · ${n} day${n > 1 ? 's' : ''}`, days };
}
