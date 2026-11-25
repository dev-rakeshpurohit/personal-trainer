export const KG_PER_LB = 0.45359237;

export const kgToLb = (kg: number): number => kg / KG_PER_LB;
export const lbToKg = (lb: number): number => lb * KG_PER_LB;

export const roundTo = (n: number, step: number): number => Math.round(n / step) * step;

/** Display a kg value in the user's units, rounded sensibly. */
export function displayWeight(kg: number | undefined, units: 'kg' | 'lb'): string {
  if (kg == null) return '–';
  const v = units === 'kg' ? roundTo(kg, 0.25) : roundTo(kgToLb(kg), 0.5);
  return Number.isInteger(v) ? String(v) : v.toFixed(v * 10 === Math.round(v * 10) ? 1 : 2);
}

export const toUserUnits = (kg: number, units: 'kg' | 'lb'): number =>
  units === 'kg' ? roundTo(kg, 0.25) : roundTo(kgToLb(kg), 0.5);

export const fromUserUnits = (v: number, units: 'kg' | 'lb'): number => (units === 'kg' ? v : lbToKg(v));

/** Stepper increment in the user's display unit. */
export function stepFor(stepKg: number, units: 'kg' | 'lb'): number {
  if (units === 'kg') return stepKg;
  return stepKg <= 2.5 ? 5 : 10;
}

export function cmToFtIn(cm: number): { ft: number; inch: number } {
  const totalIn = Math.round(cm / 2.54);
  return { ft: Math.floor(totalIn / 12), inch: totalIn % 12 };
}

export const formatDuration = (sec: number): string => {
  const s = Math.max(0, Math.round(sec));
  const m = Math.floor(s / 60);
  const r = s % 60;
  if (m >= 60) return `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}:${String(r).padStart(2, '0')}`;
  return `${m}:${String(r).padStart(2, '0')}`;
};
