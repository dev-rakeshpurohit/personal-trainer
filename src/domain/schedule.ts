import { addDays, differenceInCalendarDays, format, parseISO, startOfWeek } from 'date-fns';
import type { CycleEntry, ProgramDay, Weekday } from './types';
import { WEEKDAYS } from './types';

export const dayKey = (d: Date): string => format(d, 'yyyy-MM-dd');
export const fromDayKey = (k: string): Date => parseISO(k);

export function weekdayOf(d: Date): Weekday {
  // JS: 0 = Sunday
  return WEEKDAYS[(d.getDay() + 6) % 7];
}

export function getDayPlan<T extends Pick<ProgramDay, 'weekday'>>(days: T[], date: Date): T | undefined {
  const wd = weekdayOf(date);
  return days.find((d) => d.weekday === wd);
}

export function cycleWeek(date: Date, startedOn: string): number {
  const since = differenceInCalendarDays(date, parseISO(startedOn));
  if (since < 0) return 1;
  return (Math.floor(since / 7) % 8) + 1;
}

export function cycleEntry(week: number, cycle: CycleEntry[]): CycleEntry | undefined {
  return cycle.find((c) => c.weeks.includes(week));
}

export const isDeloadWeek = (week: number, cycle: CycleEntry[]): boolean => !!cycleEntry(week, cycle)?.deload;

export const targetRir = (week: number, cycle: CycleEntry[]): number | undefined => cycleEntry(week, cycle)?.rir;

export const deloadSets = (sets: number): number => Math.ceil(sets / 2);

export const effectiveSets = (sets: number, deload: boolean): number => (deload ? deloadSets(sets) : sets);

/** Monday- (or Sunday-) based week start for a date. */
export const weekStartOf = (d: Date, weekStart: 'mon' | 'sun' = 'mon'): Date =>
  startOfWeek(d, { weekStartsOn: weekStart === 'mon' ? 1 : 0 });

export function weekDates(d: Date, weekStart: 'mon' | 'sun' = 'mon'): Date[] {
  const s = weekStartOf(d, weekStart);
  return Array.from({ length: 7 }, (_, i) => addDays(s, i));
}
