import { cycleWeek, deloadSets, effectiveSets, getDayPlan, isDeloadWeek, targetRir, weekdayOf, dayKey } from './schedule';
import type { CycleEntry } from './types';

const cycle: CycleEntry[] = [
  { weeks: [1, 2], rir: 3 },
  { weeks: [3, 4, 5, 6, 7], rir: 2 },
  { weeks: [8], rir: 3, deload: true },
];

describe('schedule', () => {
  it('maps dates to weekdays', () => {
    expect(weekdayOf(new Date(2026, 11, 1))).toBe('TUE');
    expect(weekdayOf(new Date(2026, 10, 29))).toBe('SUN');
    expect(weekdayOf(new Date(2026, 10, 30))).toBe('MON');
  });
  it('finds the day plan or undefined for rest', () => {
    const days = [{ weekday: 'TUE' as const, title: 'A' }];
    expect(getDayPlan(days, new Date(2026, 11, 1))?.title).toBe('A');
    expect(getDayPlan(days, new Date(2026, 11, 2))).toBeUndefined();
  });
  it('computes the 8-week cycle', () => {
    expect(cycleWeek(new Date(2026, 0, 1), '2026-01-01')).toBe(1);
    expect(cycleWeek(new Date(2026, 0, 7), '2026-01-01')).toBe(1);
    expect(cycleWeek(new Date(2026, 0, 8), '2026-01-01')).toBe(2);
    expect(cycleWeek(new Date(2026, 1, 19), '2026-01-01')).toBe(8);
    expect(cycleWeek(new Date(2026, 1, 26), '2026-01-01')).toBe(1);
    expect(cycleWeek(new Date(2025, 11, 1), '2026-01-01')).toBe(1);
  });
  it('flags deload and halves sets rounding up', () => {
    expect(isDeloadWeek(8, cycle)).toBe(true);
    expect(isDeloadWeek(5, cycle)).toBe(false);
    expect(targetRir(4, cycle)).toBe(2);
    expect(deloadSets(3)).toBe(2);
    expect(deloadSets(4)).toBe(2);
    expect(effectiveSets(3, false)).toBe(3);
  });
  it('formats day keys in local time', () => {
    expect(dayKey(new Date(2026, 0, 5, 23, 59))).toBe('2026-01-05');
  });
});
