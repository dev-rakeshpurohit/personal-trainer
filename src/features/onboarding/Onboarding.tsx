import { format } from 'date-fns';
import { ArrowLeft, Check, Dumbbell, Sparkles, Upload } from 'lucide-react';
import { useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { Button } from '@/components/ui';
import { db, setMeta } from '@/data/db';
import { useProfile } from '@/data/hooks';
import { upsertBody } from '@/data/repo';
import { isUnlocked } from '@/lib/access';
import { requestPersistence } from '@/lib/storage';
import { useUI } from '@/store/ui';
import { defaultDraft, draftFromProfile, profileFromDraft, type SetupDraft } from './draft';
import { Gate } from './Gate';
import { AboutStep, EquipmentStep, FoodStep, GoalStep, PlanPreview, ScheduleStep } from './steps';

type Mode = 'generated' | 'template' | 'blank';
type StepId = 'welcome' | 'goal' | 'about' | 'schedule' | 'equipment' | 'food' | 'review';
const FLOW: Record<Mode, StepId[]> = {
  generated: ['welcome', 'goal', 'about', 'schedule', 'equipment', 'food', 'review'],
  template: ['welcome', 'about', 'schedule', 'equipment', 'food'],
  blank: ['welcome', 'about', 'schedule', 'equipment', 'food'],
};

export default function Onboarding() {
  const profile = useProfile();
  const [unlocked, setUnlocked] = useState(() => isUnlocked());
  if (profile === undefined) return null;
  if (!unlocked && !profile) return <Gate onUnlock={() => setUnlocked(true)} />;
  return <Wizard existing={profile ?? undefined} />;
}

function Wizard({ existing }: { existing?: import('@/domain/types').Profile }) {
  const nav = useNavigate();
  const [params] = useSearchParams();
  const fresh = params.get('fresh') === '1' && !!existing;
  const toast = useUI((s) => s.toast);
  const [mode, setMode] = useState<Mode>('generated');
  const [i, setI] = useState(0);
  const [busy, setBusy] = useState(false);
  const [d, setD] = useState<SetupDraft>(() => (existing ? draftFromProfile(existing) : defaultDraft()));
  const set = <K extends keyof SetupDraft>(k: K, v: SetupDraft[K]) => setD((s) => ({ ...s, [k]: v }));
  const fileRef = useRef<HTMLInputElement>(null);
  const steps = FLOW[mode];
  const step = steps[i];

  async function finish() {
    setBusy(true);
    try {
      const builder = await import('@/data/plan-builder');
      const seed = await import('@/data/seed-import');
      const draft = mode === 'template' ? { ...d, goal: 'lean' as const, sessionMin: 75 } : d;
      let p = profileFromDraft(draft, existing ? { ...existing } : {});
      p = { ...p, planSource: mode, dietSource: mode === 'generated' ? 'generated' : mode };
      await builder.ensureLibrary();
      if (mode === 'generated') {
        await builder.saveGeneratedProgram(p);
        const diet = await builder.saveGeneratedDiet(p, d.kcal, d.protein);
        p = { ...p, kcalTarget: diet.kcalTarget, proteinTargetG: diet.proteinTargetG };
      } else if (mode === 'template') {
        await seed.importProgramTemplate({ trainingDays: p.trainingDays });
        const changes = await builder.adaptActivePlanToEquipment(builder.equipmentOf(p));
        await seed.importDietTemplate();
        const plan = await db.dietPlans.filter((x) => x.active).first();
        const kcal = d.kcal ?? 2000;
        const protein = d.protein ?? 150;
        if (plan) await db.dietPlans.update(plan.id, { kcalTarget: kcal, proteinTargetG: protein });
        p = { ...p, kcalTarget: kcal, proteinTargetG: protein };
        if (changes.length) toast(`Adapted to your gym: ${changes.length} exercise change${changes.length > 1 ? 's' : ''}`);
      } else {
        const t = (await import('@/domain/dietGen')).dietTargets({ sex: p.sex, age: d.age, heightCm: p.heightCm, weightKg: p.startWeightKg, goalWeightKg: p.goalWeightKg, goal: p.goal ?? 'general', trainingDays: p.trainingDays.length });
        p = { ...p, kcalTarget: d.kcal ?? t.kcal, proteinTargetG: d.protein ?? t.proteinG };
        await seed.createBlankProgram(p.trainingDays, p.kcalTarget, p.proteinTargetG);
      }
      await db.profile.put(p);
      const today = format(new Date(), 'yyyy-MM-dd');
      await upsertBody(today, { weightKg: d.weightKg, ...(d.waistCm ? { waistCm: d.waistCm } : {}) });
      if (d.closed) await setMeta('gymClosedDay', d.closed);
      if (!existing) await setMeta('onboardedAt', new Date().toISOString());
      await setMeta('setupChangedAt', new Date().toISOString());
      await requestPersistence();
      nav(existing ? '/today' : '/today?welcome=1', { replace: true });
      if (existing) toast('Fresh plan ready. Your history is kept.', { tone: 'success' });
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

  const last = i === steps.length - 1;
  return (
    <div className="app-shell flex flex-col bg-bg">
      <header className="pt-safe">
        <div className="flex h-14 items-center gap-2 px-2">
          {i > 0 || fresh ? (
            <button type="button" aria-label="Back" onClick={() => (i > 0 ? setI(i - 1) : nav('/more/setup'))} className="flex h-12 w-12 items-center justify-center rounded-full active:bg-surface2">
              <ArrowLeft size={22} />
            </button>
          ) : (
            <div className="w-12" />
          )}
          <div className="flex flex-1 justify-center gap-1.5" aria-label={`Step ${i + 1} of ${steps.length}`}>
            {steps.map((s, k) => (
              <span key={s} className={`h-1.5 rounded-full transition-all duration-300 ${k <= i ? 'w-7 bg-primary' : 'w-3.5 bg-line'}`} />
            ))}
          </div>
          {i > 0 && !last ? (
            <button type="button" onClick={finish} disabled={busy} className="h-12 min-w-12 px-3 text-[15px] font-semibold text-muted">
              Skip
            </button>
          ) : (
            <div className="w-12" />
          )}
        </div>
      </header>

      <main className="flex-1 overflow-y-auto px-5 pb-6 pt-2">
        {step === 'welcome' && (
          <div className="animate-fade-in pt-4">
            <div className="mb-6 flex h-16 w-16 items-center justify-center rounded-[20px] bg-gradient-to-br from-[#FF9A3D] to-[#FF5E0E] shadow-[0_12px_40px_-10px_rgba(255,122,26,0.7)]">
              <Dumbbell size={32} className="text-[#0B0F14]" strokeWidth={2.4} aria-hidden />
            </div>
            <h1 className="text-[34px] font-bold leading-[1.1] tracking-tight">
              {fresh ? 'Start fresh.' : 'Your coach.'}
              <br />
              <span className="text-primary-ink">{fresh ? 'Keep your history.' : 'No signal needed.'}</span>
            </h1>
            <p className="mt-3 text-[17px] text-muted">
              {fresh ? 'Build a new plan from new settings. Your sessions, meals and weigh-ins stay.' : 'Tell it your goal, your gym and your week. It builds the plan, remembers every set and adjusts as you go. Everything stays on this phone.'}
            </p>
            <div className="mt-7 space-y-3">
              <ChoiceCard selected={mode === 'generated'} onClick={() => setMode('generated')} title="Build my plan" badge="Recommended" body="Goal, measurements, schedule and equipment → a personal training and diet plan." />
              <ChoiceCard selected={mode === 'template'} onClick={() => setMode('template')} title="Lean & Athletic template" body="A trainer-designed 5-day plan + the Veg + eggs 2,000 kcal diet, adapted to your equipment." />
              <ChoiceCard selected={mode === 'blank'} onClick={() => setMode('blank')} title="Start blank" body="Pick your days and build your own workouts and meals." />
            </div>
            {!fresh && (
              <>
                <button type="button" onClick={() => fileRef.current?.click()} className="mt-6 flex min-h-[48px] items-center gap-2 text-[15px] font-semibold text-primary-ink">
                  <Upload size={18} aria-hidden /> New phone? Restore a backup
                </button>
                <input ref={fileRef} type="file" accept=".json,.zip,application/json,application/zip" className="hidden" aria-label="Backup file" onChange={(e) => e.target.files?.[0] && restore(e.target.files[0])} />
              </>
            )}
          </div>
        )}
        {step === 'goal' && <GoalStep d={d} set={set} />}
        {step === 'about' && <AboutStep d={d} set={set} />}
        {step === 'schedule' && <ScheduleStep d={d} set={set} templateMode={mode === 'template'} />}
        {step === 'equipment' && <EquipmentStep d={d} set={set} />}
        {step === 'food' && <FoodStep d={d} set={set} templateMode={mode === 'template'} />}
        {step === 'review' && <PlanPreview d={d} />}
      </main>

      <footer className="px-5 pb-[calc(16px+env(safe-area-inset-bottom))] pt-2">
        {last ? (
          <Button size="lg" block onClick={finish} disabled={busy}>
            {busy ? 'Building your plan…' : (
              <>
                <Sparkles size={20} aria-hidden /> {fresh ? 'Use this plan' : "Let's train"}
              </>
            )}
          </Button>
        ) : (
          <Button size="lg" block onClick={() => setI(i + 1)}>
            {step === 'welcome' ? 'Get started' : 'Continue'}
          </Button>
        )}
      </footer>
    </div>
  );
}

function ChoiceCard({ selected, onClick, title, body, badge }: { selected: boolean; onClick: () => void; title: string; body: string; badge?: string }) {
  return (
    <button type="button" aria-pressed={selected} onClick={onClick} className={`flex w-full items-start gap-3 rounded-card border p-4 text-left transition-colors ${selected ? 'border-primary bg-primary/10' : 'border-line bg-surface'}`}>
      <span className={`mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2 ${selected ? 'border-primary bg-primary text-on-primary' : 'border-line'}`}>{selected && <Check size={14} strokeWidth={3} aria-hidden />}</span>
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
