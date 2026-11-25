import seed from '../../seed/program.lean-athletic-v2.json';
import { adaptFromFeedback, buildSessionPlan, estimateMinutes, hiitLevel, isInterval, targetsForUnit } from './sessionPlan';
import type { PlannedExercise, SessionFeedback } from './types';

const plannedFor = (weekday: string): PlannedExercise[] =>
  (seed.days.find((d) => d.weekday === weekday)!.exercises ?? []).map((e, i) => ({
    id: `p${i}`, dayId: weekday, order: i, slot: e.slot, exerciseId: e.name, supersetGroup: 'supersetGroup' in e ? (e.supersetGroup as string) : undefined,
    sets: e.target.sets, repsMin: e.target.repsMin, repsMax: e.target.repsMax, unit: e.target.unit as PlannedExercise['unit'], perSide: e.target.perSide, restSec: e.restSec,
  }));
const fb = (p: Partial<SessionFeedback>): SessionFeedback => ({ rpe: 7, feel: 'just_right', pain: [], disliked: [], ranOutOfTime: false, ...p });

describe('session plan', () => {
  it('full strength day keeps everything, flags A/B as main lifts', () => {
    const plan = buildSessionPlan({ planned: plannedFor('TUE'), dayType: 'strength', mode: 'full', deload: false, fallbackRir: 2 });
    expect(plan).toHaveLength(6);
    expect(plan.filter((p) => p.isMain).map((p) => p.slot)).toEqual(['A1', 'A2', 'B1', 'B2']);
    expect(plan[0].rir).toBe(2);
  });
  it('express strength keeps A/B slots, 2 sets, shorter rest, ~40 min', () => {
    const plan = buildSessionPlan({ planned: plannedFor('TUE'), dayType: 'strength', mode: 'express', deload: false });
    expect(plan.map((p) => p.slot)).toEqual(['A1', 'A2', 'B1', 'B2']);
    expect(plan.every((p) => p.sets === 2 && p.restSec <= 90)).toBe(true);
    expect(estimateMinutes(plan)).toBeLessThanOrEqual(40);
    expect(estimateMinutes(buildSessionPlan({ planned: plannedFor('TUE'), dayType: 'strength', mode: 'full', deload: false }))).toBeGreaterThan(40);
  });
  it('express cardio day shortens steady cardio and keeps 2 core moves', () => {
    const plan = buildSessionPlan({ planned: plannedFor('WED'), dayType: 'cardio', mode: 'express', deload: false });
    expect(plan).toHaveLength(3);
    expect(plan[0].repsMax).toBe(20);
  });
  it('deload halves sets after everything else', () => {
    const plan = buildSessionPlan({ planned: plannedFor('TUE'), dayType: 'strength', mode: 'full', deload: true });
    expect(plan[0].sets).toBe(2);
  });
  it('HIIT ramp: beginner level 1 = 4 × 20 s intervals and fewer sets', () => {
    const fri = plannedFor('FRI');
    expect(isInterval(fri[5])).toBe(true);
    const l1 = buildSessionPlan({ planned: fri, dayType: 'conditioning', mode: 'full', deload: false, hiit: 1 });
    const bike = l1.find((p) => p.slot === '4')!;
    expect([bike.sets, bike.repsMax, bike.restSec]).toEqual([4, 20, 120]);
    expect(l1.find((p) => p.slot === '1')!.sets).toBe(3);
    expect(l1.find((p) => p.slot === '3a')!.sets).toBe(2);
    const l3 = buildSessionPlan({ planned: fri, dayType: 'conditioning', mode: 'full', deload: false, hiit: 3 });
    expect(l3.find((p) => p.slot === '4')!.sets).toBe(6);
  });
  it('HIIT level ramps every 2 good sessions and steps back after a too-hard one', () => {
    expect(hiitLevel([])).toBe(1);
    expect(hiitLevel([{}, {}])).toBe(2);
    expect(hiitLevel([{}, {}, {}, {}])).toBe(3);
    expect(hiitLevel([{ feel: 'too_hard' }, {}, {}, {}])).toBe(1);
  });
  it('periodization: week 5 adds 1 accessory set (not to main lifts)', () => {
    const week = { week: 5, rirMain: 1, rirAccessory: 2, focus: '', note: '', setsDelta: 1, deload: false };
    const plan = buildSessionPlan({ planned: plannedFor('TUE'), dayType: 'strength', mode: 'full', deload: false, week });
    expect(plan[0].sets).toBe(4);
    expect(plan[4].sets).toBe(4);
    expect(plan[0].rir).toBe(1);
    expect(plan[4].rir).toBe(2);
  });
  it('today-only swaps replace the exercise id but keep the original', () => {
    const plan = buildSessionPlan({ planned: plannedFor('TUE'), dayType: 'strength', mode: 'full', deload: false, swaps: { p1: 'floor' } });
    expect(plan[1].exerciseId).toBe('floor');
    expect(plan[1].originalExerciseId).toBe('Dumbbell bench press');
  });
  it('unit change gets sensible default targets', () => {
    expect(targetsForUnit({ unit: 'seconds', repsMin: 30, repsMax: 45 }, 'reps')).toEqual({ repsMin: 8, repsMax: 12, unit: 'reps' });
  });
});

describe('feedback adaptation', () => {
  it('too hard → hold progression and trim accessories', () => {
    const a = adaptFromFeedback([fb({ feel: 'too_hard', rpe: 9 })]);
    expect(a.holdProgression).toBe(true);
    expect(a.accessorySetsDelta).toBe(-1);
    const plan = buildSessionPlan({ planned: plannedFor('TUE'), dayType: 'strength', mode: 'full', deload: false, adaptation: a });
    expect(plan[4].sets).toBe(2);
    expect(plan[0].sets).toBe(4);
  });
  it('two easy sessions → +1 accessory set', () => {
    expect(adaptFromFeedback([fb({ feel: 'too_easy' }), fb({ rpe: 5 })]).accessorySetsDelta).toBe(1);
    expect(adaptFromFeedback([fb({ feel: 'too_easy' })]).accessorySetsDelta).toBe(0);
  });
  it('ran out of time → prefer express; pain is carried forward', () => {
    const a = adaptFromFeedback([fb({ ranOutOfTime: true, pain: ['x'] })]);
    expect(a.preferExpress).toBe(true);
    expect(a.pain).toEqual(['x']);
  });
});
