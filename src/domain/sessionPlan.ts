/**
 * Builds the concrete exercise list for a session (pure):
 * periodization (RIR per week, deload, accessory set bumps), Express mode, gradual HIIT ramp for
 * conditioning days, and adaptations from previous feedback. See docs/09-RESEARCH.md + DECISIONS.md.
 */
import type { DayType, Feel, PlannedExercise, SessionExercise, SessionFeedback, SessionMode, Unit, WeekFocus } from './types';
import { deloadSets } from './schedule';

export const isMainSlot = (slot: string, dayType: DayType) => dayType === 'strength' && /^[AB]/i.test(slot);

/** Intervals: timed, ≥ 4 rounds, not part of a circuit (e.g. "30 s hard / 90 s easy × 6"). */
export const isInterval = (pe: Pick<PlannedExercise, 'unit' | 'sets' | 'supersetGroup'>) => pe.unit === 'seconds' && pe.sets >= 4 && !pe.supersetGroup;

/** HIIT ramp level 1–3 from completed conditioning sessions (beginner-friendly start). */
export function hiitLevel(history: { feel?: Feel }[]): 1 | 2 | 3 {
  const good = history.filter((h) => h.feel !== 'too_hard').length;
  let level = Math.min(3, 1 + Math.floor(good / 2)) as 1 | 2 | 3;
  if (history[0]?.feel === 'too_hard') level = Math.max(1, level - 1) as 1 | 2 | 3;
  return level;
}

export interface Adaptation {
  holdProgression: boolean;
  accessorySetsDelta: number;
  preferExpress: boolean;
  pain: string[];
  reasons: string[];
}

/** Adapt the next session of a program day from its recent feedback (latest first). */
export function adaptFromFeedback(recent: SessionFeedback[]): Adaptation {
  const a: Adaptation = { holdProgression: false, accessorySetsDelta: 0, preferExpress: false, pain: [], reasons: [] };
  const last = recent[0];
  if (!last) return a;
  if (last.feel === 'too_hard' || last.rpe >= 9) {
    a.holdProgression = true;
    a.accessorySetsDelta = -1;
    a.reasons.push('Last time felt very hard: holding weights and trimming 1 accessory set.');
  } else if (recent.length >= 2 && recent.slice(0, 2).every((f) => f.feel === 'too_easy' || f.rpe <= 5)) {
    a.accessorySetsDelta = 1;
    a.reasons.push('Two easy sessions in a row: +1 set on accessories.');
  }
  if (last.ranOutOfTime) {
    a.preferExpress = true;
    a.reasons.push('You ran out of time last time: Express mode suggested.');
  }
  if (last.energy === 'low' && !a.holdProgression) a.reasons.push('Low energy last time: sleep and protein first.');
  a.pain = [...new Set(last.pain)];
  if (a.pain.length) a.reasons.push('Pain reported last time: consider the alternate and keep the weight.');
  return a;
}

export interface BuildArgs {
  planned: PlannedExercise[];
  dayType: DayType;
  mode: SessionMode;
  deload: boolean;
  week?: WeekFocus;
  fallbackRir?: number;
  hiit?: 1 | 2 | 3;
  adaptation?: Adaptation;
  /** exercise overrides for today: plannedExerciseId → exerciseId */
  swaps?: Record<string, string>;
}

const minutesExpress = (n: number) => Math.max(10, Math.round((n * 2) / 3 / 5) * 5);

export function buildSessionPlan(a: BuildArgs): SessionExercise[] {
  let list = [...a.planned].sort((x, y) => x.order - y.order);

  // Express (~40 min): keep the essentials (doc 09)
  if (a.mode === 'express') {
    if (a.dayType === 'strength') {
      const ab = list.filter((p) => /^[AB]/i.test(p.slot));
      list = ab.length ? ab : list.slice(0, 4);
    } else if (a.dayType === 'conditioning') {
      list = list.filter((p) => !p.supersetGroup);
    } else if (a.dayType === 'cardio') {
      const steady = list.filter((p) => p.unit === 'minutes').slice(0, 1);
      const core = list.filter((p) => p.unit !== 'minutes').slice(0, 2);
      list = [...steady, ...core];
    } else list = list.slice(0, 4);
  }

  return list.map((p) => {
    const main = isMainSlot(p.slot, a.dayType);
    let sets = p.sets;
    let repsMin = p.repsMin;
    let repsMax = p.repsMax;
    let restSec = p.restSec;
    const notes: string[] = [];

    // Gradual HIIT ramp on conditioning days
    if (a.dayType === 'conditioning' && a.hiit && a.hiit < 3) {
      if (isInterval(p)) {
        sets = a.hiit === 1 ? Math.min(sets, 4) : Math.min(sets, 5);
        const secs = a.hiit === 1 ? 20 : 25;
        repsMin = Math.min(repsMin, secs);
        repsMax = Math.min(repsMax, secs);
        restSec = restSec + (a.hiit === 1 ? 30 : 15);
        notes.push(`Ramp level ${a.hiit}/3: ${sets} × ${repsMax}s, easy pace between.`);
      } else if (p.supersetGroup) {
        sets = Math.min(sets, a.hiit === 1 ? 2 : 3);
      } else {
        sets = Math.min(sets, 3);
      }
    }

    // Accessory set bumps (periodization + feedback), full mode only
    if (!main && a.mode === 'full' && !a.deload) {
      const bump = (a.week?.setsDelta ?? 0) + (a.adaptation?.accessorySetsDelta ?? 0);
      if (bump) sets = Math.max(2, Math.min(p.sets + 1, sets + bump));
    }

    if (a.mode === 'express') {
      sets = Math.min(sets, a.dayType === 'conditioning' ? 3 : 2);
      if (p.unit === 'minutes') {
        repsMin = minutesExpress(repsMin);
        repsMax = minutesExpress(repsMax);
      }
      if (isInterval(p)) sets = Math.min(sets, 4);
      restSec = Math.min(restSec, main ? 90 : 45);
    }
    if (a.deload) sets = deloadSets(sets);
    const rir = a.week ? (main ? a.week.rirMain : a.week.rirAccessory) : a.fallbackRir;

    return {
      plannedExerciseId: p.id,
      exerciseId: a.swaps?.[p.id] ?? p.exerciseId,
      originalExerciseId: p.exerciseId,
      slot: p.slot,
      supersetGroup: p.supersetGroup,
      sets: Math.max(1, sets),
      repsMin,
      repsMax,
      unit: p.unit,
      perSide: p.perSide,
      restSec,
      rir: p.unit === 'reps' ? rir : undefined,
      isMain: main,
      cue: p.cue,
      note: notes.join(' ') || undefined,
    };
  });
}

/** Default targets when an alternate uses a different unit from the planned slot. */
export function targetsForUnit(se: Pick<SessionExercise, 'unit' | 'repsMin' | 'repsMax'>, unit: Unit): { repsMin: number; repsMax: number; unit: Unit } {
  if (unit === se.unit) return { repsMin: se.repsMin, repsMax: se.repsMax, unit };
  if (unit === 'reps') return { repsMin: 8, repsMax: 12, unit };
  if (unit === 'seconds') return { repsMin: 20, repsMax: 40, unit };
  if (unit === 'meters') return { repsMin: 20, repsMax: 30, unit };
  return { repsMin: 10, repsMax: 20, unit };
}

export function estimateMinutes(plan: Pick<SessionExercise, 'sets' | 'restSec' | 'unit' | 'repsMax' | 'supersetGroup'>[]): number {
  let sec = 300; // warm-up
  for (const e of plan) {
    const work = e.unit === 'minutes' ? e.repsMax * 60 : e.unit === 'seconds' ? e.repsMax : 40;
    sec += e.sets * (work + e.restSec + 15);
  }
  return Math.round(sec / 60 / 5) * 5;
}
