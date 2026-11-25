import { CheckCircle2, Circle, Droplets, Minus, Plus } from 'lucide-react';
import { setHabit } from '@/data/repo';
import { Stepper } from '@/components/Stepper';
import type { HabitDef, HabitLog } from '@/domain/types';

export function Habits({ defs, logs, dayKey }: { defs: HabitDef[]; logs: HabitLog[]; dayKey: string }) {
  const val = (id: string) => logs.find((l) => l.habitId === id)?.value ?? 0;
  return (
    <div className="divide-y divide-line/50 rounded-card border border-line/50 bg-surface">
      {defs
        .sort((a, b) => a.order - b.order)
        .map((h) => {
          const v = val(h.id);
          if (h.id === 'water') {
            const target = h.target ?? 3000;
            const pct = Math.min(1, v / target);
            return (
              <div key={h.id} className="p-4">
                <div className="flex items-center justify-between">
                  <span className="flex items-center gap-2 font-semibold">
                    <Droplets size={20} className="text-info" aria-hidden /> Water
                  </span>
                  <span className="text-[17px] font-bold tnum">
                    {(v / 1000).toFixed(2)} <span className="text-[14px] font-medium text-muted">/ {(target / 1000).toFixed(1)} L</span>
                  </span>
                </div>
                <div className="mt-2 h-2 overflow-hidden rounded-full bg-surface2" role="progressbar" aria-valuenow={Math.round(pct * 100)} aria-valuemin={0} aria-valuemax={100} aria-label="Water progress">
                  <div className="h-full rounded-full bg-info transition-[width] duration-300" style={{ width: `${pct * 100}%` }} />
                </div>
                <div className="mt-3 flex gap-2">
                  <button type="button" onClick={() => setHabit(dayKey, h.id, Math.max(0, v - 250))} className="flex h-12 w-14 items-center justify-center rounded-btn bg-surface2" aria-label="Remove 250 ml water">
                    <Minus size={18} aria-hidden />
                  </button>
                  <button type="button" onClick={() => setHabit(dayKey, h.id, v + 250)} className="flex h-12 flex-1 items-center justify-center gap-1.5 rounded-btn bg-info/20 font-bold text-info" aria-label="Add 250 ml water">
                    <Plus size={18} aria-hidden /> 250 ml
                  </button>
                  <button type="button" onClick={() => setHabit(dayKey, h.id, v + 500)} className="flex h-12 flex-1 items-center justify-center gap-1.5 rounded-btn bg-info/10 font-semibold text-info" aria-label="Add 500 ml water">
                    <Plus size={18} aria-hidden /> 500 ml
                  </button>
                </div>
              </div>
            );
          }
          if (h.kind === 'check')
            return (
              <button key={h.id} type="button" role="checkbox" aria-checked={v > 0} onClick={() => setHabit(dayKey, h.id, v > 0 ? 0 : 1)} className="flex min-h-[60px] w-full items-center gap-3 px-4 text-left">
                {v > 0 ? <CheckCircle2 size={26} className="text-success" aria-hidden /> : <Circle size={26} className="text-muted" aria-hidden />}
                <span className={`flex-1 font-medium ${v > 0 ? 'text-muted' : ''}`}>{h.label}</span>
              </button>
            );
          const isSteps = h.id === 'steps' || h.unit === 'steps';
          return (
            <div key={h.id} className="flex items-center gap-3 px-4 py-3">
              <div className="min-w-0 flex-1">
                <p className="font-medium">{h.label}</p>
                <p className="text-caption text-muted">
                  Target {h.target?.toLocaleString()} {h.unit}
                  {h.target && v >= h.target ? ' · ✓ hit' : ''}
                </p>
              </div>
              <div className="w-[180px]">
                <Stepper label={h.label} value={v} onChange={(n) => setHabit(dayKey, h.id, n)} step={isSteps ? 500 : 0.5} decimals={isSteps ? 0 : 1} inputMode={isSteps ? 'numeric' : 'decimal'} max={isSteps ? 100000 : 24} />
              </div>
            </div>
          );
        })}
    </div>
  );
}
