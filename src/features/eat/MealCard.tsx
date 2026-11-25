import { Check, Repeat, SkipForward, Undo2 } from 'lucide-react';
import { useState } from 'react';
import { Button, Chip } from '@/components/ui';
import { Sheet } from '@/components/Sheet';
import { Field, TextInput } from '@/components/Field';
import { Stepper } from '@/components/Stepper';
import { clearMeal, logMeal } from '@/data/repo';
import type { MealLog, PlannedMeal } from '@/domain/types';
import { useUI } from '@/store/ui';

export function MealCard({ meal, log, dayKey, highlight }: { meal: PlannedMeal; log?: MealLog; dayKey: string; highlight?: boolean }) {
  const toast = useUI((s) => s.toast);
  const [swap, setSwap] = useState(false);
  const [rot, setRot] = useState<string | undefined>(log?.chosenRotation);
  const done = log && log.state !== 'skipped';

  const act = async (state: MealLog['state'], extra = {}) => {
    const undo = await logMeal(dayKey, meal, state, { chosenRotation: rot, ...extra });
    toast(state === 'eaten' ? `${meal.meal} logged · +${meal.proteinG} g protein` : state === 'skipped' ? `${meal.meal} skipped` : `${meal.meal} swapped`, { undo });
  };

  return (
    <article
      className={`rounded-card border p-4 transition-colors ${
        log?.state === 'skipped' ? 'border-line/50 bg-surface opacity-60' : done ? 'border-success/40 bg-success/[0.07]' : highlight ? 'border-primary/50 bg-surface' : 'border-line/50 bg-surface'
      }`}
      aria-label={`${meal.meal} at ${meal.time}`}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-caption font-semibold text-muted tnum">
            {meal.time}
            {meal.optional && ' · optional'}
          </p>
          <h3 className="text-[18px] font-bold">{meal.meal}</h3>
        </div>
        <div className="text-right">
          <p className="text-[17px] font-bold tnum">{log?.state === 'swapped' ? log.proteinG : meal.proteinG} g</p>
          <p className="text-caption text-muted tnum">{log?.state === 'swapped' ? log.kcal : meal.kcal} kcal</p>
        </div>
      </div>
      {log?.state === 'swapped' && log.label ? (
        <p className="mt-2 text-[15px]">
          <span className="font-semibold text-info">Swapped:</span> {log.label}
        </p>
      ) : (
        <ul className="mt-2 space-y-0.5 text-[15px] text-text/90">
          {meal.items.map((i) => (
            <li key={i}>• {i}</li>
          ))}
        </ul>
      )}
      {meal.rotate && meal.rotate.length > 0 && (
        <div className="no-scrollbar -mx-1 mt-3 flex gap-2 overflow-x-auto px-1">
          {meal.rotate.map((r) => (
            <Chip
              key={r}
              active={rot === r}
              onClick={async () => {
                const v = rot === r ? undefined : r;
                setRot(v);
                if (log) await logMeal(dayKey, meal, log.state, { chosenRotation: v, label: log.label, proteinG: log.proteinG, kcal: log.kcal });
              }}
            >
              {r}
            </Chip>
          ))}
        </div>
      )}
      <div className="mt-3 flex gap-2">
        {log ? (
          <Button
            variant="secondary"
            className="flex-1"
            onClick={async () => {
              const undo = await clearMeal(dayKey, meal.id);
              toast(`${meal.meal} reset`, { undo });
            }}
          >
            <Undo2 size={18} aria-hidden /> {log.state === 'eaten' ? 'Eaten' : log.state === 'skipped' ? 'Skipped' : 'Swapped'} · undo
          </Button>
        ) : (
          <>
            <Button variant="success" className="flex-[2]" onClick={() => act('eaten')}>
              <Check size={20} strokeWidth={3} aria-hidden /> Eaten
            </Button>
            <Button variant="secondary" className="flex-1" onClick={() => setSwap(true)} aria-label={`Swap ${meal.meal}`}>
              <Repeat size={18} aria-hidden /> Swap
            </Button>
            <Button variant="secondary" className="flex-1" onClick={() => act('skipped')} aria-label={`Skip ${meal.meal}`}>
              <SkipForward size={18} aria-hidden /> Skip
            </Button>
          </>
        )}
      </div>
      <SwapSheet open={swap} onClose={() => setSwap(false)} meal={meal} onSave={(label, p, k) => act('swapped', { label, proteinG: p, kcal: k })} />
    </article>
  );
}

function SwapSheet({ open, onClose, meal, onSave }: { open: boolean; onClose: () => void; meal: PlannedMeal; onSave: (label: string, p: number, k: number) => void }) {
  const [label, setLabel] = useState('');
  const [p, setP] = useState(meal.proteinG);
  const [k, setK] = useState(meal.kcal);
  return (
    <Sheet
      open={open}
      onClose={onClose}
      title={`Swap ${meal.meal.toLowerCase()}`}
      footer={
        <Button
          block
          size="lg"
          onClick={() => {
            onSave(label.trim() || 'Something else', p, k);
            onClose();
          }}
        >
          Save swap
        </Button>
      }
    >
      <div className="space-y-4 pt-2">
        <Field label="What did you eat instead?">
          <TextInput value={label} onChange={(e) => setLabel(e.target.value)} placeholder="e.g. 3 egg whites + 2 toast" />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <span className="mb-1 block text-[14px] font-semibold text-muted">Protein</span>
            <Stepper label="Protein grams" value={p} onChange={setP} step={5} suffix="g" inputMode="numeric" decimals={0} />
          </div>
          <div>
            <span className="mb-1 block text-[14px] font-semibold text-muted">Calories</span>
            <Stepper label="Calories" value={k} onChange={setK} step={25} suffix="kcal" inputMode="numeric" decimals={0} />
          </div>
        </div>
        <p className="text-caption text-muted">Starts from the planned values. Adjust roughly; close enough is fine.</p>
      </div>
    </Sheet>
  );
}
