import { addDays, format, parseISO } from 'date-fns';
import { ArrowLeft, Check, Dumbbell, Sparkles, Upload } from 'lucide-react';
import { useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button, Chip } from '@/components/ui';
import { Field, TextInput } from '@/components/Field';
import { Segmented } from '@/components/Segmented';
import { Stepper } from '@/components/Stepper';
import { db, setMeta } from '@/data/db';
import { suggestTargets } from '@/domain/diet';
import { cmToFtIn } from '@/domain/units';
import type { DietType, Profile, Sex, Weekday } from '@/domain/types';
import { WEEKDAYS, WEEKDAY_LABEL } from '@/domain/types';
import { requestPersistence } from '@/lib/storage';
import { useUI } from '@/store/ui';

type Mode = 'template' | 'blank';
const INTOLERANCES = ['lactose', 'gluten', 'nuts', 'soy', 'paneer'];
const DIETS: { v: DietType; l: string }[] = [
  { v: 'veg', l: 'Vegetarian' },
  { v: 'veg_egg', l: 'Veg + eggs' },
  { v: 'nonveg', l: 'Non-veg' },
  { v: 'vegan', l: 'Vegan' },
];

export default function Onboarding() {
  const nav = useNavigate();
  const toast = useUI((s) => s.toast);
  const [step, setStep] = useState(0);
  const [busy, setBusy] = useState(false);
  const [mode, setMode] = useState<Mode>('template');
  const thisYear = new Date().getFullYear();
  const [f, setF] = useState({
    name: '',
    sex: 'male' as Sex,
    age: 30,
    heightCm: 175,
    weightKg: 80,
    goalKg: 74,
    targetDate: '',
    days: ['TUE', 'WED', 'THU', 'FRI', 'SAT'] as Weekday[],
    closed: 'MON' as Weekday | '',
    sessionTime: '09:15',
    diet: 'veg_egg' as DietType,
    intolerances: ['lactose'] as string[],
    kcal: 2000,
    protein: 150,
    targetsTouched: false,
  });
  const set = <K extends keyof typeof f>(k: K, v: (typeof f)[K]) => setF((s) => ({ ...s, [k]: v }));
  const fileRef = useRef<HTMLInputElement>(null);

  const suggested = useMemo(
    () => suggestTargets({ sex: f.sex, age: f.age, heightCm: f.heightCm, weightKg: f.weightKg, goalWeightKg: f.goalKg }),
    [f.sex, f.age, f.heightCm, f.weightKg, f.goalKg],
  );

  const pace = useMemo(() => {
    const toLose = f.weightKg - f.goalKg;
    if (toLose <= 0) return { text: 'Goal is at or above your current weight: we will focus on strength and recomposition.' };
    const fast = addDays(new Date(), Math.round((toLose / 0.75) * 7));
    const slow = addDays(new Date(), Math.round((toLose / 0.5) * 7));
    let warn: string | undefined;
    if (f.targetDate) {
      const weeks = (parseISO(f.targetDate).getTime() - Date.now()) / (7 * 864e5);
      const rate = toLose / Math.max(weeks, 0.1);
      if (rate > 1) warn = `That date needs ${rate.toFixed(1)} kg/week, which is a lot. Something around ${format(slow, 'MMM yyyy')} is kinder and more likely to stick.`;
    }
    return { text: `At a healthy 0.5–0.75 kg a week you'd reach ${f.goalKg} kg between ${format(fast, 'MMM d')} and ${format(slow, 'MMM d, yyyy')}.`, warn };
  }, [f.weightKg, f.goalKg, f.targetDate]);

  async function finish() {
    setBusy(true);
    try {
      const kcal = f.targetsTouched ? f.kcal : mode === 'template' ? 2000 : suggested.kcal;
      const protein = f.targetsTouched ? f.protein : mode === 'template' ? 150 : suggested.proteinG;
      const days = f.days.length ? f.days : (['TUE', 'THU', 'SAT'] as Weekday[]);
      const profile: Profile = {
        id: 'me',
        name: f.name.trim() || 'there',
        sex: f.sex,
        birthYear: thisYear - f.age,
        heightCm: f.heightCm,
        startWeightKg: f.weightKg,
        goalWeightKg: f.goalKg,
        targetDate: f.targetDate || undefined,
        units: 'kg',
        theme: 'dark',
        dietType: f.diet,
        intolerances: f.intolerances,
        kcalTarget: kcal,
        proteinTargetG: protein,
        trainingDays: days,
        sessionTime: f.sessionTime,
        restTimer: { sound: true, vibrate: true, notify: false },
        stepKg: { dumbbell: 2, barbell: 5, machine: 5 },
        weekStart: 'mon',
        createdAt: new Date().toISOString(),
      };
      const seed = await import('@/data/seed-import');
      if (mode === 'template') {
        await seed.importProgramTemplate({ trainingDays: days });
        await seed.importDietTemplate();
        const plan = await db.dietPlans.filter((p) => p.active).first();
        if (plan) await db.dietPlans.update(plan.id, { kcalTarget: kcal, proteinTargetG: protein });
      } else {
        await seed.createBlankProgram(days, kcal, protein);
      }
      await db.profile.put(profile);
      await db.bodyLogs.put({ id: crypto.randomUUID(), dayKey: format(new Date(), 'yyyy-MM-dd'), weightKg: f.weightKg });
      if (f.closed) await setMeta('gymClosedDay', f.closed);
      await setMeta('onboardedAt', new Date().toISOString());
      await requestPersistence();
      nav('/today?welcome=1', { replace: true });
    } catch (e) {
      console.error(e);
      toast('Something went wrong setting up. Please try again.');
      setBusy(false);
    }
  }

  async function restore(file: File) {
    try {
      const { parseBackupFile, restoreBackup } = await import('@/data/backup');
      await restoreBackup(await parseBackupFile(file), 'replace');
      await requestPersistence();
      toast('Backup restored. Welcome back!', { tone: 'success' });
      nav('/today', { replace: true });
    } catch (e) {
      toast((e as Error).message);
    }
  }

  const steps = ['Welcome', 'About you', 'Schedule', 'Food'];
  const { ft, inch } = cmToFtIn(f.heightCm);

  return (
    <div className="app-shell flex flex-col bg-bg">
      <header className="pt-safe">
        <div className="flex h-14 items-center gap-2 px-2">
          {step > 0 ? (
            <button type="button" aria-label="Back" onClick={() => setStep(step - 1)} className="flex h-12 w-12 items-center justify-center rounded-full active:bg-surface2">
              <ArrowLeft size={22} />
            </button>
          ) : (
            <div className="w-12" />
          )}
          <div className="flex flex-1 justify-center gap-1.5" aria-label={`Step ${step + 1} of 4`}>
            {steps.map((s, i) => (
              <span key={s} className={`h-1.5 rounded-full transition-all duration-300 ${i <= step ? 'w-8 bg-primary' : 'w-4 bg-line'}`} />
            ))}
          </div>
          {step > 0 ? (
            <button type="button" onClick={finish} disabled={busy} className="h-12 min-w-12 px-3 text-[15px] font-semibold text-muted">
              Skip
            </button>
          ) : (
            <div className="w-12" />
          )}
        </div>
      </header>

      <main className="flex-1 overflow-y-auto px-5 pb-6">
        {step === 0 && (
          <div className="animate-fade-in pt-6">
            <div className="mb-6 flex h-16 w-16 items-center justify-center rounded-[20px] bg-gradient-to-br from-[#FF9A3D] to-[#FF5E0E] shadow-[0_12px_40px_-10px_rgba(255,122,26,0.7)]">
              <Dumbbell size={32} className="text-[#0B0F14]" strokeWidth={2.4} aria-hidden />
            </div>
            <h1 className="text-[34px] font-bold leading-[1.1] tracking-tight">
              Your coach.
              <br />
              <span className="text-primary-ink">No signal needed.</span>
            </h1>
            <p className="mt-3 text-[17px] text-muted">Open, see today's plan, tap through your sets. Repmate remembers, times, progresses and nudges. Everything stays on this phone.</p>

            <div className="mt-8 space-y-3">
              <ChoiceCard
                selected={mode === 'template'}
                onClick={() => setMode('template')}
                title="Use a ready plan"
                badge="Recommended"
                body="Lean & Athletic, 5 days a week (Tue–Sat), plus the Veg + eggs 2,000 kcal diet. Edit anything later."
              />
              <ChoiceCard selected={mode === 'blank'} onClick={() => setMode('blank')} title="Start blank" body="Pick your days and build your own workouts and meals." />
            </div>

            <button type="button" onClick={() => fileRef.current?.click()} className="mt-6 flex min-h-[48px] items-center gap-2 text-[15px] font-semibold text-primary-ink">
              <Upload size={18} aria-hidden /> New phone? Restore a backup
            </button>
            <input
              ref={fileRef}
              type="file"
              accept=".json,.zip,application/json,application/zip"
              className="hidden"
              aria-label="Backup file"
              onChange={(e) => e.target.files?.[0] && restore(e.target.files[0])}
            />
          </div>
        )}

        {step === 1 && (
          <div className="animate-fade-in space-y-5 pt-2">
            <h1 className="text-[28px] font-bold tracking-tight">About you</h1>
            <Field label="Name">
              <TextInput value={f.name} onChange={(e) => set('name', e.target.value)} placeholder="What should we call you?" autoComplete="given-name" />
            </Field>
            <div>
              <span className="mb-1.5 block text-[14px] font-semibold text-muted">Sex</span>
              <Segmented
                label="Sex"
                value={f.sex}
                onChange={(v) => set('sex', v)}
                options={[
                  { value: 'male', label: 'Male' },
                  { value: 'female', label: 'Female' },
                  { value: 'other', label: 'Other' },
                ]}
              />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <NumberBox label="Age" value={f.age} onChange={(v) => set('age', v)} step={1} min={14} max={90} suffix="years" inputMode="numeric" />
              <NumberBox label="Height" value={f.heightCm} onChange={(v) => set('heightCm', v)} step={1} min={120} max={220} suffix={`cm · ${ft}′${inch}″`} inputMode="numeric" />
              <NumberBox label="Current weight" value={f.weightKg} onChange={(v) => set('weightKg', v)} step={0.5} min={30} max={250} suffix="kg" />
              <NumberBox label="Goal weight" value={f.goalKg} onChange={(v) => set('goalKg', v)} step={0.5} min={30} max={250} suffix="kg" />
            </div>
            <Field label="Target date (optional)">
              <TextInput type="date" value={f.targetDate} onChange={(e) => set('targetDate', e.target.value)} min={format(new Date(), 'yyyy-MM-dd')} />
            </Field>
            <div className="rounded-card border border-info/30 bg-info/10 p-4 text-[15px]">
              <p>{pace.text}</p>
              {pace.warn && <p className="mt-2 text-warning">{pace.warn}</p>}
            </div>
          </div>
        )}

        {step === 2 && (
          <div className="animate-fade-in space-y-6 pt-2">
            <h1 className="text-[28px] font-bold tracking-tight">Your week</h1>
            <div>
              <p className="mb-2 text-[14px] font-semibold text-muted">Training days</p>
              <div className="flex flex-wrap gap-2">
                {WEEKDAYS.map((w) => (
                  <Chip
                    key={w}
                    active={f.days.includes(w)}
                    disabled={f.closed === w}
                    className="min-w-[56px] justify-center disabled:opacity-30"
                    onClick={() => set('days', f.days.includes(w) ? f.days.filter((d) => d !== w) : [...f.days, w])}
                  >
                    {WEEKDAY_LABEL[w]}
                  </Chip>
                ))}
              </div>
              {mode === 'template' && f.days.length !== 5 && (
                <p className="mt-2 text-caption text-muted">The ready plan has 5 sessions; we'll map the first {Math.min(5, f.days.length)} onto your days.</p>
              )}
            </div>
            <Field label="Usual session time">
              <TextInput type="time" value={f.sessionTime} onChange={(e) => set('sessionTime', e.target.value)} />
            </Field>
            <div>
              <p className="mb-2 text-[14px] font-semibold text-muted">Gym closed on</p>
              <div className="flex flex-wrap gap-2">
                <Chip active={f.closed === ''} onClick={() => set('closed', '')}>
                  Never
                </Chip>
                {WEEKDAYS.map((w) => (
                  <Chip
                    key={w}
                    active={f.closed === w}
                    onClick={() => {
                      set('closed', w);
                      set('days', f.days.filter((d) => d !== w));
                    }}
                  >
                    {WEEKDAY_LABEL[w]}
                  </Chip>
                ))}
              </div>
            </div>
          </div>
        )}

        {step === 3 && (
          <div className="animate-fade-in space-y-6 pt-2">
            <h1 className="text-[28px] font-bold tracking-tight">Food</h1>
            <div>
              <p className="mb-2 text-[14px] font-semibold text-muted">Diet</p>
              <div className="flex flex-wrap gap-2">
                {DIETS.map((d) => (
                  <Chip key={d.v} active={f.diet === d.v} onClick={() => set('diet', d.v)}>
                    {d.l}
                  </Chip>
                ))}
              </div>
            </div>
            <div>
              <p className="mb-2 text-[14px] font-semibold text-muted">Avoid / intolerant to</p>
              <div className="flex flex-wrap gap-2">
                {INTOLERANCES.map((i) => (
                  <Chip key={i} active={f.intolerances.includes(i)} onClick={() => set('intolerances', f.intolerances.includes(i) ? f.intolerances.filter((x) => x !== i) : [...f.intolerances, i])}>
                    {i}
                  </Chip>
                ))}
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <NumberBox
                label="Calories / day"
                value={f.targetsTouched ? f.kcal : mode === 'template' ? 2000 : suggested.kcal}
                onChange={(v) => setF((s) => ({ ...s, kcal: v, protein: s.targetsTouched ? s.protein : mode === 'template' ? 150 : suggested.proteinG, targetsTouched: true }))}
                step={50}
                min={1200}
                max={5000}
                suffix="kcal"
                inputMode="numeric"
              />
              <NumberBox
                label="Protein / day"
                value={f.targetsTouched ? f.protein : mode === 'template' ? 150 : suggested.proteinG}
                onChange={(v) => setF((s) => ({ ...s, protein: v, kcal: s.targetsTouched ? s.kcal : mode === 'template' ? 2000 : suggested.kcal, targetsTouched: true }))}
                step={5}
                min={40}
                max={300}
                suffix="g"
                inputMode="numeric"
              />
            </div>
            <p className="flex gap-2 text-caption text-muted">
              <Sparkles size={16} className="shrink-0 text-primary-ink" aria-hidden />
              Suggested from your numbers: about {suggested.kcal} kcal and {suggested.proteinG} g protein. You can change these any time.
            </p>
          </div>
        )}
      </main>

      <footer className="px-5 pb-[calc(16px+env(safe-area-inset-bottom))] pt-2">
        {step < 3 ? (
          <Button size="lg" block onClick={() => setStep(step + 1)}>
            {step === 0 ? 'Get started' : 'Continue'}
          </Button>
        ) : (
          <Button size="lg" block onClick={finish} disabled={busy}>
            {busy ? 'Setting up…' : "Let's train"}
          </Button>
        )}
      </footer>
    </div>
  );
}

function ChoiceCard({ selected, onClick, title, body, badge }: { selected: boolean; onClick: () => void; title: string; body: string; badge?: string }) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={onClick}
      className={`flex w-full items-start gap-3 rounded-card border p-4 text-left transition-colors ${selected ? 'border-primary bg-primary/10' : 'border-line bg-surface'}`}
    >
      <span className={`mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2 ${selected ? 'border-primary bg-primary text-on-primary' : 'border-line'}`}>
        {selected && <Check size={14} strokeWidth={3} aria-hidden />}
      </span>
      <span>
        <span className="flex items-center gap-2 text-[17px] font-semibold">
          {title}
          {badge && <span className="rounded-full bg-primary/20 px-2 py-0.5 text-[12px] font-bold text-primary-ink">{badge}</span>}
        </span>
        <span className="mt-1 block text-[15px] text-muted">{body}</span>
      </span>
    </button>
  );
}

function NumberBox(props: { label: string; value: number; onChange: (v: number) => void; step: number; min: number; max: number; suffix: string; inputMode?: 'decimal' | 'numeric' }) {
  return (
    <div>
      <span className="mb-1.5 block text-[14px] font-semibold text-muted">{props.label}</span>
      <div className="rounded-btn border border-line bg-surface px-1 py-1">
        <Stepper label={props.label} value={props.value} onChange={props.onChange} step={props.step} min={props.min} max={props.max} suffix={props.suffix} inputMode={props.inputMode} decimals={1} />
      </div>
    </div>
  );
}
