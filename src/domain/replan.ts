/**
 * Missed-session auto re-plan (Rakesh's request, see DECISIONS.md).
 * If a planned training day earlier this week was missed, the remaining sessions are re-flowed
 * onto the remaining training slots: missed sessions are done next, in order. If there are more
 * sessions than slots, an active-recovery day (e.g. Sunday) becomes a make-up slot for strength work,
 * and only then is the lowest-priority session (cardio → conditioning → strength) dropped.
 * Rest days (gym closed) are never used. Pure.
 */
import { addDays, isBefore, startOfDay } from 'date-fns';
import { dayKey, weekdayOf, weekDates } from './schedule';
import type { DayType, Weekday } from './types';
import { isTrainingType } from './types';

export interface PlanDay {
  id: string;
  weekday: Weekday;
  type: DayType;
  title: string;
}

export interface WeekPlan<T extends PlanDay> {
  /** What to do on each date of the week (dayKey → program day, or undefined = rest/nothing). */
  byDate: Record<string, T | undefined>;
  /** Original plan for each date, for "moved from" labels. */
  original: Record<string, T | undefined>;
  missed: { day: T; date: string }[];
  dropped: T[];
  adjusted: boolean;
}

const PRIORITY: Record<DayType, number> = { strength: 3, conditioning: 2, cardio: 1, active_recovery: 0, rest: 0 };

export function replanWeek<T extends PlanDay>(args: {
  days: T[];
  today: Date;
  /** programDayIds completed (status done) this week, with the date they were done. */
  done: { programDayId?: string; dayKey: string }[];
  weekStart?: 'mon' | 'sun';
}): WeekPlan<T> {
  const today = startOfDay(args.today);
  const dates = weekDates(today, args.weekStart ?? 'mon');
  const dayFor = (d: Date) => args.days.find((x) => x.weekday === weekdayOf(d));
  const original: Record<string, T | undefined> = {};
  dates.forEach((d) => (original[dayKey(d)] = dayFor(d)));
  const doneIds = new Set(args.done.map((x) => x.programDayId).filter(Boolean) as string[]);
  const doneToday = args.done.some((x) => x.dayKey === dayKey(today));

  const training = dates.map((d) => ({ date: d, day: dayFor(d) })).filter((x) => x.day && isTrainingType(x.day.type)) as {
    date: Date;
    day: T;
  }[];
  const missed = training.filter((x) => isBefore(x.date, today) && !doneIds.has(x.day.id));
  const upcoming = training.filter((x) => !isBefore(x.date, today) && !doneIds.has(x.day.id));

  const byDate: Record<string, T | undefined> = { ...original };
  if (!missed.length) {
    return { byDate, original, missed: [], dropped: [], adjusted: false };
  }

  // training slots from today on (today only if nothing has been done yet today)
  const slots = training
    .filter((x) => !isBefore(x.date, today))
    .filter((x) => !(doneToday && dayKey(x.date) === dayKey(today)))
    .map((x) => x.date);
  const queue = [...missed, ...upcoming].map((x) => x.day);

  // Make-up slots: active-recovery days still ahead, used only for strength that would otherwise be dropped
  const recovery = dates.filter((d) => !isBefore(d, today) && dayFor(d)?.type === 'active_recovery');
  let over = queue.length - slots.length;
  const strengthAtRisk = () => {
    const sorted = [...queue].sort((a, b) => PRIORITY[a.type] - PRIORITY[b.type]);
    return sorted.slice(0, Math.max(0, over)).some((d) => d.type === 'strength');
  };
  while (over > 0 && recovery.length && strengthAtRisk()) {
    slots.push(recovery.shift()!);
    over--;
  }
  slots.sort((a, b) => a.getTime() - b.getTime());

  const dropped: T[] = [];
  while (queue.length > slots.length) {
    // drop the lowest-priority session; ties → the later one
    let idx = 0;
    queue.forEach((d, i) => {
      if (PRIORITY[d.type] <= PRIORITY[queue[idx].type]) idx = i;
    });
    dropped.push(queue.splice(idx, 1)[0]);
  }

  // clear training days from today on, then assign the queue in order
  for (let d = today; d <= dates[6]; d = addDays(d, 1)) {
    const k = dayKey(d);
    if (original[k] && isTrainingType(original[k]!.type)) byDate[k] = undefined;
  }
  slots.forEach((d, i) => {
    if (queue[i]) byDate[dayKey(d)] = queue[i];
  });
  if (doneToday) byDate[dayKey(today)] = original[dayKey(today)];

  return { byDate, original, missed: missed.map((m) => ({ day: m.day, date: dayKey(m.date) })), dropped, adjusted: true };
}

/** Planned dates whose session was completed (on the day, or as a make-up later that week). */
export function coveredDates(days: PlanDay[], done: { programDayId?: string; dayKey: string }[], weekDatesList: Date[]): Set<string> {
  const out = new Set(done.map((d) => d.dayKey));
  for (const d of weekDatesList) {
    const p = days.find((x) => x.weekday === weekdayOf(d));
    if (p && done.some((x) => x.programDayId === p.id)) out.add(dayKey(d));
  }
  return out;
}
