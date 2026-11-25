import { ChevronRight, RefreshCcw, Sparkles, Trash2 } from 'lucide-react';
import { useMemo, useState, type ReactNode } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { BackButton } from '@/components/BackButton';
import { Toggle } from '@/components/Field';
import { Sheet } from '@/components/Sheet';
import { Button, Card, PageHeader, SectionTitle } from '@/components/ui';
import { useActiveSession, useProfile } from '@/data/hooks';
import { EQUIPMENT, PRESETS } from '@/domain/equipment';
import { GOALS } from '@/domain/generator';
import { WEEKDAY_LABEL, type Profile } from '@/domain/types';
import { useUI } from '@/store/ui';
import { draftFromProfile, profileFromDraft, type SetupDraft } from '@/features/onboarding/draft';
import { AboutStep, EquipmentStep, FoodStep, GoalStep, PlanPreview, ScheduleStep } from '@/features/onboarding/steps';

type Section = 'goal' | 'about' | 'schedule' | 'equipment' | 'food';

export default function Setup() {
  const profile = useProfile();
  if (!profile) return null;
  return <SetupInner profile={profile} />;
}

function SetupInner({ profile }: { profile: Profile }) {
  const nav = useNavigate();
  const toast = useUI((s) => s.toast);
  const active = useActiveSession();
  const original = useMemo(() => draftFromProfile(profile), [profile]);
  const [d, setD] = useState<SetupDraft>(original);
  const [open, setOpen] = useState<Section>();
  const [apply, setApply] = useState(false);
  const [busy, setBusy] = useState(false);
  const set = <K extends keyof SetupDraft>(k: K, v: SetupDraft[K]) => setD((s) => ({ ...s, [k]: v }));

  const changed = (keys: (keyof SetupDraft)[]) => keys.some((k) => JSON.stringify(d[k]) !== JSON.stringify(original[k]));
  const workoutChanged = changed(['goal', 'experience', 'days', 'sessionMin']);
  const equipmentChanged = changed(['equipment']);
  const dietChanged = changed(['diet', 'intolerances', 'kcal', 'protein', 'goal', 'weightKg', 'goalKg', 'sex', 'age', 'heightCm']);
  const dirty = JSON.stringify(d) !== JSON.stringify(original);
  const [rebuildWorkout, setRW] = useState(false);
  const [rebuildDiet, setRD] = useState(false);

  const openApply = () => {
    setRW(workoutChanged);
    setRD(dietChanged);
    setApply(true);
  };
  const doApply = async () => {
    setBusy(true);
    try {
      const { applySetup } = await import('@/data/plan-builder');
      const next = profileFromDraft(d, profile);
      const notes = await applySetup(next, { rebuildWorkout, rebuildDiet });
      toast(notes.length ? notes.slice(0, 2).join(' · ') + (notes.length > 2 ? ` (+${notes.length - 2} more)` : '') : 'Settings saved', { tone: 'success' });
      setApply(false);
      nav('/today');
    } finally {
      setBusy(false);
    }
  };

  const goal = GOALS.find((g) => g.id === d.goal);
  const eqLabel = PRESETS.full_gym.every((x) => d.equipment.includes(x)) ? 'Full gym' : `${d.equipment.length} of ${EQUIPMENT.length} items`;
  const rows: { id: Section; label: string; value: string }[] = [
    { id: 'goal', label: 'Goal & experience', value: `${goal?.label} · ${d.experience}` },
    { id: 'about', label: 'Body & measurements', value: `${d.weightKg} → ${d.goalKg} kg · ${d.heightCm} cm` },
    { id: 'schedule', label: 'Schedule', value: `${d.days.map((x) => WEEKDAY_LABEL[x]).join(' ')} · ${d.sessionMin} min` },
    { id: 'equipment', label: 'Gym equipment', value: eqLabel },
    { id: 'food', label: 'Food', value: `${d.diet.replace('_', ' + ')}${d.intolerances.length ? ` · no ${d.intolerances.join(', ')}` : ''}` },
  ];

  return (
    <div className="pb-32">
      <PageHeader title="My plan setup" sub="Change anything, then apply" right={<BackButton to="/more" />} />
      <div className="space-y-2 px-4">
        <ul className="divide-y divide-line/50 overflow-hidden rounded-card border border-line/50 bg-surface">
          {rows.map((r) => (
            <li key={r.id}>
              <button type="button" onClick={() => setOpen(r.id)} className="flex min-h-[64px] w-full items-center gap-3 px-4 text-left active:bg-surface2">
                <span className="min-w-0 flex-1">
                  <span className="block font-semibold">{r.label}</span>
                  <span className="block truncate text-caption capitalize text-muted">{r.value}</span>
                </span>
                <ChevronRight size={18} className="text-muted" aria-hidden />
              </button>
            </li>
          ))}
        </ul>

        <SectionTitle>Start fresh</SectionTitle>
        <Card className="space-y-2">
          <p className="text-[15px] text-muted">Rebuild everything from scratch with the setup wizard. Your sessions, meals and weigh-ins are kept.</p>
          <Button variant="secondary" block onClick={() => nav('/onboarding?fresh=1')} disabled={!!active}>
            <RefreshCcw size={18} aria-hidden /> New plan, keep history
          </Button>
          <Link to="/more/settings" className="flex min-h-[48px] items-center justify-center gap-2 text-[15px] font-semibold text-danger">
            <Trash2 size={16} aria-hidden /> Erase everything instead
          </Link>
        </Card>
        {active && <p className="text-center text-caption text-warning">Finish your workout in progress before changing the plan.</p>}
      </div>

      {dirty && (
        <div className="glass fixed inset-x-0 bottom-[calc(64px+env(safe-area-inset-bottom))] z-20 border-t border-line/50 px-4 py-3">
          <div className="flex gap-2">
            <Button variant="secondary" onClick={() => setD(original)}>
              Undo
            </Button>
            <Button block size="lg" onClick={openApply} disabled={!!active}>
              <Sparkles size={20} aria-hidden /> Apply changes
            </Button>
          </div>
        </div>
      )}

      <Sheet open={!!open} onClose={() => setOpen(undefined)} title={rows.find((r) => r.id === open)?.label ?? ''} tall footer={<Button block size="lg" onClick={() => setOpen(undefined)}>Done</Button>}>
        <SectionBody section={open} d={d} set={set} />
      </Sheet>

      <Sheet
        open={apply}
        onClose={() => setApply(false)}
        title="Apply changes"
        tall
        footer={
          <Button block size="lg" onClick={doApply} disabled={busy}>
            {busy ? 'Updating your plan…' : 'Apply'}
          </Button>
        }
      >
        <div className="space-y-2 pb-3">
          <Toggle checked={rebuildWorkout} onChange={setRW} label="Rebuild workout plan" sub={workoutChanged ? 'Recommended: goal, experience, days or session length changed' : 'Your current plan (and your edits) stays if off'} />
          {!rebuildWorkout && equipmentChanged && <p className="rounded-btn bg-info/10 p-3 text-[14px] text-info">Equipment changed: exercises you can't do will be swapped for alternates, never added.</p>}
          <Toggle checked={rebuildDiet} onChange={setRD} label="Rebuild diet plan" sub={dietChanged ? 'Recommended: food or body settings changed' : 'Your current meals stay if off'} />
          <p className="pt-1 text-caption text-muted">History (sessions, sets, meals, weigh-ins) is always kept.</p>
          {rebuildWorkout && (
            <div className="pt-2">
              <PlanPreview d={d} />
            </div>
          )}
        </div>
      </Sheet>
    </div>
  );
}

function SectionBody({ section, d, set }: { section?: Section; d: SetupDraft; set: <K extends keyof SetupDraft>(k: K, v: SetupDraft[K]) => void }): ReactNode {
  if (section === 'goal') return <GoalStep d={d} set={set} />;
  if (section === 'about') return <AboutStep d={d} set={set} />;
  if (section === 'schedule') return <ScheduleStep d={d} set={set} />;
  if (section === 'equipment') return <EquipmentStep d={d} set={set} />;
  if (section === 'food') return <FoodStep d={d} set={set} />;
  return null;
}
