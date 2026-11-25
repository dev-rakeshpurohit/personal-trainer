import { addDays, format, parseISO } from 'date-fns';
import { Check, Dumbbell, HeartPulse, Moon, Zap } from 'lucide-react';
import { useMemo } from 'react';
import { Chip } from '@/components/ui';
import { Field, TextInput } from '@/components/Field';
import { Segmented } from '@/components/Segmented';
import { Stepper } from '@/components/Stepper';
import { previewProgram, staticLibrary } from '@/data/plan-builder';
import { dietTargets, generateDiet } from '@/domain/dietGen';
import { EQUIPMENT, PRESETS } from '@/domain/equipment';
import { GOALS } from '@/domain/generator';
import { cmToFtIn } from '@/domain/units';
import type { DietType, Experience } from '@/domain/types';
import { WEEKDAYS, WEEKDAY_LABEL } from '@/domain/types';
import type { SetupDraft } from './draft';

type Set = <K extends keyof SetupDraft>(k: K, v: SetupDraft[K]) => void;
interface StepProps {
  d: SetupDraft;
  set: Set;
}

export const H = ({ children, sub }: { children: React.ReactNode; sub?: string }) => (
  <div className="mb-4">
    <h1 className="text-[28px] font-bold leading-tight tracking-tight">{children}</h1>
    {sub && <p className="mt-1 text-[15px] text-muted">{sub}</p>}
  </div>
);

const EXP: { v: Experience; l: string; s: string }[] = [
  { v: 'beginner', l: 'New to lifting', s: 'Under 6 months, or coming back after a long break' },
  { v: 'intermediate', l: 'Some experience', s: '6 months to 2 years of regular training' },
  { v: 'advanced', l: 'Experienced', s: '2+ years, comfortable with barbell lifts' },
];

export function GoalStep({ d, set }: StepProps) {
  return (
    <div className="animate-fade-in">
      <H sub="We'll shape your training and food around this. You can change it any time.">Your goal</H>
      <div className="grid grid-cols-2 gap-2">
        {GOALS.map((g) => (
          <button
            key={g.id}
            type="button"
            aria-pressed={d.goal === g.id}
            onClick={() => set('goal', g.id)}
            className={`flex min-h-[96px] flex-col items-start justify-between rounded-card border p-3 text-left transition-colors ${d.goal === g.id ? 'border-primary bg-primary/10' : 'border-line bg-surface'} ${g.id === 'general' ? 'col-span-2' : ''}`}
          >
            <span className="text-[26px]" aria-hidden>
              {g.emoji}
            </span>
            <span>
              <span className="block font-bold">{g.label}</span>
              <span className="block text-caption text-muted">{g.sub}</span>
            </span>
          </button>
        ))}
      </div>
      <p className="mb-2 mt-6 text-[14px] font-semibold text-muted">Training experience</p>
      <div className="space-y-2">
        {EXP.map((e) => (
          <button
            key={e.v}
            type="button"
            aria-pressed={d.experience === e.v}
            onClick={() => set('experience', e.v)}
            className={`flex min-h-[60px] w-full items-center gap-3 rounded-card border px-4 py-2 text-left ${d.experience === e.v ? 'border-primary bg-primary/10' : 'border-line bg-surface'}`}
          >
            <span className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2 ${d.experience === e.v ? 'border-primary bg-primary text-on-primary' : 'border-line'}`}>
              {d.experience === e.v && <Check size={14} strokeWidth={3} aria-hidden />}
            </span>
            <span>
              <span className="block font-semibold">{e.l}</span>
              <span className="block text-caption text-muted">{e.s}</span>
            </span>
          </button>
        ))}
      </div>
    </div>
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

export function AboutStep({ d, set, showName = true }: StepProps & { showName?: boolean }) {
  const { ft, inch } = cmToFtIn(d.heightCm);
  const pace = useMemo(() => {
    const toLose = d.weightKg - d.goalKg;
    if (toLose <= 0) return { text: d.goal === 'muscle' ? 'Aiming to gain: about 0.25–0.5 kg a month keeps it mostly muscle.' : 'Goal is at or above your current weight: we will focus on strength and body composition.' };
    const fast = addDays(new Date(), Math.round((toLose / 0.75) * 7));
    const slow = addDays(new Date(), Math.round((toLose / 0.5) * 7));
    let warn: string | undefined;
    if (d.targetDate) {
      const weeks = (parseISO(d.targetDate).getTime() - Date.now()) / (7 * 864e5);
      const rate = toLose / Math.max(weeks, 0.1);
      if (rate > 1) warn = `That date needs ${rate.toFixed(1)} kg/week, which is a lot. Around ${format(slow, 'MMM yyyy')} is kinder and more likely to stick.`;
    }
    return { text: `At a healthy 0.5–0.75 kg a week you'd reach ${d.goalKg} kg between ${format(fast, 'MMM d')} and ${format(slow, 'MMM d, yyyy')}.`, warn };
  }, [d.weightKg, d.goalKg, d.targetDate, d.goal]);
  return (
    <div className="animate-fade-in space-y-5">
      <H sub="Stored only on this phone.">About you</H>
      {showName && (
        <Field label="Name">
          <TextInput value={d.name} onChange={(e) => set('name', e.target.value)} placeholder="What should we call you?" autoComplete="given-name" />
        </Field>
      )}
      <div>
        <span className="mb-1.5 block text-[14px] font-semibold text-muted">Sex</span>
        <Segmented label="Sex" value={d.sex} onChange={(v) => set('sex', v)} options={[{ value: 'male', label: 'Male' }, { value: 'female', label: 'Female' }, { value: 'other', label: 'Other' }]} />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <NumberBox label="Age" value={d.age} onChange={(v) => set('age', v)} step={1} min={14} max={90} suffix="years" inputMode="numeric" />
        <NumberBox label="Height" value={d.heightCm} onChange={(v) => set('heightCm', v)} step={1} min={120} max={220} suffix={`cm · ${ft}′${inch}″`} inputMode="numeric" />
        <NumberBox label="Current weight" value={d.weightKg} onChange={(v) => set('weightKg', v)} step={0.5} min={30} max={250} suffix="kg" />
        <NumberBox label="Goal weight" value={d.goalKg} onChange={(v) => set('goalKg', v)} step={0.5} min={30} max={250} suffix="kg" />
        <NumberBox label="Waist (optional)" value={d.waistCm ?? 0} onChange={(v) => set('waistCm', v || undefined)} step={0.5} min={0} max={200} suffix="cm at navel" />
        <Field label="Target date (optional)">
          <TextInput type="date" value={d.targetDate} onChange={(e) => set('targetDate', e.target.value)} min={format(new Date(), 'yyyy-MM-dd')} />
        </Field>
      </div>
      <div className="rounded-card border border-info/30 bg-info/10 p-4 text-[15px]">
        <p>{pace.text}</p>
        {pace.warn && <p className="mt-2 text-warning">{pace.warn}</p>}
      </div>
    </div>
  );
}

const LENGTHS = [30, 45, 60, 75, 90];
export function ScheduleStep({ d, set, templateMode }: StepProps & { templateMode?: boolean }) {
  return (
    <div className="animate-fade-in space-y-6">
      <H sub="Pick what you can keep up on a busy week, not your best week.">Your week</H>
      <div>
        <p className="mb-2 text-[14px] font-semibold text-muted">Training days ({d.days.length})</p>
        <div className="flex flex-wrap gap-2">
          {WEEKDAYS.map((w) => (
            <Chip
              key={w}
              active={d.days.includes(w)}
              disabled={d.closed === w}
              className="min-w-[56px] justify-center disabled:opacity-30"
              onClick={() => set('days', d.days.includes(w) ? d.days.filter((x) => x !== w) : [...d.days, w])}
            >
              {WEEKDAY_LABEL[w]}
            </Chip>
          ))}
        </div>
        {templateMode && d.days.length !== 5 && <p className="mt-2 text-caption text-muted">The ready plan has 5 sessions; we'll map the first {Math.min(5, d.days.length)} onto your days.</p>}
      </div>
      {!templateMode && (
        <div>
          <p className="mb-2 text-[14px] font-semibold text-muted">Time per session</p>
          <div className="flex flex-wrap gap-2">
            {LENGTHS.map((m) => (
              <Chip key={m} active={d.sessionMin === m} onClick={() => set('sessionMin', m)}>
                {m} min
              </Chip>
            ))}
          </div>
          <p className="mt-2 text-caption text-muted">Short on time some days? Every session also has an Express (~40 min) version.</p>
        </div>
      )}
      <Field label="Usual session time">
        <TextInput type="time" value={d.sessionTime} onChange={(e) => set('sessionTime', e.target.value)} />
      </Field>
      <div>
        <p className="mb-2 text-[14px] font-semibold text-muted">Gym closed on</p>
        <div className="flex flex-wrap gap-2">
          <Chip active={d.closed === ''} onClick={() => set('closed', '')}>
            Never
          </Chip>
          {WEEKDAYS.map((w) => (
            <Chip
              key={w}
              active={d.closed === w}
              onClick={() => {
                set('closed', w);
                set('days', d.days.filter((x) => x !== w));
              }}
            >
              {WEEKDAY_LABEL[w]}
            </Chip>
          ))}
        </div>
      </div>
    </div>
  );
}

export function EquipmentStep({ d, set }: StepProps) {
  const toggle = (id: string) => set('equipment', d.equipment.includes(id) ? d.equipment.filter((x) => x !== id) : [...d.equipment, id]);
  const preset = (Object.keys(PRESETS) as (keyof typeof PRESETS)[]).find((k) => PRESETS[k].length === d.equipment.length && PRESETS[k].every((x) => d.equipment.includes(x)));
  const usable = useMemo(() => staticLibrary().filter((e) => e.pattern && (e.alternates || e.level != null)).length, []);
  return (
    <div className="animate-fade-in">
      <H sub="Repmate only ever plans exercises you can actually do here. Bodyweight moves are always included.">Your gym</H>
      <div className="mb-4 grid grid-cols-3 gap-2">
        {(
          [
            ['full_gym', 'Full gym'],
            ['dumbbells_only', 'Dumbbells'],
            ['home', 'Home'],
          ] as const
        ).map(([k, l]) => (
          <button key={k} type="button" aria-pressed={preset === k} onClick={() => set('equipment', [...PRESETS[k]])} className={`min-h-[52px] rounded-btn border text-[15px] font-semibold ${preset === k ? 'border-primary bg-primary/15 text-primary-ink' : 'border-line bg-surface'}`}>
            {l}
          </button>
        ))}
      </div>
      <ul className="divide-y divide-line/50 overflow-hidden rounded-card border border-line/50 bg-surface">
        {EQUIPMENT.map((e) => {
          const on = d.equipment.includes(e.id);
          return (
            <li key={e.id}>
              <button type="button" role="checkbox" aria-checked={on} onClick={() => toggle(e.id)} className="flex min-h-[56px] w-full items-center gap-3 px-4 text-left">
                <span className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-md border-2 ${on ? 'border-primary bg-primary text-on-primary' : 'border-line'}`}>{on && <Check size={14} strokeWidth={3} aria-hidden />}</span>
                <span className="min-w-0 flex-1">
                  <span className="block font-medium">{e.label}</span>
                  {e.hint && <span className="block text-caption text-muted">{e.hint}</span>}
                </span>
              </button>
            </li>
          );
        })}
      </ul>
      <p className="mt-2 text-caption text-muted">{usable} exercises in the library; anything needing missing equipment is swapped for an alternate or left out.</p>
    </div>
  );
}

const DIETS: { v: DietType; l: string }[] = [
  { v: 'veg', l: 'Vegetarian' },
  { v: 'veg_egg', l: 'Veg + eggs' },
  { v: 'nonveg', l: 'Non-veg' },
  { v: 'vegan', l: 'Vegan' },
];
const INTOL = ['lactose', 'paneer', 'gluten', 'nuts', 'soy', 'eggs'];

export function FoodStep({ d, set, templateMode }: StepProps & { templateMode?: boolean }) {
  const t = dietTargets({ sex: d.sex, age: d.age, heightCm: d.heightCm, weightKg: d.weightKg, goalWeightKg: d.goalKg, goal: d.goal, trainingDays: d.days.length });
  const sk = templateMode ? 2000 : t.kcal;
  const sp = templateMode ? 150 : t.proteinG;
  return (
    <div className="animate-fade-in space-y-6">
      <H sub="Meals are built from everyday Indian food and scaled to your numbers.">Food</H>
      <div>
        <p className="mb-2 text-[14px] font-semibold text-muted">Diet</p>
        <div className="flex flex-wrap gap-2">
          {DIETS.map((x) => (
            <Chip key={x.v} active={d.diet === x.v} onClick={() => set('diet', x.v)}>
              {x.l}
            </Chip>
          ))}
        </div>
      </div>
      <div>
        <p className="mb-2 text-[14px] font-semibold text-muted">Avoid / intolerant to</p>
        <div className="flex flex-wrap gap-2">
          {INTOL.map((i) => (
            <Chip key={i} active={d.intolerances.includes(i)} onClick={() => set('intolerances', d.intolerances.includes(i) ? d.intolerances.filter((x) => x !== i) : [...d.intolerances, i])}>
              {i}
            </Chip>
          ))}
        </div>
      </div>
      <div className="grid grid-cols-2 gap-4">
        <NumberBox label="Calories / day" value={d.kcal ?? sk} onChange={(v) => set('kcal', v)} step={50} min={1200} max={5000} suffix="kcal" inputMode="numeric" />
        <NumberBox label="Protein / day" value={d.protein ?? sp} onChange={(v) => set('protein', v)} step={5} min={40} max={300} suffix="g" inputMode="numeric" />
      </div>
      <p className="text-caption text-muted">
        Suggested for your goal: about {t.kcal.toLocaleString()} kcal and {t.proteinG} g protein (Mifflin–St Jeor × activity, protein by body weight).{' '}
        {(d.kcal != null || d.protein != null) && (
          <button
            type="button"
            className="font-semibold text-primary-ink underline"
            onClick={() => {
              set('kcal', undefined);
              set('protein', undefined);
            }}
          >
            Use suggested
          </button>
        )}
      </p>
    </div>
  );
}

const ICON = { strength: Dumbbell, cardio: HeartPulse, conditioning: Zap, rest: Moon, active_recovery: HeartPulse };
export function PlanPreview({ d }: { d: SetupDraft }) {
  const prog = useMemo(() => previewProgram({ goal: d.goal, experience: d.experience, trainingDays: d.days, sessionMin: d.sessionMin, equipment: d.equipment }), [d.goal, d.experience, d.days, d.sessionMin, d.equipment]);
  const diet = useMemo(
    () =>
      generateDiet({ sex: d.sex, age: d.age, heightCm: d.heightCm, weightKg: d.weightKg, goalWeightKg: d.goalKg, goal: d.goal, trainingDays: d.days.length, dietType: d.diet, intolerances: d.intolerances, kcalOverride: d.kcal, proteinOverride: d.protein }),
    [d],
  );
  const lib = useMemo(() => new Map(staticLibrary().map((e) => [e.id, e])), []);
  return (
    <div className="animate-fade-in space-y-3">
      <H sub="Everything is editable later in More → Workout plan / Diet plan.">Your plan</H>
      <div className="rounded-card border border-primary/40 bg-primary/[0.07] p-4">
        <p className="text-[13px] font-bold uppercase tracking-wider text-primary-ink">Training</p>
        <p className="text-[19px] font-bold">{prog.name}</p>
        <p className="text-caption text-muted">8-week wave with a deload · auto-progression · {d.sessionMin} min sessions</p>
      </div>
      <ul className="space-y-1.5">
        {prog.days.map((day) => {
          const Icon = ICON[day.type];
          return (
            <li key={day.weekday} className="flex items-start gap-3 rounded-btn bg-surface px-3 py-2.5">
              <span className="w-9 shrink-0 pt-0.5 text-[13px] font-bold text-muted">{WEEKDAY_LABEL[day.weekday]}</span>
              <Icon size={18} className={`mt-0.5 shrink-0 ${day.exercises.length ? 'text-primary-ink' : 'text-muted'}`} aria-hidden />
              <span className="min-w-0 flex-1">
                <span className="block font-semibold">{day.title}</span>
                {day.exercises.length > 0 && <span className="block text-caption text-muted">{day.exercises.map((e) => lib.get(e.exerciseId)?.name).join(' · ')}</span>}
              </span>
            </li>
          );
        })}
      </ul>
      <div className="rounded-card border border-success/40 bg-success/[0.07] p-4">
        <p className="text-[13px] font-bold uppercase tracking-wider text-success">Food</p>
        <p className="text-[19px] font-bold">
          {diet.kcalTarget.toLocaleString()} kcal · {diet.proteinTargetG} g protein
        </p>
        <p className="text-caption text-muted">{diet.meals.filter((m) => !m.optional).length} meals a day, with swaps and rotating snacks</p>
      </div>
    </div>
  );
}

