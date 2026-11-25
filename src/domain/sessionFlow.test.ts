import { buildFlow, nextStep, stepKey } from './sessionFlow';

describe('session flow', () => {
  const flow = buildFlow([
    { sets: 4, supersetGroup: 'A' },
    { sets: 3, supersetGroup: 'A' },
    { sets: 2 },
  ]);
  it('alternates superset pairs and handles uneven set counts', () => {
    expect(flow.map(stepKey)).toEqual(['0:0', '1:0', '0:1', '1:1', '0:2', '1:2', '0:3', '2:0', '2:1']);
  });
  it('finds the next pending step and wraps around', () => {
    const done = new Set(['0:0']);
    expect(nextStep(flow, done, { ex: 0, set: 0 })).toEqual({ ex: 1, set: 0 });
    const almost = new Set(flow.map(stepKey).filter((k) => k !== '0:1'));
    expect(nextStep(flow, almost, { ex: 2, set: 1 })).toEqual({ ex: 0, set: 1 });
    expect(nextStep(flow, new Set(flow.map(stepKey)), { ex: 2, set: 1 })).toBeUndefined();
  });
});
