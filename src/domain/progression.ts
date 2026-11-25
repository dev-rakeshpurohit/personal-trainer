import type { Exercise, PlannedExercise, SetLog, Unit } from './types';

export type Equip = 'dumbbell' | 'barbell' | 'machine';

/** Map an exercise's equipment/name onto an increment bucket. */
export function equipmentBucket(ex: Pick<Exercise, 'equipment' | 'name'>): Equip {
  const all = [...ex.equipment, ex.name].join(' ').toLowerCase();
  if (/trap.?bar|barbell|e-z/.test(all)) return 'barbell';
  if (/machine|cable|leg press|pulldown|smith/.test(all)) return 'machine';
  return 'dumbbell';
}

export interface StepCfg {
  dumbbell: number;
  barbell: number;
  machine: number;
}
export const incrementFor = (ex: Pick<Exercise, 'equipment' | 'name'>, step: StepCfg): number =>
  step[equipmentBucket(ex)];

type WorkSet = Pick<SetLog, 'weightKg' | 'reps' | 'seconds' | 'meters' | 'rir' | 'setIndex'>;
/** History for one exercise: past sessions' working sets, most recent session first. */
export type History = WorkSet[][];

export type SuggestionKind = 'first' | 'increase' | 'hold' | 'decrease' | 'time_increase' | 'time_cap';

export interface Prefill {
  weightKg?: number;
  reps?: number;
  seconds?: number;
  meters?: number;
}

export interface Suggestion {
  kind: SuggestionKind;
  weightKg?: number;
  message: string;
  prefill: Prefill[];
}

export const SECONDS_CAP = 60;

const maxWeight = (sets: WorkSet[]): number | undefined => {
  const ws = sets.map((s) => s.weightKg).filter((w): w is number => w != null && w > 0);
  return ws.length ? Math.max(...ws) : undefined;
};

const valueOf = (s: WorkSet, unit: Unit): number | undefined =>
  unit === 'reps' ? s.reps : unit === 'meters' ? s.meters : s.seconds != null ? (unit === 'minutes' ? s.seconds / 60 : s.seconds) : undefined;

function bySetIndex(sets: WorkSet[], i: number): WorkSet | undefined {
  return [...sets].sort((a, b) => a.setIndex - b.setIndex)[i];
}

export function readyToProgress(
  sets: WorkSet[],
  planned: Pick<PlannedExercise, 'sets' | 'repsMax' | 'unit'>,
  targetRir?: number,
): boolean {
  if (sets.length < planned.sets || sets.length === 0) return false;
  return sets.every((s) => {
    const v = valueOf(s, planned.unit) ?? 0;
    const rirOk = s.rir == null || targetRir == null || s.rir >= targetRir;
    return v >= planned.repsMax && rirOk;
  });
}

/**
 * Double progression (doc 06 §2). Pure.
 * `sets` is the planned set count *for this session* (already deload-adjusted).
 */
export function suggestNext(args: {
  planned: Pick<PlannedExercise, 'sets' | 'repsMin' | 'repsMax' | 'unit'>;
  sets: number;
  history: History;
  targetRir?: number;
  increment: number;
  bodyweight?: boolean;
}): Suggestion {
  const { planned, history, targetRir, increment, bodyweight } = args;
  const n = args.sets;
  const last = history[0];
  const unit = planned.unit;
  const fill = (f: (i: number) => Prefill): Prefill[] => Array.from({ length: n }, (_, i) => f(i));

  if (!last || last.length === 0) {
    return {
      kind: 'first',
      message: 'First time: pick a weight you could lift for a couple more reps.',
      prefill: fill(() =>
        unit === 'reps'
          ? { reps: planned.repsMin }
          : unit === 'meters'
            ? { meters: planned.repsMin }
            : { seconds: unit === 'minutes' ? planned.repsMin * 60 : planned.repsMin },
      ),
    };
  }

  const lastW = bodyweight ? undefined : maxWeight(last);

  if (unit === 'seconds') {
    const allHit = last.length >= planned.sets && last.every((s) => (s.seconds ?? 0) >= planned.repsMax);
    const best = Math.max(...last.map((s) => s.seconds ?? 0), planned.repsMin);
    if (allHit) {
      if (best >= SECONDS_CAP)
        return {
          kind: 'time_cap',
          weightKg: lastW,
          message: `You own ${SECONDS_CAP}s. Try a harder variant.`,
          prefill: fill(() => ({ seconds: SECONDS_CAP, weightKg: lastW })),
        };
      const next = Math.min(SECONDS_CAP, Math.max(best, planned.repsMax) + 5);
      return {
        kind: 'time_increase',
        weightKg: lastW,
        message: `↑ Hold ${next}s`,
        prefill: fill(() => ({ seconds: next, weightKg: lastW })),
      };
    }
    return {
      kind: 'hold',
      weightKg: lastW,
      message: 'Same time, add a few seconds where you can.',
      prefill: fill((i) => ({ seconds: bySetIndex(last, i)?.seconds ?? planned.repsMin, weightKg: lastW })),
    };
  }

  if (unit === 'minutes' || unit === 'meters') {
    return {
      kind: 'hold',
      weightKg: lastW,
      message: 'Match last time.',
      prefill: fill((i) => {
        const s = bySetIndex(last, i);
        return unit === 'minutes'
          ? { seconds: s?.seconds ?? planned.repsMin * 60, weightKg: lastW }
          : { meters: s?.meters ?? planned.repsMin, weightKg: lastW };
      }),
    };
  }

  // reps
  if (readyToProgress(last, planned, targetRir)) {
    if (lastW != null) {
      const w = lastW + increment;
      return {
        kind: 'increase',
        weightKg: w,
        message: `↑ Try ${fmt(w)} kg`,
        prefill: fill(() => ({ weightKg: w, reps: planned.repsMin })),
      };
    }
    return {
      kind: 'hold',
      message: 'Top of the range: slow the tempo or try a harder variant.',
      prefill: fill(() => ({ reps: planned.repsMax })),
    };
  }

  const prev = history[1];
  const under = (sets: WorkSet[] | undefined) => !!sets?.length && sets.some((s) => (s.reps ?? 0) < planned.repsMin);
  if (under(last) && under(prev) && lastW != null) {
    const w = Math.max(0, lastW - increment);
    return {
      kind: 'decrease',
      weightKg: w,
      message: `Ease off: ${fmt(w)} kg and own the reps`,
      prefill: fill((i) => ({ weightKg: w, reps: Math.max(planned.repsMin, bySetIndex(last, i)?.reps ?? planned.repsMin) })),
    };
  }

  const sorted = [...last].sort((a, b) => a.setIndex - b.setIndex);
  let lowest = 0;
  sorted.forEach((s, i) => {
    if ((s.reps ?? 0) < (sorted[lowest].reps ?? 0)) lowest = i;
  });
  return {
    kind: 'hold',
    weightKg: lastW,
    message: `Same weight, aim +1 rep on set ${lowest + 1}`,
    prefill: fill((i) => ({
      weightKg: lastW,
      reps: Math.min(planned.repsMax, (bySetIndex(last, i)?.reps ?? planned.repsMin) + (i === lowest ? 1 : 0)),
    })),
  };
}

const fmt = (w: number) => (Number.isInteger(w) ? String(w) : w.toFixed(1));

/** Epley estimated 1RM; only valid for 1–12 reps. */
export function e1rm(weightKg: number | undefined, reps: number | undefined): number | undefined {
  if (!weightKg || !reps || reps < 1 || reps > 12) return undefined;
  return weightKg * (1 + reps / 30);
}

export type PRType = 'weight' | 'e1rm' | 'reps';

/** Detect PRs for a newly completed set against all prior sets of the same exercise. */
export function detectPRs(
  set: Pick<SetLog, 'weightKg' | 'reps'>,
  prior: Pick<SetLog, 'weightKg' | 'reps'>[],
): PRType[] {
  if (!prior.length || !set.weightKg || !set.reps) return [];
  const out: PRType[] = [];
  const maxW = Math.max(0, ...prior.map((p) => p.weightKg ?? 0));
  if (set.weightKg > maxW) out.push('weight');
  const best = Math.max(0, ...prior.map((p) => e1rm(p.weightKg, p.reps) ?? 0));
  const mine = e1rm(set.weightKg, set.reps);
  if (mine && best > 0 && mine > best + 1e-9) out.push('e1rm');
  const sameW = prior.filter((p) => p.weightKg === set.weightKg);
  if (sameW.length && set.reps > Math.max(...sameW.map((p) => p.reps ?? 0))) out.push('reps');
  return out;
}

export const volume = (sets: Pick<SetLog, 'weightKg' | 'reps' | 'isWarmup'>[]): number =>
  sets.filter((s) => !s.isWarmup).reduce((a, s) => a + (s.weightKg ?? 0) * (s.reps ?? 0), 0);
