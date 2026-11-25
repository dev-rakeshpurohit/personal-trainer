import { differenceInCalendarDays, parseISO } from 'date-fns';
import { useLiveQuery } from 'dexie-react-hooks';
import { Salad } from 'lucide-react';
import { Button } from '@/components/ui';
import { db, getMeta, setMeta } from '@/data/db';
import { dietAdjustment } from '@/domain/coach';
import { dietChangeFor, riceReduced, type MealChange } from '@/domain/diet';
import type { Profile } from '@/domain/types';
import { useUI } from '@/store/ui';

export function DietCoachCard({ profile, rate, checks, adherence, liftsDown, daysOfData }: { profile: Profile; rate?: number; checks: number[]; adherence?: number; liftsDown: number; daysOfData: number }) {
  const toast = useUI((s) => s.toast);
  const ctx = useLiveQuery(async () => {
    const plan = await db.dietPlans.filter((p) => p.active).first();
    const meals = plan ? await db.plannedMeals.where('dietPlanId').equals(plan.id).toArray() : [];
    const last = await getMeta<string>('dietCoachLastAt');
    return { plan, meals, last };
  }, []);
  if (!ctx?.plan) return null;
  const card = dietAdjustment({
    daysOfData,
    checks,
    rate,
    adherence,
    liftsDown,
    sex: profile.sex,
    kcalTarget: ctx.plan.kcalTarget,
    riceReduced: riceReduced(ctx.meals),
  });
  if (!card) return null;
  const snoozed = ctx.last && differenceInCalendarDays(new Date(), parseISO(ctx.last)) < 14;
  if (snoozed && card.kind !== 'on_track') return null;
  const change: MealChange | undefined = card.applicable && (card.kind === 'stalled' || card.kind === 'eat_more') ? dietChangeFor(card.kind, ctx.meals) : undefined;

  const apply = async () => {
    if (!change || !ctx.plan) return;
    const meal = ctx.meals.find((m) => m.id === change.mealId)!;
    await db.plannedMeals.update(change.mealId, { items: change.items, kcal: change.kcal, proteinG: change.proteinG });
    await db.dietPlans.update(ctx.plan.id, { kcalTarget: ctx.plan.kcalTarget + (change.kcal - meal.kcal) });
    const log = (await getMeta<object[]>('planChanges')) ?? [];
    await setMeta('planChanges', [...log, { at: new Date().toISOString(), kind: card.kind, change: change.description }]);
    await setMeta('dietCoachLastAt', new Date().toISOString());
    toast(`Diet updated: ${change.description}`, {
      tone: 'success',
      undo: async () => {
        await db.plannedMeals.put(meal);
        await db.dietPlans.update(ctx.plan!.id, { kcalTarget: ctx.plan!.kcalTarget });
      },
    });
  };
  const tone = card.kind === 'on_track' ? 'border-success/40 bg-success/[0.07]' : card.kind === 'eat_more' || card.kind === 'stalled' ? 'border-warning/40 bg-warning/[0.07]' : 'border-info/40 bg-info/[0.07]';
  return (
    <div className={`rounded-card border p-4 ${tone}`}>
      <p className="flex items-center gap-2 font-bold">
        <Salad size={20} aria-hidden /> Diet check · {card.title}
      </p>
      <p className="mt-1 text-[15px] text-text/85">{card.body}</p>
      {card.floorWarning && <p className="mt-2 text-[14px] text-warning">This would take you below a safe minimum. Please talk to a doctor or dietitian before cutting further.</p>}
      {change && <p className="mt-2 text-[14px] font-semibold">Suggested: {change.description}</p>}
      {(change || card.kind !== 'on_track') && (
        <div className="mt-3 flex gap-2">
          {change && (
            <Button onClick={apply} className="flex-1">
              Apply
            </Button>
          )}
          <Button variant="secondary" className="flex-1" onClick={() => setMeta('dietCoachLastAt', new Date().toISOString())}>
            Dismiss
          </Button>
        </div>
      )}
    </div>
  );
}
