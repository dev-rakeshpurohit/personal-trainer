/** Gym equipment model: what each exercise needs, what's available, and plan substitution. Pure. */
import type { Exercise, PlannedExercise } from './types';

export type EquipmentId =
  | 'dumbbells' | 'barbell' | 'trap_bar' | 'kettlebells' | 'cable' | 'machines' | 'bench' | 'pullup_bar'
  | 'bands' | 'medicine_ball' | 'box' | 'cardio_machines' | 'stability_ball' | 'sled';

export const EQUIPMENT: { id: EquipmentId; label: string; hint: string }[] = [
  { id: 'dumbbells', label: 'Dumbbells', hint: 'A rack of fixed or adjustable dumbbells' },
  { id: 'bench', label: 'Adjustable bench', hint: 'Flat / incline' },
  { id: 'barbell', label: 'Barbell + plates', hint: 'Includes EZ bar, squat rack' },
  { id: 'trap_bar', label: 'Trap / hex bar', hint: '' },
  { id: 'kettlebells', label: 'Kettlebells', hint: '' },
  { id: 'cable', label: 'Cable station', hint: 'Pulley with handles / rope' },
  { id: 'machines', label: 'Machines', hint: 'Leg press, lat pulldown, rows…' },
  { id: 'pullup_bar', label: 'Pull-up bar', hint: 'Or captain’s chair' },
  { id: 'bands', label: 'Resistance bands', hint: '' },
  { id: 'medicine_ball', label: 'Medicine ball', hint: '' },
  { id: 'box', label: 'Plyo box / step', hint: '' },
  { id: 'cardio_machines', label: 'Cardio machines', hint: 'Bike, treadmill, rower, cross-trainer' },
  { id: 'stability_ball', label: 'Stability ball', hint: '' },
  { id: 'sled', label: 'Sled', hint: '' },
];

export const PRESETS: Record<'full_gym' | 'dumbbells_only' | 'home', EquipmentId[]> = {
  full_gym: ['dumbbells', 'bench', 'barbell', 'trap_bar', 'kettlebells', 'cable', 'machines', 'pullup_bar', 'bands', 'medicine_ball', 'box', 'cardio_machines', 'stability_ball'],
  dumbbells_only: ['dumbbells', 'bench', 'bands'],
  home: ['bands'],
};

const has = (s: string, re: RegExp) => re.test(s);

/** Equipment an exercise needs (empty = bodyweight). */
export function requiredEquipment(ex: Pick<Exercise, 'name' | 'equipment' | 'category'>): EquipmentId[] {
  const name = ex.name.toLowerCase();
  const eq = ex.equipment.map((e) => e.toLowerCase());
  const out = new Set<EquipmentId>();
  const cardioName = /bike|cycling|bicycl|treadmill|rower|rowing machine|rowing,|elliptical|cross-?trainer|stair|assault|airdyne|ski erg/;
  for (const e of eq) {
    if (/dumbbell/.test(e)) out.add('dumbbells');
    else if (/barbell|e-z|ez bar/.test(e)) out.add('barbell');
    else if (/cable/.test(e)) out.add('cable');
    else if (/machine/.test(e)) out.add(has(name, cardioName) ? 'cardio_machines' : 'machines');
    else if (/kettlebell/.test(e)) out.add('kettlebells');
    else if (/band/.test(e)) out.add('bands');
    else if (/medicine ball/.test(e)) out.add('medicine_ball');
    else if (/exercise ball|stability/.test(e)) out.add('stability_ball');
  }
  if (has(name, /trap.?bar|hex bar/)) {
    out.delete('barbell');
    out.add('trap_bar');
  }
  if (has(name, cardioName) && !has(name, /walk|outdoor|band/)) {
    out.delete('machines');
    out.add('cardio_machines');
  }
  if (has(name, /leg press|hack squat|pulldown|pull-?down|smith|pec deck|leg curl|leg extension|assisted pull-?up machine|chest press machine/)) out.add('machines');
  if (has(name, /cable|woodchop|pallof/) && !out.has('bands') && !has(name, /band/)) out.add('cable');
  if (has(name, /pull-?up|chin-?up|hanging|toes to bar/) && !has(name, /machine|band-assisted pulldown/)) out.add('pullup_bar');
  if (has(name, /bench|incline|decline|step-?up|bulgarian|box squat|hip thrust/) && (out.has('dumbbells') || out.has('barbell') || has(name, /bench|step-?up|bulgarian/))) out.add('bench');
  if (has(name, /box jump|depth jump/)) out.add('box');
  if (has(name, /sled|yoke|prowler/)) out.add('sled');
  if (has(name, /farmer|suitcase carry/) && !out.size) out.add('dumbbells');
  if (has(name, /medicine.?ball|slam/) && !out.size) out.add('medicine_ball');
  if (has(name, /kettlebell/)) out.add('kettlebells');
  if (has(name, /dumbbell/)) out.add('dumbbells');
  if (has(name, /\bband/)) {
    out.delete('cable');
    out.add('bands');
  }
  return [...out];
}

export function isAvailable(ex: Pick<Exercise, 'name' | 'equipment' | 'category'>, available: readonly string[]): boolean {
  return requiredEquipment(ex).every((r) => available.includes(r));
}

/** Best available replacement: plan swap first, then alternates closest in difficulty and with the same unit. */
export function bestReplacement(
  original: Exercise,
  candidates: (Exercise | undefined)[],
  available: readonly string[],
  exclude: string[] = [],
): Exercise | undefined {
  const target = original.level ?? 3;
  const ok = candidates.filter((c): c is Exercise => !!c && c.id !== original.id && !exclude.includes(c.id) && isAvailable(c, available));
  return ok
    .map((c, i) => ({ c, score: Math.abs((c.level ?? target) - target) * 2 + (c.defaultUnit === original.defaultUnit ? 0 : 3) + i * 0.01 }))
    .sort((a, b) => a.score - b.score)[0]?.c;
}

export interface PlanChange {
  plannedExerciseId: string;
  from: string;
  to?: string;
  kind: 'replaced' | 'removed' | 'swap_replaced' | 'swap_removed';
}

/** Make a day's planned exercises fit the available equipment. Returns the edits to apply. */
export function adaptToEquipment(planned: PlannedExercise[], exMap: Map<string, Exercise>, available: readonly string[]): PlanChange[] {
  const changes: PlanChange[] = [];
  for (const pe of planned) {
    const ex = exMap.get(pe.exerciseId);
    if (!ex) continue;
    const used = planned.filter((p) => p.id !== pe.id).map((p) => p.exerciseId);
    if (!isAvailable(ex, available)) {
      const candidates = [pe.swapExerciseId, ...(ex.alternates ?? [])].map((id) => (id ? exMap.get(id) : undefined));
      const rep = bestReplacement(ex, candidates, available, used);
      changes.push(rep ? { plannedExerciseId: pe.id, from: ex.id, to: rep.id, kind: 'replaced' } : { plannedExerciseId: pe.id, from: ex.id, kind: 'removed' });
    }
    const swap = pe.swapExerciseId ? exMap.get(pe.swapExerciseId) : undefined;
    if (swap && !isAvailable(swap, available)) {
      const main = changes.find((c) => c.plannedExerciseId === pe.id)?.to ?? pe.exerciseId;
      const rep = bestReplacement(swap, (ex.alternates ?? []).map((id) => exMap.get(id)), available, [main, ...used]);
      changes.push(rep ? { plannedExerciseId: pe.id, from: swap.id, to: rep.id, kind: 'swap_replaced' } : { plannedExerciseId: pe.id, from: swap.id, kind: 'swap_removed' });
    }
  }
  return changes;
}
