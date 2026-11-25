import { addDays, differenceInCalendarDays, parseISO, startOfISOWeek } from 'date-fns';
import { dayKey } from './schedule';

export interface Point {
  dayKey: string;
  value: number;
}

/** 7-day trailing moving average for each point (calendar-day window, handles gaps). */
export function movingAverage7(points: Point[]): Point[] {
  const sorted = [...points].sort((a, b) => a.dayKey.localeCompare(b.dayKey));
  return sorted.map((p) => {
    const d = parseISO(p.dayKey);
    const win = sorted.filter((q) => {
      const diff = differenceInCalendarDays(d, parseISO(q.dayKey));
      return diff >= 0 && diff < 7;
    });
    return { dayKey: p.dayKey, value: win.reduce((a, q) => a + q.value, 0) / win.length };
  });
}

export interface WeeklyAvg {
  weekStart: string;
  avg?: number;
  count: number;
  valid: boolean;
  needed: number;
}

export const MIN_WEIGHINS_PER_WEEK = 4;

/** Mean of weigh-ins in the ISO week starting at weekStart (Monday). */
export function weeklyAverage(points: Point[], weekStart: Date): WeeklyAvg {
  const ws = startOfISOWeek(weekStart);
  const end = addDays(ws, 7);
  const inWeek = points.filter((p) => {
    const d = parseISO(p.dayKey);
    return d >= ws && d < end;
  });
  const count = inWeek.length;
  const valid = count >= MIN_WEIGHINS_PER_WEEK;
  return {
    weekStart: dayKey(ws),
    count,
    valid,
    needed: Math.max(0, MIN_WEIGHINS_PER_WEEK - count),
    avg: count ? inWeek.reduce((a, p) => a + p.value, 0) / count : undefined,
  };
}

/** Least-squares slope (y per x). */
export function linearSlope(xy: { x: number; y: number }[]): number | undefined {
  const n = xy.length;
  if (n < 2) return undefined;
  const mx = xy.reduce((a, p) => a + p.x, 0) / n;
  const my = xy.reduce((a, p) => a + p.y, 0) / n;
  let num = 0;
  let den = 0;
  for (const p of xy) {
    num += (p.x - mx) * (p.y - my);
    den += (p.x - mx) ** 2;
  }
  return den === 0 ? undefined : num / den;
}

export interface Rate {
  /** kg lost per week (positive = losing). */
  lossPerWeek: number;
  method: 'regression' | 'weekly';
}

/** Rate of loss (doc 06 §4): regression over last 21 days (≥10 points), else consecutive valid weekly averages. */
export function rateKgPerWeek(points: Point[], today: Date): Rate | undefined {
  const recent = points.filter((p) => {
    const diff = differenceInCalendarDays(today, parseISO(p.dayKey));
    return diff >= 0 && diff < 21;
  });
  if (recent.length >= 10) {
    const slope = linearSlope(recent.map((p) => ({ x: -differenceInCalendarDays(today, parseISO(p.dayKey)), y: p.value })));
    if (slope != null) return { lossPerWeek: -slope * 7, method: 'regression' };
  }
  const weeks = weeklyAverages(points, today, 8).filter((w) => w.valid);
  if (weeks.length >= 2) {
    const a = weeks[weeks.length - 2].avg!;
    const b = weeks[weeks.length - 1].avg!;
    return { lossPerWeek: a - b, method: 'weekly' };
  }
  return undefined;
}

/** The last `n` ISO weeks (oldest first) ending with the week containing `today`. */
export function weeklyAverages(points: Point[], today: Date, n: number): WeeklyAvg[] {
  const cur = startOfISOWeek(today);
  return Array.from({ length: n }, (_, i) => weeklyAverage(points, addDays(cur, -7 * (n - 1 - i))));
}

/** Weekly loss for each pair of consecutive valid weeks (completed weeks only), oldest first. */
export function weeklyLossChecks(points: Point[], today: Date, n = 4): number[] {
  const weeks = weeklyAverages(points, addDays(startOfISOWeek(today), -1), n + 1);
  const out: number[] = [];
  for (let i = 1; i < weeks.length; i++) {
    const a = weeks[i - 1];
    const b = weeks[i];
    if (a.valid && b.valid) out.push(a.avg! - b.avg!);
  }
  return out;
}

export function current7dAvg(points: Point[], today: Date): number | undefined {
  const win = points.filter((p) => {
    const diff = differenceInCalendarDays(today, parseISO(p.dayKey));
    return diff >= 0 && diff < 7;
  });
  return win.length ? win.reduce((a, p) => a + p.value, 0) / win.length : undefined;
}

/** Projected goal date; only when losing faster than 0.1 kg/week and above goal. */
export function projectedGoalDate(current: number | undefined, goal: number, lossPerWeek: number | undefined, today: Date): Date | undefined {
  if (current == null || lossPerWeek == null || lossPerWeek <= 0.1 || current <= goal) return undefined;
  const weeks = (current - goal) / lossPerWeek;
  return addDays(today, Math.round(weeks * 7));
}

/**
 * Training streak (doc 06 §7): consecutive *planned* training days completed, walking back from today.
 * Today counts if done; if not yet done it doesn't break the streak.
 */
export function trainingStreak(isPlanned: (d: Date) => boolean, doneDayKeys: Set<string>, today: Date, since?: Date): number {
  let streak = 0;
  for (let i = 0; i < 400; i++) {
    const d = addDays(today, -i);
    if (since && d < since) break;
    if (!isPlanned(d)) continue;
    const done = doneDayKeys.has(dayKey(d));
    if (done) streak++;
    else if (i === 0) continue;
    else break;
  }
  return streak;
}

/** Percentage change between first and last of a series (e.g. e1RM over 4 weeks). */
export function pctChange(series: number[]): number | undefined {
  if (series.length < 2 || !series[0]) return undefined;
  return ((series[series.length - 1] - series[0]) / series[0]) * 100;
}
