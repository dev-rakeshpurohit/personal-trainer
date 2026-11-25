import { replanWeek, coveredDates } from './replan';
import { weekDates } from './schedule';
import type { PlanDay } from './replan';

const days: PlanDay[] = [
  { id: 'mon', weekday: 'MON', type: 'rest', title: 'Rest' },
  { id: 'A', weekday: 'TUE', type: 'strength', title: 'Strength A' },
  { id: 'cardio', weekday: 'WED', type: 'cardio', title: 'Cardio' },
  { id: 'B', weekday: 'THU', type: 'strength', title: 'Strength B' },
  { id: 'power', weekday: 'FRI', type: 'conditioning', title: 'Power' },
  { id: 'C', weekday: 'SAT', type: 'strength', title: 'Strength C' },
  { id: 'sun', weekday: 'SUN', type: 'active_recovery', title: 'Recovery' },
];
// week of Mon 30 Nov 2026
const d = (date: number) => new Date(2026, 10, 30 + date); // 0 = Mon 30 Nov
const key = (n: number) => {
  const x = d(n);
  return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
};

describe('replanWeek', () => {
  it('leaves the plan alone when nothing was missed', () => {
    const p = replanWeek({ days, today: d(2), done: [{ programDayId: 'A', dayKey: key(1) }] });
    expect(p.adjusted).toBe(false);
    expect(p.byDate[key(2)]?.id).toBe('cardio');
  });
  it('missed Tuesday strength → done Wednesday, cardio is the one dropped', () => {
    const p = replanWeek({ days, today: d(2), done: [] });
    expect(p.adjusted).toBe(true);
    expect(p.missed.map((m) => m.day.id)).toEqual(['A']);
    expect([2, 3, 4, 5].map((n) => p.byDate[key(n)]?.id)).toEqual(['A', 'B', 'power', 'C']);
    // Sunday stays recovery: only cardio had to go, so no make-up slot is needed
    expect(p.byDate[key(6)]?.type).toBe('active_recovery');
    expect(p.dropped.map((x) => x.id)).toEqual(['cardio']);
  });
  it('drops the lowest priority session when even Sunday is not enough', () => {
    // Missed Tue + Wed + Thu, today Fri
    const p = replanWeek({ days, today: d(4), done: [] });
    const assigned = [4, 5, 6].map((n) => p.byDate[key(n)]?.id);
    expect(assigned).toEqual(['A', 'B', 'C']);
    expect(p.dropped.map((x) => x.id).sort()).toEqual(['cardio', 'power']);
  });
  it('does not touch today if a session is already done today', () => {
    const p = replanWeek({ days, today: d(2), done: [{ programDayId: 'cardio', dayKey: key(2) }] });
    expect(p.byDate[key(2)]?.id).toBe('cardio');
    expect(p.byDate[key(3)]?.id).toBe('A');
  });
  it('never schedules on a rest (gym closed) day', () => {
    const p = replanWeek({ days, today: d(6), done: [] });
    expect(p.byDate[key(0)]?.type).toBe('rest');
    expect(p.byDate[key(6)]?.type).toBe('strength');
  });
  it('a make-up session covers the missed planned date for streaks', () => {
    const cov = coveredDates(days, [{ programDayId: 'A', dayKey: key(2) }], weekDates(d(2)));
    expect(cov.has(key(1))).toBe(true);
    expect(cov.has(key(2))).toBe(true);
  });
});
