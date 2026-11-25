import { detectPRs, e1rm, equipmentBucket, readyToProgress, suggestNext, volume } from './progression';

const planned = { sets: 3, repsMin: 8, repsMax: 10, unit: 'reps' as const };
const s = (weightKg: number, reps: number, setIndex: number, rir?: number) => ({ weightKg, reps, setIndex, rir });

describe('double progression', () => {
  it('suggests +increment when all sets hit the top of the range', () => {
    const r = suggestNext({ planned, sets: 3, history: [[s(14, 10, 0), s(14, 10, 1), s(14, 10, 2)]], targetRir: 2, increment: 2 });
    expect(r.kind).toBe('increase');
    expect(r.weightKg).toBe(16);
    expect(r.message).toBe('↑ Try 16 kg');
    expect(r.prefill.every((p) => p.weightKg === 16 && p.reps === 8)).toBe(true);
  });
  it('does not progress when RIR was below target', () => {
    expect(readyToProgress([s(14, 10, 0, 1), s(14, 10, 1, 2), s(14, 10, 2, 2)], planned, 2)).toBe(false);
    expect(readyToProgress([s(14, 10, 0, 2), s(14, 10, 1, 3), s(14, 10, 2)], planned, 2)).toBe(true);
  });
  it('does not progress with fewer sets than planned', () => {
    expect(readyToProgress([s(14, 10, 0), s(14, 10, 1)], planned)).toBe(false);
  });
  it('holds weight and targets +1 rep on the lowest set', () => {
    const r = suggestNext({ planned, sets: 3, history: [[s(14, 10, 0), s(14, 9, 1), s(14, 8, 2)]], increment: 2 });
    expect(r.kind).toBe('hold');
    expect(r.weightKg).toBe(14);
    expect(r.message).toContain('set 3');
    expect(r.prefill.map((p) => p.reps)).toEqual([10, 9, 9]);
  });
  it('eases off after two consecutive sessions under repsMin', () => {
    const bad = [s(20, 7, 0), s(20, 6, 1), s(20, 6, 2)];
    const r = suggestNext({ planned, sets: 3, history: [bad, bad], increment: 2 });
    expect(r.kind).toBe('decrease');
    expect(r.weightKg).toBe(18);
  });
  it('one bad session is not enough to ease off', () => {
    const r = suggestNext({ planned, sets: 3, history: [[s(20, 7, 0)], [s(20, 9, 0)]], increment: 2 });
    expect(r.kind).toBe('hold');
  });
  it('first-time prefill uses repsMin', () => {
    const r = suggestNext({ planned, sets: 2, history: [], increment: 2 });
    expect(r.kind).toBe('first');
    expect(r.prefill).toEqual([{ reps: 8 }, { reps: 8 }]);
  });
  it('progresses time for seconds-based holds and caps at 60s', () => {
    const p = { sets: 3, repsMin: 30, repsMax: 45, unit: 'seconds' as const };
    const hist = [[0, 1, 2].map((i) => ({ seconds: 45, setIndex: i }))];
    const r = suggestNext({ planned: p, sets: 3, history: hist, increment: 2, bodyweight: true });
    expect(r.kind).toBe('time_increase');
    expect(r.prefill[0].seconds).toBe(50);
    const capped = suggestNext({ planned: p, sets: 3, history: [[0, 1, 2].map((i) => ({ seconds: 60, setIndex: i }))], increment: 2 });
    expect(capped.kind).toBe('time_cap');
  });
  it('uses deload-adjusted set counts for prefill', () => {
    const r = suggestNext({ planned, sets: 2, history: [[s(14, 9, 0), s(14, 9, 1), s(14, 9, 2)]], increment: 2 });
    expect(r.prefill).toHaveLength(2);
  });
  it('bodyweight at top of range suggests a harder variant', () => {
    const r = suggestNext({ planned, sets: 3, history: [[0, 1, 2].map((i) => ({ reps: 10, setIndex: i }))], increment: 2, bodyweight: true });
    expect(r.kind).toBe('hold');
    expect(r.message).toMatch(/harder variant/);
  });
  it('maps equipment to increment buckets', () => {
    expect(equipmentBucket({ equipment: ['dumbbell'], name: 'Goblet squat' })).toBe('dumbbell');
    expect(equipmentBucket({ equipment: ['other'], name: 'Trap-bar deadlift' })).toBe('barbell');
    expect(equipmentBucket({ equipment: ['cable'], name: 'Seated cable row' })).toBe('machine');
  });
});

describe('strength metrics', () => {
  it('computes Epley e1RM and ignores >12 reps', () => {
    expect(e1rm(100, 3)).toBeCloseTo(110);
    expect(e1rm(100, 13)).toBeUndefined();
    expect(e1rm(undefined, 5)).toBeUndefined();
  });
  it('detects weight, e1rm and reps PRs', () => {
    const prior = [{ weightKg: 14, reps: 10 }, { weightKg: 16, reps: 6 }];
    expect(detectPRs({ weightKg: 18, reps: 5 }, prior)).toEqual(['weight', 'e1rm']);
    expect(detectPRs({ weightKg: 14, reps: 11 }, prior)).toEqual(['reps']);
    expect(detectPRs({ weightKg: 14, reps: 12 }, prior)).toEqual(['e1rm', 'reps']);
    expect(detectPRs({ weightKg: 12, reps: 8 }, prior)).toEqual([]);
    expect(detectPRs({ weightKg: 50, reps: 8 }, [])).toEqual([]);
  });
  it('sums working-set volume', () => {
    expect(volume([{ weightKg: 10, reps: 10, isWarmup: false }, { weightKg: 5, reps: 10, isWarmup: true }])).toBe(100);
  });
});
