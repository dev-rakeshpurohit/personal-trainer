import { useLiveQuery } from 'dexie-react-hooks';
import { Check, ChevronRight, Scale } from 'lucide-react';
import { useMemo, useState } from 'react';
import { Button } from '@/components/ui';
import { Sheet } from '@/components/Sheet';
import { db } from '@/data/db';
import type { ProgramBundle } from '@/data/hooks';
import { addExerciseToDay } from '@/data/plan-edit';
import { GROUPS, planCheck, type Suggestion } from '@/domain/balance';
import { PRESETS } from '@/domain/equipment';
import type { Exercise } from '@/domain/types';
import { exerciseThumb } from '@/lib/clips';
import { useUI } from '@/store/ui';

/** Weekly sets per muscle group with one-tap fixes for gaps. */
export function PlanCheck({ bundle, exMap }: { bundle: ProgramBundle; exMap: Map<string, Exercise> }) {
  const profile = useLiveQuery(() => db.profile.get('me'), []);
  const [open, setOpen] = useState(false);
  const res = useMemo(() => {
    if (!exMap.size || !profile) return undefined;
    return planCheck({
      days: bundle.days,
      planned: bundle.planned,
      exMap,
      library: [...exMap.values()],
      equipment: profile.equipment ?? PRESETS.full_gym,
      goal: profile.goal,
    });
  }, [bundle, exMap, profile]);
  if (!res) return null;
  const gaps = res.suggestions;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={`mt-6 flex min-h-[64px] w-full items-center gap-3 rounded-card border px-4 py-3 text-left ${gaps.length ? 'border-warning/40 bg-warning/[0.07]' : 'border-line/50 bg-surface'}`}
      >
        <Scale size={22} className={gaps.length ? 'text-warning' : 'text-success'} aria-hidden />
        <span className="min-w-0 flex-1">
          <span className="block font-semibold">Plan check</span>
          <span className="block text-caption text-muted">
            {gaps.length ? `${gaps.length} gap${gaps.length > 1 ? 's' : ''}: ${gaps.map((g) => GROUPS.find((x) => x.id === g.group)!.label.toLowerCase()).join(', ')}` : 'Every muscle group gets enough work each week'}
          </span>
        </span>
        <ChevronRight size={18} className="text-muted" aria-hidden />
      </button>

      <Sheet open={open} onClose={() => setOpen(false)} title="Plan check" tall>
        <p className="mb-3 text-[15px] text-muted">Working sets per week. Helper muscles count half. Targets come from your goal.</p>
        <ul className="space-y-2" aria-label="Weekly sets per muscle group">
          {GROUPS.map((g) => {
            const have = res.sets[g.id];
            const need = res.targets[g.id];
            const ok = have >= need;
            return (
              <li key={g.id} className="grid grid-cols-[88px_1fr_64px] items-center gap-2">
                <span className="text-[15px] font-semibold">{g.label}</span>
                <span className="h-2.5 overflow-hidden rounded-full bg-surface2" role="img" aria-label={`${have} of ${need} sets`}>
                  <span className={`block h-full rounded-full ${ok ? 'bg-success' : 'bg-warning'}`} style={{ width: `${Math.min(100, (have / Math.max(need, 1)) * 100)}%` }} />
                </span>
                <span className={`text-right text-[13px] tnum ${ok ? 'text-muted' : 'font-bold text-warning'}`}>
                  {have} / {need}
                </span>
              </li>
            );
          })}
        </ul>
        {gaps.length === 0 ? (
          <p className="mt-4 flex items-center gap-2 rounded-card bg-success/10 p-3 text-[15px] font-semibold text-success">
            <Check size={18} aria-hidden /> Balanced. Nothing to add.
          </p>
        ) : (
          <div className="mt-5 space-y-4 pb-3">
            {gaps.map((s) => (
              <Fix key={s.group} s={s} onDone={() => undefined} />
            ))}
          </div>
        )}
      </Sheet>
    </>
  );
}

function Fix({ s, onDone }: { s: Suggestion; onDone: () => void }) {
  const [pick, setPick] = useState(s.options[0].id);
  const [added, setAdded] = useState(false);
  const toast = useUI((x) => x.toast);
  const label = GROUPS.find((g) => g.id === s.group)!.label;
  return (
    <section className="rounded-card border border-line/50 bg-surface p-3" aria-label={`${label} fix`}>
      <p className="font-semibold">
        {label}: {s.have} of {s.need} sets a week
      </p>
      <p className="text-caption text-muted">
        Add {s.sets} × {s.repsMin}–{s.repsMax} to {s.dayLabel}
      </p>
      <ul className="mt-2 space-y-1.5">
        {s.options.map((o) => {
          const t = exerciseThumb(o);
          const on = pick === o.id;
          return (
            <li key={o.id}>
              <button
                type="button"
                aria-pressed={on}
                onClick={() => setPick(o.id)}
                className={`flex min-h-[56px] w-full items-center gap-3 rounded-btn border p-1.5 text-left ${on ? 'border-primary bg-primary/10' : 'border-line/40'}`}
              >
                <span className="h-11 w-11 shrink-0 overflow-hidden rounded-btn bg-white">{t && <img src={t} alt="" className="h-full w-full object-cover" loading="lazy" />}</span>
                <span className="flex-1 font-semibold leading-snug">{o.name}</span>
                {on && <Check size={18} className="text-primary-ink" aria-hidden />}
              </button>
            </li>
          );
        })}
      </ul>
      <Button
        className="mt-2"
        block
        disabled={added}
        onClick={async () => {
          await addExerciseToDay(s.dayId, pick, { sets: s.sets, repsMin: s.repsMin, repsMax: s.repsMax, restSec: s.restSec });
          setAdded(true);
          toast(`Added to ${s.dayLabel}`, { tone: 'success' });
          onDone();
        }}
      >
        {added ? 'Added' : `Add to ${s.dayLabel.split(' – ')[0]}`}
      </Button>
    </section>
  );
}
