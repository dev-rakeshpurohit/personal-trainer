import { kcalFloor } from './diet';

export type DietCardKind = 'on_track' | 'keep_going' | 'stalled' | 'adherence' | 'eat_more';

export interface DietCard {
  kind: DietCardKind;
  title: string;
  body: string;
  kcalDelta: number;
  applicable: boolean;
  floorWarning?: boolean;
}

/**
 * Diet adjustment coach (doc 06 §6). `checks` are weekly-loss values (kg/week, oldest first),
 * computed from consecutive valid weekly averages. Needs ≥ 14 days of data.
 */
export function dietAdjustment(args: {
  daysOfData: number;
  checks: number[];
  rate?: number;
  adherence?: number;
  liftsDown: number;
  sex: 'male' | 'female' | 'other';
  kcalTarget: number;
  riceReduced: boolean;
}): DietCard | undefined {
  const { daysOfData, checks, adherence = 0, liftsDown, sex, kcalTarget, riceReduced } = args;
  if (daysOfData < 14) return undefined;
  const rate = args.rate ?? checks[checks.length - 1];
  if (rate == null) return undefined;

  if (rate > 1.0 || liftsDown >= 2) {
    return {
      kind: 'eat_more',
      title: 'Eat a bit more',
      body: riceReduced
        ? 'You are losing fast or strength is slipping. Put lunch rice back to 100 g (≈ +65 kcal).'
        : 'You are losing fast or strength is slipping. Add 1 slice of multigrain toast at breakfast (≈ +70 kcal).',
      kcalDelta: riceReduced ? 65 : 70,
      applicable: true,
    };
  }
  const last2 = checks.slice(-2);
  const stalled2 = last2.length === 2 && last2.every((c) => c < 0.3);
  if (rate < 0.3 && adherence < 80) {
    return {
      kind: 'adherence',
      title: 'Adherence first',
      body: `You hit ${adherence}% of meals. Get that to 80%+ before cutting anything.`,
      kcalDelta: 0,
      applicable: false,
    };
  }
  if (stalled2 && adherence >= 80) {
    const next = kcalTarget - 65;
    return {
      kind: 'stalled',
      title: 'Progress has stalled',
      body: riceReduced
        ? 'Add 2,000 steps/day. Rice is already at 50 g, so keep steps up before cutting further.'
        : 'Add 2,000 steps/day first. If still stuck next check: lunch rice → 50 g (≈ −65 kcal).',
      kcalDelta: riceReduced ? 0 : -65,
      applicable: !riceReduced,
      floorWarning: next < kcalFloor(sex),
    };
  }
  if (rate >= 0.5 && rate <= 0.75) {
    return { kind: 'on_track', title: 'On track ✅', body: 'Weekly average loss is in the sweet spot. No change.', kcalDelta: 0, applicable: false };
  }
  return {
    kind: 'keep_going',
    title: 'Keep going',
    body: `Losing ${rate.toFixed(2)} kg/week. Stay consistent and check again in 2 weeks.`,
    kcalDelta: 0,
    applicable: false,
  };
}
