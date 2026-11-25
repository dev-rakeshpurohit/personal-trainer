import { addDays } from 'date-fns';
import { dayKey } from './schedule';
import {
  current7dAvg, linearSlope, movingAverage7, pctChange, projectedGoalDate, rateKgPerWeek, trainingStreak, weeklyAverage, weeklyLossChecks,
} from './stats';

const today = new Date(2026, 11, 20); // Sunday
const series = (days: number, start: number, perDay: number, skip: (i: number) => boolean = () => false) =>
  Array.from({ length: days }, (_, i) => i)
    .filter((i) => !skip(i))
    .map((i) => ({ dayKey: dayKey(addDays(today, -(days - 1 - i))), value: start + perDay * i }));

describe('body stats', () => {
  it('weekly average needs ≥4 weigh-ins', () => {
    const pts = [0, 1, 2].map((i) => ({ dayKey: dayKey(addDays(new Date(2026, 11, 14), i)), value: 80 }));
    const w = weeklyAverage(pts, new Date(2026, 11, 14));
    expect(w.valid).toBe(false);
    expect(w.needed).toBe(1);
    pts.push({ dayKey: '2026-12-18', value: 76 });
    const w2 = weeklyAverage(pts, new Date(2026, 11, 16));
    expect(w2.valid).toBe(true);
    expect(w2.avg).toBe(79);
  });
  it('7-day moving average handles gaps', () => {
    const ma = movingAverage7([
      { dayKey: '2026-12-01', value: 80 },
      { dayKey: '2026-12-03', value: 78 },
      { dayKey: '2026-12-09', value: 76 },
    ]);
    expect(ma[1].value).toBe(79);
    expect(ma[2].value).toBe(77);
  });
  it('regression rate over 21 days', () => {
    const pts = series(21, 80, -0.1); // −0.7 kg/week
    const r = rateKgPerWeek(pts, today)!;
    expect(r.method).toBe('regression');
    expect(r.lossPerWeek).toBeCloseTo(0.7, 5);
  });
  it('falls back to weekly averages with sparse data', () => {
    const pts = series(21, 80, -0.1, (i) => i % 2 === 1); // 11 pts → still regression
    expect(rateKgPerWeek(pts, today)?.method).toBe('regression');
    const sparse = series(21, 80, -0.1, (i) => i % 3 !== 0); // 7 pts → too few
    expect(rateKgPerWeek(sparse, today)).toBeUndefined();
  });
  it('linear slope', () => {
    expect(linearSlope([{ x: 0, y: 1 }, { x: 1, y: 3 }])).toBe(2);
    expect(linearSlope([{ x: 0, y: 1 }])).toBeUndefined();
  });
  it('projects goal date only when losing > 0.1 kg/week', () => {
    expect(projectedGoalDate(79, 73, 0.6, today)).toEqual(addDays(today, 70));
    expect(projectedGoalDate(79, 73, 0.05, today)).toBeUndefined();
    expect(projectedGoalDate(72, 73, 0.6, today)).toBeUndefined();
  });
  it('current 7-day average', () => {
    expect(current7dAvg(series(10, 80, 0), today)).toBe(80);
  });
  it('weekly loss checks use completed weeks only', () => {
    const pts = series(35, 80, -0.1);
    const checks = weeklyLossChecks(pts, today);
    expect(checks.length).toBeGreaterThanOrEqual(3);
    checks.forEach((c) => expect(c).toBeCloseTo(0.7, 5));
  });
  it('pct change', () => {
    expect(pctChange([100, 110])).toBeCloseTo(10);
    expect(pctChange([100])).toBeUndefined();
  });
});

describe('training streak', () => {
  const planned = (d: Date) => d.getDay() >= 2 && d.getDay() <= 6; // Tue–Sat
  it('counts planned days done, rest days do not break it', () => {
    // today = Sun 20 Dec. Tue 15–Sat 19 done, plus Sat 12 done, Fri 11 missed
    const done = new Set(['2026-12-15', '2026-12-16', '2026-12-17', '2026-12-18', '2026-12-19', '2026-12-12']);
    expect(trainingStreak(planned, done, today)).toBe(6);
  });
  it('today not yet done does not break the streak', () => {
    const tue = new Date(2026, 11, 22);
    const done = new Set(['2026-12-19', '2026-12-18']);
    expect(trainingStreak(planned, done, tue)).toBe(2);
  });
  it('a missed planned day breaks it', () => {
    const done = new Set(['2026-12-19', '2026-12-17']);
    expect(trainingStreak(planned, done, today)).toBe(1);
  });
});
