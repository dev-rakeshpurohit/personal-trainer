import { useLiveQuery } from 'dexie-react-hooks';
import { AlertTriangle, Dumbbell, Lock, Salad, Sparkles, WifiOff, X } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { BackButton } from '@/components/BackButton';
import { Segmented } from '@/components/Segmented';
import { Button, Card, Chip, PageHeader, SectionTitle } from '@/components/ui';
import { db } from '@/data/db';
import { saveAiDiet, saveAiWorkout } from '@/data/plan-builder';
import { askCoach, CoachError, type CoachResult } from '@/lib/coach';
import { checkCode, storeCode, storedCode } from '@/lib/access';
import { useOnline } from '@/lib/online';
import { useUI } from '@/store/ui';

type Mode = 'new' | 'change';

const IDEAS: Record<Mode, string[]> = {
  new: [
    'Bad knee: no jumping or deep lunges',
    'Weekdays are busy, keep them under 50 min',
    'I love paneer, dal and eggs',
    'I get bored easily: lots of variety',
    'Sundays I only have resistance bands',
  ],
  change: [
    'Make Friday a 45-minute session',
    'My lower back is sore: swap risky moves',
    'More variety for upper body',
    'Higher protein without whey',
    'Add a little more cardio',
  ],
};
const STEPS = [
  'Reading your profile…',
  'Picking exercises that fit your gym…',
  'Balancing your week…',
  'Planning sets, reps and rest…',
  'Writing your meals…',
  'Checking it all adds up…',
];

export default function Coach() {
  const [params] = useSearchParams();
  const first = params.get('first') === '1';
  const nav = useNavigate();
  const online = useOnline();
  const toast = useUI((s) => s.toast);
  const hasProgram = useLiveQuery(async () => !!(await db.programs.filter((p) => p.active).first()), []);
  const [mode, setMode] = useState<Mode>(first ? 'new' : 'change');
  useEffect(() => {
    if (hasProgram === false) setMode('new');
  }, [hasProgram]);
  const [want, setWant] = useState({ workout: true, diet: true });
  const [notes, setNotes] = useState('');
  const [code, setCode] = useState('');
  const [needCode, setNeedCode] = useState(() => !storedCode());
  const [busy, setBusy] = useState(false);
  const [step, setStep] = useState(0);
  const [err, setErr] = useState<string>();
  const [res, setRes] = useState<CoachResult>();
  const [saving, setSaving] = useState(false);
  const abort = useRef<AbortController>();

  useEffect(() => {
    if (!busy) return;
    setStep(0);
    const t = setInterval(() => setStep((s) => Math.min(s + 1, STEPS.length - 1)), 3500);
    return () => clearInterval(t);
  }, [busy]);

  const ask = async () => {
    setErr(undefined);
    setRes(undefined);
    if (needCode) {
      if (!(await checkCode(code))) return setErr('That invite code isn’t right.');
      storeCode(code);
      setNeedCode(false);
    }
    abort.current = new AbortController();
    setBusy(true);
    try {
      setRes(await askCoach({ mode, want, notes, signal: abort.current.signal }));
    } catch (e) {
      if ((e as Error).name === 'AbortError') return;
      if (e instanceof CoachError && e.status === 401) setNeedCode(true);
      setErr((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const apply = async () => {
    if (!res) return;
    setSaving(true);
    try {
      const p = await db.profile.get('me');
      if (!p) return;
      let next = { ...p };
      if (res.plan.workout) {
        await saveAiWorkout(p, res.plan.workout);
        next = { ...next, planSource: 'ai' };
      }
      if (res.plan.diet) {
        await saveAiDiet(res.plan.diet);
        next = {
          ...next,
          dietSource: 'ai',
          kcalTarget: res.plan.diet.kcalTarget,
          proteinTargetG: res.plan.diet.proteinTargetG,
        };
      }
      await db.profile.put(next);
      await db.meta.put({ key: 'setupChangedAt', value: new Date().toISOString() });
      toast('Your new plan is ready. History is kept.', { tone: 'success' });
      nav(res.plan.workout ? '/train' : '/eat');
    } finally {
      setSaving(false);
    }
  };

  const exNames = useLiveQuery(async () => {
    if (!res?.plan.workout) return new Map<string, string>();
    const ids = res.plan.workout.days.flatMap((d) => d.exercises.map((e) => e.exerciseId));
    return new Map((await db.exercises.bulkGet(ids)).filter((e) => !!e).map((e) => [e!.id, e!.name]));
  }, [res]);
  const totals = useMemo(() => {
    const m = res?.plan.diet?.meals ?? [];
    return {
      kcal: Math.round(m.reduce((s, x) => s + x.kcal, 0)),
      protein: Math.round(m.reduce((s, x) => s + x.proteinG, 0)),
    };
  }, [res]);

  return (
    <div className="app-shell flex flex-col">
      <main className="flex-1 overflow-y-auto overscroll-none pb-4">
        <PageHeader
          title="AI coach"
          sub="Plans written around you"
          right={<BackButton to={first ? '/today' : '/more'} />}
        />
        <div className="space-y-3 px-4">
          {first && (
            <Card className="border-primary/40 bg-primary/[0.07]">
              <p className="font-semibold">Your starter plan is saved.</p>
              <p className="mt-1 text-[15px] text-muted">
                Tell the coach anything the form didn’t ask: injuries, likes, schedule quirks, foods. It will
                rewrite the plan around you.
              </p>
            </Card>
          )}
          {!online && (
            <p
              className="flex items-center gap-2 rounded-card bg-warning/10 p-3 text-[15px] text-warning"
              role="status"
            >
              <WifiOff size={18} aria-hidden /> The AI coach needs internet. Your current plan keeps working
              offline.
            </p>
          )}

          {!res && (
            <>
              {hasProgram && (
                <Segmented
                  value={mode}
                  onChange={(v) => setMode(v)}
                  options={[
                    { value: 'change', label: 'Change my plan' },
                    { value: 'new', label: 'New plan' },
                  ]}
                  label="What should the coach do?"
                />
              )}
              <div className="flex gap-2">
                <Chip
                  active={want.workout}
                  onClick={() => setWant((w) => ({ ...w, workout: !w.workout || !w.diet }))}
                >
                  <Dumbbell size={15} aria-hidden /> Workout
                </Chip>
                <Chip
                  active={want.diet}
                  onClick={() => setWant((w) => ({ ...w, diet: !w.diet || !w.workout }))}
                >
                  <Salad size={15} aria-hidden /> Diet
                </Chip>
              </div>
              <label className="block">
                <span className="mb-1.5 block text-[14px] font-semibold text-muted">
                  {mode === 'new' ? 'Tell your coach about you' : 'What would you like to change?'}
                </span>
                <textarea
                  value={notes}
                  onChange={(e) => setNotes(e.target.value.slice(0, 2000))}
                  rows={6}
                  placeholder={
                    mode === 'new'
                      ? 'e.g. 35, desk job, new dad. Left knee clicks on lunges. I like swimming. Mostly veg, eggs OK, no whey. Gym Tue–Sat 9:15 for an hour.'
                      : 'e.g. Thursday leg day takes too long, and I want to try kettlebells.'
                  }
                  className="w-full rounded-btn border border-line bg-surface p-3 text-[17px] leading-snug outline-none focus:border-primary"
                />
                <span className="mt-1 block text-right text-caption text-muted tnum">
                  {notes.length} / 2000
                </span>
              </label>
              <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4">
                {IDEAS[mode].map((t) => (
                  <Chip key={t} onClick={() => setNotes((n) => (n ? `${n.trim()}\n${t}` : t))}>
                    + {t}
                  </Chip>
                ))}
              </div>
              {needCode && (
                <label className="block">
                  <span className="mb-1.5 flex items-center gap-1.5 text-[14px] font-semibold text-muted">
                    <Lock size={14} aria-hidden /> Invite code (asked once)
                  </span>
                  <input
                    value={code}
                    onChange={(e) => setCode(e.target.value)}
                    placeholder="RPM-XXXX-XXXX"
                    autoCapitalize="characters"
                    className="min-h-[48px] w-full rounded-btn border border-line bg-surface px-3 text-[17px] tracking-wider outline-none focus:border-primary"
                  />
                </label>
              )}
              <p className="text-caption text-muted">
                To write the plan, your age, height, weight, goal, schedule, equipment, food preferences and
                this note are sent to an AI model through OpenRouter. Nothing else leaves your phone, and the
                plan is saved on-device.
              </p>
            </>
          )}

          {busy && (
            <Card className="text-center" aria-live="polite">
              <Sparkles size={28} className="mx-auto animate-pulse text-primary-ink" aria-hidden />
              <p className="mt-2 font-semibold">{STEPS[step]}</p>
              <p className="mt-1 text-caption text-muted">Usually 20–60 seconds.</p>
              <Button variant="ghost" className="mt-2" onClick={() => abort.current?.abort()}>
                Cancel
              </Button>
            </Card>
          )}

          {err && (
            <p
              className="flex items-start gap-2 rounded-card bg-danger/10 p-3 text-[15px] text-danger"
              role="alert"
            >
              <AlertTriangle size={18} className="mt-0.5 shrink-0" aria-hidden /> {err}
            </p>
          )}

          {res && (
            <>
              <Card>
                <p className="flex items-center gap-2 text-[13px] font-bold uppercase tracking-wider text-primary-ink">
                  <Sparkles size={15} aria-hidden /> Coach’s note
                </p>
                <p className="mt-1.5 text-[16px] leading-relaxed">
                  {res.plan.summary || 'Here’s your plan.'}
                </p>
                {res.costUsd != null && (
                  <p className="mt-2 text-caption text-muted">
                    Cost of this answer: US${res.costUsd.toFixed(4)}
                  </p>
                )}
              </Card>
              {res.plan.warnings.length > 0 && (
                <ul className="space-y-1 rounded-card bg-warning/10 p-3 text-[14px] text-warning">
                  {res.plan.warnings.map((w) => (
                    <li key={w}>• {w}</li>
                  ))}
                </ul>
              )}
              {res.plan.workout && (
                <>
                  <SectionTitle>{res.plan.workout.name}</SectionTitle>
                  <div className="space-y-2">
                    {res.plan.workout.days
                      .filter((d) => d.exercises.length)
                      .map((d) => (
                        <Card key={d.weekday} className="!p-3">
                          <p className="text-caption font-semibold text-muted">
                            {d.weekday} · {d.durationMin ?? '–'} min
                          </p>
                          <p className="font-semibold">{d.title}</p>
                          <ul className="mt-1.5 space-y-0.5 text-[15px]">
                            {d.exercises.map((e) => (
                              <li key={e.slot} className="flex gap-2">
                                <span className="w-7 shrink-0 font-semibold text-primary-ink">{e.slot}</span>
                                <span className="flex-1">{exNames?.get(e.exerciseId) ?? e.exerciseId}</span>
                                <span className="shrink-0 text-muted tnum">
                                  {e.sets}×{e.repsMin === e.repsMax ? e.repsMin : `${e.repsMin}–${e.repsMax}`}
                                  {e.unit === 'reps'
                                    ? ''
                                    : e.unit === 'seconds'
                                      ? 's'
                                      : e.unit === 'minutes'
                                        ? 'm'
                                        : 'm'}
                                </span>
                              </li>
                            ))}
                          </ul>
                          {d.notes && <p className="mt-1.5 text-caption text-muted">{d.notes}</p>}
                        </Card>
                      ))}
                    <p className="text-caption text-muted">
                      Rest days:{' '}
                      {res.plan.workout.days
                        .filter((d) => !d.exercises.length)
                        .map((d) => d.weekday)
                        .join(', ') || 'none'}
                    </p>
                  </div>
                </>
              )}
              {res.plan.diet && (
                <>
                  <SectionTitle>
                    Diet · {res.plan.diet.kcalTarget.toLocaleString()} kcal · {res.plan.diet.proteinTargetG} g
                    protein
                  </SectionTitle>
                  <div className="space-y-2">
                    {res.plan.diet.meals.map((m) => (
                      <Card key={`${m.time}-${m.meal}`} className="!p-3">
                        <p className="flex justify-between text-caption font-semibold text-muted">
                          <span>
                            {m.time} · {m.meal}
                            {m.optional ? ' · optional' : ''}
                          </span>
                          <span className="tnum">
                            {Math.round(m.kcal)} kcal · {Math.round(m.proteinG)} g
                          </span>
                        </p>
                        <p className="mt-1 text-[15px]">{m.items.join(' · ')}</p>
                        {m.rotate?.length ? (
                          <p className="mt-1 text-caption text-muted">Or: {m.rotate.join(' / ')}</p>
                        ) : null}
                      </Card>
                    ))}
                    <p className="text-caption text-muted tnum">
                      Meals add up to {totals.kcal.toLocaleString()} kcal and {totals.protein} g protein.
                    </p>
                    {res.plan.diet.tips?.length ? (
                      <ul className="space-y-1 text-[15px] text-text/85">
                        {res.plan.diet.tips.map((t) => (
                          <li key={t}>• {t}</li>
                        ))}
                      </ul>
                    ) : null}
                  </div>
                </>
              )}
            </>
          )}
        </div>
      </main>

      <footer className="border-t border-line/50 bg-bg px-4 pb-[calc(12px+env(safe-area-inset-bottom))] pt-3">
        {res ? (
          <div className="flex gap-2">
            <Button
              variant="secondary"
              onClick={() => setRes(undefined)}
              aria-label="Discard and edit the request"
            >
              <X size={18} aria-hidden />
            </Button>
            <Button variant="secondary" className="flex-1" onClick={ask} disabled={busy || !online}>
              Ask again
            </Button>
            <Button className="flex-[1.4]" onClick={apply} disabled={saving}>
              Use this plan
            </Button>
          </div>
        ) : (
          <Button
            size="lg"
            block
            onClick={ask}
            disabled={busy || !online || (mode === 'change' && !notes.trim()) || (needCode && !code.trim())}
          >
            <Sparkles size={20} aria-hidden />{' '}
            {busy ? 'Coach is writing…' : mode === 'new' ? 'Build my plan' : 'Update my plan'}
          </Button>
        )}
      </footer>
    </div>
  );
}
