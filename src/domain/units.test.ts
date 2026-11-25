import { cmToFtIn, displayWeight, formatDuration, fromUserUnits, stepFor, toUserUnits } from './units';

describe('units', () => {
  it('converts kg/lb', () => {
    expect(displayWeight(20, 'kg')).toBe('20');
    expect(displayWeight(20, 'lb')).toBe('44');
    expect(fromUserUnits(44.0925, 'lb')).toBeCloseTo(20, 2);
    expect(toUserUnits(14.3, 'kg')).toBe(14.25);
    expect(stepFor(2, 'lb')).toBe(5);
  });
  it('formats durations and heights', () => {
    expect(formatDuration(75)).toBe('1:15');
    expect(formatDuration(3725)).toBe('1:02:05');
    expect(cmToFtIn(178)).toEqual({ ft: 5, inch: 10 });
  });
});
