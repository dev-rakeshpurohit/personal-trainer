import { ChevronRight, Plus, Trash2 } from 'lucide-react';
import { useState } from 'react';
import { BackButton } from '@/components/BackButton';
import { Field, TextInput, Toggle } from '@/components/Field';
import { Sheet } from '@/components/Sheet';
import { Stepper } from '@/components/Stepper';
import { Button, Card, PageHeader, SectionTitle } from '@/components/ui';
import { db, uid } from '@/data/db';
import { useDiet } from '@/data/hooks';
import { plannedTotals } from '@/domain/diet';
import type { PlannedMeal } from '@/domain/types';
import { useUI } from '@/store/ui';

export default function DietEditor() {
  const diet = useDiet();
  const [edit, setEdit] = useState<PlannedMeal>();
  if (diet === undefined) return null;
  if (diet === null)
    return (
      <div className="pb-6">
        <PageHeader title="Diet plan" right={<BackButton to="/more" />} />
        <div className="px-4">
          <Button
            block
            onClick={async () => {
              const p = await db.profile.get('me');
              await db.dietPlans.add({ id: uid(), name: 'My diet', active: true, kcalTarget: p?.kcalTarget ?? 2000, proteinTargetG: p?.proteinTargetG ?? 140 });
            }}
          >
            Create a diet plan
          </Button>
        </div>
      </div>
    );
  const t = plannedTotals(diet.meals);
  const addMeal = async () => {
    const m: PlannedMeal = { id: uid(), dietPlanId: diet.plan.id, order: diet.meals.length, time: '12:00', meal: 'New meal', items: [], proteinG: 20, kcal: 300 };
    await db.plannedMeals.add(m);
    setEdit(m);
  };
  return (
    <div className="pb-8">
      <PageHeader title="Diet plan" sub={diet.plan.name} right={<BackButton to="/more" />} />
      <div className="space-y-3 px-4">
        <Card className="space-y-3">
          <div className="flex items-center gap-3">
            <span className="w-24 font-medium">Calories</span>
            <div className="flex-1">
              <Stepper label="Calorie target" value={diet.plan.kcalTarget} onChange={(v) => db.dietPlans.update(diet.plan.id, { kcalTarget: v })} step={50} min={1000} max={5000} suffix="kcal" decimals={0} inputMode="numeric" />
            </div>
          </div>
          <div className="flex items-center gap-3">
            <span className="w-24 font-medium">Protein</span>
            <div className="flex-1">
              <Stepper label="Protein target" value={diet.plan.proteinTargetG} onChange={(v) => db.dietPlans.update(diet.plan.id, { proteinTargetG: v })} step={5} min={30} max={400} suffix="g" decimals={0} inputMode="numeric" />
            </div>
          </div>
          <p className="text-caption text-muted">
            Planned meals add up to {t.kcal.toLocaleString()} kcal and {t.proteinG} g protein (optional meals excluded).
          </p>
        </Card>
        <SectionTitle>Meals</SectionTitle>
        <ul className="space-y-2">
          {diet.meals.map((m) => (
            <li key={m.id}>
              <button type="button" onClick={() => setEdit(m)} className="flex min-h-[64px] w-full items-center gap-3 rounded-card border border-line/50 bg-surface p-3 text-left">
                <span className="w-12 text-[15px] font-semibold text-muted tnum">{m.time}</span>
                <span className="min-w-0 flex-1">
                  <span className="block font-semibold">{m.meal}{m.optional ? ' · optional' : ''}</span>
                  <span className="block truncate text-caption text-muted">{m.items.join(' · ') || 'No items yet'}</span>
                </span>
                <span className="text-right text-[14px] tnum">
                  {m.proteinG} g<br />
                  <span className="text-muted">{m.kcal} kcal</span>
                </span>
                <ChevronRight size={18} className="text-muted" aria-hidden />
              </button>
            </li>
          ))}
        </ul>
        <Button variant="secondary" block size="lg" onClick={addMeal}>
          <Plus size={20} aria-hidden /> Add meal
        </Button>
      </div>
      {edit && <MealSheet meal={edit} onClose={() => setEdit(undefined)} />}
    </div>
  );
}

function MealSheet({ meal, onClose }: { meal: PlannedMeal; onClose: () => void }) {
  const toast = useUI((s) => s.toast);
  const [m, setM] = useState(meal);
  const save = async () => {
    await db.plannedMeals.put({ ...m, items: m.items.map((i) => i.trim()).filter(Boolean), rotate: m.rotate?.map((i) => i.trim()).filter(Boolean) });
    onClose();
  };
  return (
    <Sheet
      open
      onClose={save}
      title="Edit meal"
      tall
      footer={
        <div className="flex gap-2">
          <Button
            variant="danger"
            aria-label="Delete meal"
            onClick={async () => {
              await db.plannedMeals.delete(meal.id);
              toast(`${meal.meal} deleted`, { undo: () => db.plannedMeals.put(meal).then(() => undefined) });
              onClose();
            }}
          >
            <Trash2 size={18} aria-hidden />
          </Button>
          <Button block size="lg" onClick={save}>
            Save
          </Button>
        </div>
      }
    >
      <div className="space-y-4 pb-3">
        <div className="grid grid-cols-[1fr_120px] gap-3">
          <Field label="Name">
            <TextInput value={m.meal} onChange={(e) => setM({ ...m, meal: e.target.value })} />
          </Field>
          <Field label="Time">
            <TextInput type="time" value={m.time} onChange={(e) => setM({ ...m, time: e.target.value })} />
          </Field>
        </div>
        <Field label="Items (one per line)">
          <textarea value={m.items.join('\n')} onChange={(e) => setM({ ...m, items: e.target.value.split('\n') })} rows={4} className="w-full rounded-btn border border-line bg-surface2 p-3 text-[16px] outline-none focus:border-primary" />
        </Field>
        <Field label="Rotating options (one per line, optional)">
          <textarea value={(m.rotate ?? []).join('\n')} onChange={(e) => setM({ ...m, rotate: e.target.value.split('\n') })} rows={3} className="w-full rounded-btn border border-line bg-surface2 p-3 text-[16px] outline-none focus:border-primary" />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <span className="mb-1 block text-[14px] font-semibold text-muted">Protein</span>
            <Stepper label="Protein grams" value={m.proteinG} onChange={(v) => setM({ ...m, proteinG: v })} step={1} suffix="g" decimals={0} inputMode="numeric" />
          </div>
          <div>
            <span className="mb-1 block text-[14px] font-semibold text-muted">Calories</span>
            <Stepper label="Calories" value={m.kcal} onChange={(v) => setM({ ...m, kcal: v })} step={10} suffix="kcal" decimals={0} inputMode="numeric" />
          </div>
        </div>
        <Toggle checked={!!m.optional} onChange={(v) => setM({ ...m, optional: v })} label="Optional" sub="Not counted in adherence" />
        <Toggle checked={!!m.skipOnRestDay} onChange={(v) => setM({ ...m, skipOnRestDay: v })} label="Training days only" sub="Hidden on rest days (e.g. pre-gym snack)" />
      </div>
    </Sheet>
  );
}
