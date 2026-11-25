import { useLiveQuery } from 'dexie-react-hooks';
import { Check, ChevronDown, ChevronLeft, ChevronRight, Lock, MoreHorizontal, Play, Plus, Repeat, Shuffle, Trash2, TrendingUp } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { DemoPlayer } from '@/components/DemoPlayer';
import { Sheet } from '@/components/Sheet';
import { Stepper } from '@/components/Stepper';
import { Button } from '@/components/ui';
import { db } from '@/data/db';
import { useActiveSession, useExerciseMap, useProfile } from '@/data/hooks';
import { detectPRs, incrementFor, suggestNext, type Suggestion } from '@/domain/progression';
import { buildFlow, nextStep, stepKey } from '@/domain/sessionFlow';
import type { ActiveSessionState, Exercise, Profile, Session, SessionExercise, SetLog } from '@/domain/types';
import { displayWeight, formatDuration, fromUserUnits, stepFor, toUserUnits } from '@/domain/units';
import { cancelRestNotification, notificationsSupported, requestNotificationPermission, scheduleRestNotification } from '@/lib/notify';
import { useWakeLock } from '@/lib/wakeLock';
import { useUI } from '@/store/ui';
import { AlternatesSheet } from './AlternatesSheet';
import { loadHistory } from './progressionData';
import { RestSheet, WorkTimer } from './RestSheet';
import { deleteSet, discardSession, finishSession, logSet, patchActive, swapExercise, updateSet } from './session';

type Draft = { weightKg?: number; reps?: number; seconds?: number; meters?: number };

export default function Player() {
  const a = useActiveSession();
  const profile = useProfile();
  const exMap = useExerciseMap();
  if (a === undefined || profile === undefined) return null;
  if (a === null || !profile) return <Navigate to="/today" replace />;
  return <PlayerInner active={a.active} session={a.session} profile={profile} exMap={exMap} />;
}

const unitLabel = (se: SessionExercise) =>
  `${se.repsMin === se.repsMax ? se.repsMax : `${se.repsMin}–${se.repsMax}`}${se.unit === 'reps' ? '' : se.unit === 'seconds' ? 's' : se.unit === 'minutes' ? ' min' : ' m'}${se.perSide ? ' / side' : ''}`;

function PlayerInner({ active, session, profile, exMap }: { active: ActiveSessionState; session: Session; profile: Profile; exMap: Map<string, Exercise> }) {
  const nav = useNavigate();
  const toast = useUI((s) => s.toast);
  const plan = useMemo(() => active.plan ?? [], [active.plan]);
  const idx = Math.min(Math.max(0, active.exerciseIdx), Math.max(0, plan.length - 1));
  const se = plan[idx];
  const ex = se ? exMap.get(se.exerciseId) : undefined;
  const units = profile.units;
  const wake = useWakeLock(true);
  const sets = useLiveQuery(() => db.sets.where('sessionId').equals(session.id).toArray(), [session.id]);
  const planned = useLiveQuery(() => (se ? db.plannedExercises.get(se.plannedExerciseId) : undefined), [se?.plannedExerciseId]);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [sugg, setSugg] = useState<Record<string, Suggestion & { last?: string }>>({});
  const [menu, setMenu] = useState(false);
  const [alts, setAlts] = useState(false);
  const [edit, setEdit] = useState<SetLog>();
  const [timer, setTimer] = useState<{ setIndex: number; target: number }>();
  const [rirFor, setRirFor] = useState<string>();
  const [cueOpen, setCueOpen] = useState(false);
  const [notes, setNotes] = useState(session.notes ?? '');
  const [, tick] = useState(0);
  const touch = useRef<{ x: number; y: number }>();

  useEffect(() => {
    const t = setInterval(() => tick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);

  const setsFor = useCallback(
    (i: number) => (sets ?? []).filter((s) => s.plannedExerciseId === plan[i]?.plannedExerciseId).sort((a, b) => a.setIndex - b.setIndex),
    [sets, plan],
  );
  const totalSets = useCallback((i: number) => (plan[i]?.sets ?? 0) + (active.extraSets?.[plan[i]?.plannedExerciseId] ?? 0), [plan, active.extraSets]);
  const flow = useMemo(() => buildFlow(plan.map((p, i) => ({ sets: totalSets(i), supersetGroup: p.supersetGroup }))), [plan, totalSets]);
  const doneKeys = useMemo(() => {
    const k = new Set<string>();
    plan.forEach((_, i) => setsFor(i).forEach((s) => k.add(stepKey({ ex: i, set: s.setIndex }))));
    return k;
  }, [plan, setsFor]);
  const allDone = flow.length > 0 && flow.every((s) => doneKeys.has(stepKey(s)));

  // progression suggestion for the current exercise (its own history, keyed by exerciseId)
  const suggKey = se ? `${idx}:${se.exerciseId}` : '';
  useEffect(() => {
    if (!se || sugg[suggKey]) return;
    let alive = true;
    void loadHistory(se.exerciseId, session.id).then((history) => {
      if (!alive) return;
      let s = suggestNext({
        planned: se,
        sets: totalSets(idx),
        history,
        targetRir: se.rir,
        increment: ex ? incrementFor(ex, profile.stepKg) : profile.stepKg.dumbbell,
        bodyweight: ex?.isBodyweight,
      });
      const painful = active.pain?.includes(se.exerciseId) || active.pain?.includes(se.originalExerciseId);
      if ((active.hold || painful) && (s.kind === 'increase' || s.kind === 'time_increase')) {
        const lastW = history[0]?.length ? Math.max(...history[0].map((x) => x.weightKg ?? 0)) || undefined : undefined;
        s = { ...s, kind: 'hold', weightKg: lastW, message: painful ? 'Pain last time: keep the weight, move carefully' : 'Holding weight today: last session felt very hard', prefill: s.prefill.map((p) => ({ ...p, weightKg: lastW ?? p.weightKg })) };
      }
      const last = history[0]
        ?.map((x) => (x.seconds != null ? `${se.unit === 'minutes' ? Math.round(x.seconds / 60) + ' min' : x.seconds + 's'}` : x.meters != null ? `${x.meters} m` : `${x.weightKg ? `${displayWeight(x.weightKg, units)} ${units} × ` : ''}${x.reps ?? ''}`))
        .join(', ');
      setSugg((m) => ({ ...m, [suggKey]: { ...s, last } }));
    });
    return () => {
      alive = false;
    };
  }, [suggKey, se, ex, idx, session.id, totalSets, profile.stepKg, active.hold, active.pain, units, sugg]);

  const cur = sugg[suggKey];
  const logged = se ? setsFor(idx) : [];
  const nextSetIdx = (() => {
    for (let s = 0; s < totalSets(idx); s++) if (!logged.some((l) => l.setIndex === s)) return s;
    return undefined;
  })();

  const draftFor = (i: number, s: number): Draft => {
    const k = `${i}:${plan[i]?.exerciseId}:${s}`;
    if (drafts[k]) return drafts[k];
    const p = sugg[`${i}:${plan[i]?.exerciseId}`]?.prefill[s] ?? sugg[`${i}:${plan[i]?.exerciseId}`]?.prefill[0];
    const prev = setsFor(i).filter((x) => plan[i] && x.exerciseId === plan[i].exerciseId).at(-1);
    const unit = plan[i]?.unit;
    const base: Draft =
      unit === 'reps'
        ? { reps: p?.reps ?? plan[i].repsMin }
        : unit === 'meters'
          ? { meters: p?.meters ?? plan[i].repsMin }
          : { seconds: p?.seconds ?? (unit === 'minutes' ? plan[i].repsMin * 60 : plan[i].repsMin) };
    return { ...base, weightKg: prev?.weightKg ?? p?.weightKg };
  };
  const setDraft = (s: number, patch: Draft) => setDrafts((d) => ({ ...d, [`${idx}:${se.exerciseId}:${s}`]: { ...draftFor(idx, s), ...patch } }));

  const go = (i: number) => {
    if (i < 0 || i >= plan.length) return;
    void patchActive({ exerciseIdx: i });
  };

  const doLog = async (setIndex: number, override?: Draft) => {
    if (!se) return;
    const v = { ...draftFor(idx, setIndex), ...override };
    if (se.unit === 'reps' && !v.reps) return toast('Enter your reps first');
    if (ex?.isBodyweight) delete v.weightKg;
    const prior = await db.sets.where('exerciseId').equals(se.exerciseId).filter((s) => !s.isWarmup).toArray();
    const row = await logSet(session.id, se, setIndex, v);
    setRirFor(se.unit === 'reps' ? row.id : undefined);

    // PR toast once per exercise per session
    const prs = detectPRs(row, prior);
    if (prs.length && !active.prShown?.includes(se.exerciseId)) {
      toast(`🏆 New PR: ${ex?.name ?? ''}${prs.includes('weight') ? ' · heaviest' : prs.includes('e1rm') ? ' · best e1RM' : ' · most reps'}`, { tone: 'pr' });
      await patchActive({ prShown: [...(active.prShown ?? []), se.exerciseId] });
    }

    const done = new Set(doneKeys).add(stepKey({ ex: idx, set: setIndex }));
    const nxt = nextStep(flow, done, { ex: idx, set: setIndex });
    const rest = nxt ? se.restSec : 0;
    const endsAt = rest > 0 ? Date.now() + rest * 1000 : undefined;
    await patchActive({ exerciseIdx: nxt?.ex ?? idx, setIdx: nxt?.set ?? setIndex, restEndsAt: endsAt ? new Date(endsAt).toISOString() : undefined, restTotalSec: rest || undefined });
    if (endsAt && profile.restTimer.notify) {
      const n = nxt ? plan[nxt.ex] : undefined;
      scheduleRestNotification(endsAt, n ? `Next: ${exMap.get(n.exerciseId)?.name ?? ''} · set ${nxt!.set + 1}` : 'Time for your next set');
    }
    if (!nxt) toast('All sets done. Finish when you are ready 💪', { tone: 'success' });
  };

  const finish = async () => {
    await finishSession(session.id, notes || undefined);
    nav(`/workout/summary/${session.id}`, { replace: true });
  };

  if (!se)
    return (
      <div className="app-shell flex flex-col items-center justify-center gap-4 p-6 text-center">
        <p className="text-title">This session has no exercises.</p>
        <Button onClick={() => discardSession(session.id).then(() => nav('/today'))}>Close</Button>
      </div>
    );

  const elapsed = (Date.now() - new Date(session.startedAt).getTime()) / 1000;
  const swapId = planned?.swapExerciseId;
  const swapped = se.exerciseId !== se.originalExerciseId;
  const partner = se.supersetGroup ? plan.find((p, i) => i !== idx && p.supersetGroup === se.supersetGroup && i > idx) ?? plan.find((p, i) => i !== idx && p.supersetGroup === se.supersetGroup) : undefined;
  const painful = active.pain?.includes(se.exerciseId) || active.pain?.includes(se.originalExerciseId);
  const restEndsAt = active.restEndsAt ? new Date(active.restEndsAt).getTime() : undefined;
  const nextName = (() => {
    const n = plan[active.exerciseIdx];
    return n ? `${n.slot} ${exMap.get(n.exerciseId)?.name ?? ''}` : undefined;
  })();
  const weightStep = stepFor(ex ? incrementFor(ex, profile.stepKg) : 2, units) / (units === 'kg' ? 2 : 1);

  return (
    <div
      className="app-shell flex flex-col bg-bg"
      onTouchStart={(e) => (touch.current = { x: e.touches[0].clientX, y: e.touches[0].clientY })}
      onTouchEnd={(e) => {
        const t = touch.current;
        if (!t) return;
        const dx = e.changedTouches[0].clientX - t.x;
        const dy = e.changedTouches[0].clientY - t.y;
        if (Math.abs(dx) > 80 && Math.abs(dy) < 40) go(idx + (dx < 0 ? 1 : -1));
        else if (dy > 120 && Math.abs(dx) < 40 && t.y < 140) nav('/today');
      }}
    >
      {/* Top bar */}
      <header className="pt-safe">
        <div className="flex h-14 items-center gap-2 px-2">
          <button type="button" onClick={() => nav('/today')} className="flex h-12 w-12 items-center justify-center rounded-full active:bg-surface2" aria-label="Minimise workout">
            <ChevronDown size={26} aria-hidden />
          </button>
          <div className="flex flex-1 flex-col items-center">
            <span className="text-[17px] font-bold tnum" aria-label="Session time">
              {formatDuration(elapsed)}
            </span>
            <div className="mt-1 flex gap-1" aria-label={`Exercise ${idx + 1} of ${plan.length}`}>
              {plan.map((p, i) => {
                const d = setsFor(i).length >= totalSets(i);
                return <span key={p.plannedExerciseId} className={`h-1.5 rounded-full transition-all ${i === idx ? 'w-5 bg-primary' : d ? 'w-1.5 bg-success' : 'w-1.5 bg-line'}`} />;
              })}
            </div>
          </div>
          {wake !== 'off' && <Lock size={16} className="text-muted" aria-label="Screen kept awake" />}
          <button type="button" onClick={() => setMenu(true)} className="flex h-12 w-12 items-center justify-center rounded-full active:bg-surface2" aria-label="Workout menu">
            <MoreHorizontal size={24} aria-hidden />
          </button>
        </div>
      </header>

      <main className={`flex-1 overflow-y-auto px-4 ${restEndsAt ? 'pb-[260px]' : 'pb-4'}`}>
        <DemoPlayer exercise={ex} className="h-[30dvh] w-full" />

        <div className="mt-3 flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="flex items-center gap-2 text-[13px] font-bold uppercase tracking-wider text-primary-ink">
              <span className="rounded-md bg-primary/15 px-1.5 py-0.5">{se.slot}</span>
              {se.isMain ? 'Main lift' : 'Accessory'}
              {swapped && <span className="text-info">· swapped</span>}
            </p>
            <h1 className="mt-1 text-[24px] font-bold leading-tight">{ex?.name ?? se.exerciseId}</h1>
            {partner && <p className="text-[15px] text-muted">then {partner.slot}: {exMap.get(partner.exerciseId)?.name}</p>}
          </div>
          <div className="flex shrink-0 gap-1">
            <button type="button" onClick={() => go(idx - 1)} disabled={idx === 0} className="flex h-12 w-12 items-center justify-center rounded-full bg-surface2 disabled:opacity-30" aria-label="Previous exercise">
              <ChevronLeft size={22} aria-hidden />
            </button>
            <button type="button" onClick={() => go(idx + 1)} disabled={idx >= plan.length - 1} className="flex h-12 w-12 items-center justify-center rounded-full bg-surface2 disabled:opacity-30" aria-label="Next exercise">
              <ChevronRight size={22} aria-hidden />
            </button>
          </div>
        </div>

        {(se.cue ?? ex?.cue) && (
          <button type="button" onClick={() => setCueOpen(!cueOpen)} className={`mt-1 block text-left text-[15px] text-text/80 ${cueOpen ? '' : 'line-clamp-2'}`} aria-expanded={cueOpen}>
            {se.cue ?? ex?.cue}
            {cueOpen && ex?.instructions?.length ? <span className="mt-1 block text-muted">{ex.instructions.join(' ')}</span> : null}
          </button>
        )}
        {se.note && <p className="mt-1 text-[14px] font-medium text-info">{se.note}</p>}

        {painful && (
          <div className="mt-2 rounded-btn border border-warning/40 bg-warning/10 p-3 text-[15px]">
            You reported pain here last time.{' '}
            <button type="button" onClick={() => setAlts(true)} className="font-semibold text-warning underline">
              Try an alternate
            </button>
          </div>
        )}

        {/* Swap chips */}
        <div className="no-scrollbar -mx-4 mt-3 flex gap-2 overflow-x-auto px-4">
          {swapped ? (
            <button type="button" onClick={() => swapExercise(active, idx, se.originalExerciseId, false)} className="flex min-h-[44px] shrink-0 items-center gap-1.5 rounded-full border border-info/50 bg-info/10 px-3.5 text-[15px] font-semibold text-info">
              <Repeat size={16} aria-hidden /> Back to {exMap.get(se.originalExerciseId)?.name}
            </button>
          ) : swapId ? (
            <button type="button" onClick={() => swapExercise(active, idx, swapId, false)} className="flex min-h-[44px] shrink-0 items-center gap-1.5 rounded-full border border-line bg-surface2 px-3.5 text-[15px] font-semibold">
              <Repeat size={16} aria-hidden /> Busy? → {exMap.get(swapId)?.name}
            </button>
          ) : null}
          <button type="button" onClick={() => setAlts(true)} className="flex min-h-[44px] shrink-0 items-center gap-1.5 rounded-full border border-line bg-surface2 px-3.5 text-[15px] font-semibold">
            <Shuffle size={16} aria-hidden /> Alternates
          </button>
        </div>

        {/* Target line */}
        <div className="mt-3 rounded-card border border-line/50 bg-surface p-3">
          <p className="text-[17px] font-bold tnum">
            {totalSets(idx)} × {unitLabel(se)}
            {se.rir != null && <span className="font-medium text-muted"> · RIR {se.rir}</span>}
            {se.restSec > 0 && <span className="font-medium text-muted"> · rest {se.restSec}s</span>}
          </p>
          {cur?.last && <p className="mt-0.5 text-[14px] text-muted tnum">Last: {cur.last}</p>}
          {cur && cur.kind !== 'first' && (
            <p className={`mt-1 flex items-center gap-1.5 text-[15px] font-semibold ${cur.kind === 'increase' || cur.kind === 'time_increase' ? 'text-success' : cur.kind === 'decrease' ? 'text-warning' : 'text-text/80'}`}>
              {(cur.kind === 'increase' || cur.kind === 'time_increase') && <TrendingUp size={16} aria-hidden />}
              {cur.message}
            </p>
          )}
          {cur?.kind === 'first' && <p className="mt-1 text-[14px] text-muted">{cur.message}</p>}
        </div>

        {/* Set rows */}
        <ol className="mt-3 space-y-2" aria-label="Sets">
          {Array.from({ length: totalSets(idx) }, (_, s) => {
            const done = logged.find((l) => l.setIndex === s);
            const d = draftFor(idx, s);
            const isNext = s === nextSetIdx;
            if (done)
              return (
                <li key={s}>
                  <button type="button" onClick={() => setEdit(done)} className="flex min-h-[56px] w-full items-center gap-3 rounded-card border border-success/40 bg-success/[0.09] px-3 text-left" aria-label={`Set ${s + 1} done, edit`}>
                    <span className="flex h-8 w-8 items-center justify-center rounded-full bg-success text-on-primary">
                      <Check size={18} strokeWidth={3} aria-hidden />
                    </span>
                    <span className="flex-1 text-[19px] font-bold tnum">
                      {done.seconds != null
                        ? se.unit === 'minutes'
                          ? `${Math.round(done.seconds / 60)} min`
                          : `${done.seconds}s`
                        : done.meters != null
                          ? `${done.meters} m`
                          : `${done.weightKg ? `${displayWeight(done.weightKg, units)} ${units} × ` : ''}${done.reps}`}
                      {done.weightKg && done.seconds != null ? ` · ${displayWeight(done.weightKg, units)} ${units}` : ''}
                    </span>
                    {done.rir != null && <span className="text-caption text-muted">RIR {done.rir}</span>}
                  </button>
                  {rirFor === done.id && (
                    <div className="mt-1.5 flex items-center gap-1.5 px-1" role="group" aria-label="Reps in reserve">
                      <span className="mr-1 text-caption text-muted">Reps left?</span>
                      {[0, 1, 2, 3, 4].map((r) => (
                        <button
                          key={r}
                          type="button"
                          onClick={async () => {
                            await updateSet(done.id, { rir: r });
                            setRirFor(undefined);
                          }}
                          className="h-10 min-w-10 rounded-full bg-surface2 px-2 text-[15px] font-semibold active:bg-line"
                        >
                          {r === 4 ? '4+' : r}
                        </button>
                      ))}
                    </div>
                  )}
                </li>
              );
            return (
              <li key={s} className={`rounded-card border p-2 ${isNext ? 'border-primary/60 bg-surface' : 'border-line/40 bg-surface/60'}`}>
                <div className="flex items-center gap-2">
                  <span className={`w-6 text-center text-[17px] font-bold ${isNext ? 'text-primary-ink' : 'text-muted'}`}>{s + 1}</span>
                  <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                    {!ex?.isBodyweight && (
                      <Stepper
                        label={`Set ${s + 1} weight`}
                        value={d.weightKg != null ? toUserUnits(d.weightKg, units) : undefined}
                        onChange={(v) => setDraft(s, { weightKg: fromUserUnits(v, units) })}
                        step={weightStep}
                        suffix={units}
                        decimals={2}
                      />
                    )}
                    {se.unit === 'reps' && <Stepper label={`Set ${s + 1} reps`} value={d.reps} onChange={(v) => setDraft(s, { reps: v })} step={1} suffix={se.perSide ? 'reps / side' : 'reps'} inputMode="numeric" decimals={0} max={100} />}
                    {se.unit === 'seconds' && (
                      <div className="flex items-center gap-2">
                        <div className="min-w-0 flex-1">
                          <Stepper label={`Set ${s + 1} seconds`} value={d.seconds} onChange={(v) => setDraft(s, { seconds: v })} step={5} suffix="seconds" inputMode="numeric" decimals={0} max={600} />
                        </div>
                        <button type="button" onClick={() => setTimer({ setIndex: s, target: d.seconds ?? se.repsMax })} className="flex h-12 w-12 shrink-0 items-center justify-center rounded-btn bg-info/20 text-info" aria-label={`Start timer for set ${s + 1}`}>
                          <Play size={20} fill="currentColor" aria-hidden />
                        </button>
                      </div>
                    )}
                    {se.unit === 'minutes' && <Stepper label={`Set ${s + 1} minutes`} value={d.seconds != null ? d.seconds / 60 : undefined} onChange={(v) => setDraft(s, { seconds: Math.round(v * 60) })} step={1} suffix="minutes" inputMode="numeric" decimals={0} max={180} />}
                    {se.unit === 'meters' && <Stepper label={`Set ${s + 1} meters`} value={d.meters} onChange={(v) => setDraft(s, { meters: v })} step={5} suffix="meters" inputMode="numeric" decimals={0} max={5000} />}
                  </div>
                  <button
                    type="button"
                    onClick={() => doLog(s)}
                    className={`flex h-14 w-14 shrink-0 items-center justify-center rounded-btn ${isNext ? 'bg-success text-on-primary' : 'bg-surface2 text-muted'}`}
                    aria-label={`Log set ${s + 1}`}
                  >
                    <Check size={28} strokeWidth={3} aria-hidden />
                  </button>
                </div>
              </li>
            );
          })}
        </ol>
        <button
          type="button"
          onClick={() => patchActive({ extraSets: { ...(active.extraSets ?? {}), [se.plannedExerciseId]: (active.extraSets?.[se.plannedExerciseId] ?? 0) + 1 } })}
          className="mt-2 flex min-h-[48px] w-full items-center justify-center gap-1.5 rounded-btn text-[15px] font-semibold text-muted active:bg-surface2"
        >
          <Plus size={18} aria-hidden /> Add a set
        </button>
      </main>

      {/* Bottom action bar (thumb zone) */}
      {!restEndsAt && (
        <footer className="border-t border-line/50 bg-bg px-4 pb-[calc(10px+env(safe-area-inset-bottom))] pt-2.5">
          {allDone ? (
            <Button size="xl" variant="success" block onClick={finish}>
              <Check size={24} strokeWidth={3} aria-hidden /> Finish workout
            </Button>
          ) : (
            <div className="flex gap-2">
              <Button size="xl" className="flex-[2]" onClick={() => (nextSetIdx != null ? doLog(nextSetIdx) : go(Math.min(plan.length - 1, idx + 1)))}>
                <Check size={24} strokeWidth={3} aria-hidden /> {nextSetIdx != null ? `Log set ${nextSetIdx + 1}` : 'Exercise done'}
              </Button>
              <Button size="xl" variant="secondary" className="flex-1" onClick={() => go(idx + 1)} disabled={idx >= plan.length - 1}>
                Next <ChevronRight size={20} aria-hidden />
              </Button>
            </div>
          )}
        </footer>
      )}

      {restEndsAt && (
        <RestSheet
          key={active.restEndsAt}
          endsAt={restEndsAt}
          total={active.restTotalSec ?? 60}
          next={nextName}
          sound={profile.restTimer.sound}
          vibrateOn={profile.restTimer.vibrate}
          onAdjust={(d) => {
            const n = Math.max(Date.now(), restEndsAt + d * 1000);
            void patchActive({ restEndsAt: new Date(n).toISOString(), restTotalSec: Math.max(1, (active.restTotalSec ?? 60) + d) });
            if (profile.restTimer.notify) scheduleRestNotification(n, 'Time for your next set');
          }}
          onSkip={() => {
            cancelRestNotification();
            void patchActive({ restEndsAt: undefined });
          }}
          onDone={() => void patchActive({ restEndsAt: undefined })}
        />
      )}

      {timer && (
        <WorkTimer
          target={timer.target}
          label={ex?.name ?? ''}
          sound={profile.restTimer.sound}
          onCancel={() => setTimer(undefined)}
          onFinish={(secs) => {
            setTimer(undefined);
            void doLog(timer.setIndex, { seconds: secs });
          }}
        />
      )}

      <AlternatesSheet
        open={alts}
        onClose={() => setAlts(false)}
        originalId={se.originalExerciseId}
        swapId={swapId}
        currentId={se.exerciseId}
        onPick={async (id, always) => {
          await swapExercise(active, idx, id, always);
          toast(always ? `${exMap.get(id)?.name} is now in your plan` : `Swapped to ${exMap.get(id)?.name} for today`, { tone: 'success' });
        }}
      />

      <EditSetSheet set={edit} unit={se.unit} units={units} bodyweight={!!ex?.isBodyweight} weightStep={weightStep} onClose={() => setEdit(undefined)} />

      <Sheet open={menu} onClose={() => setMenu(false)} title="Workout">
        <div className="space-y-3 pb-3">
          <label className="block">
            <span className="mb-1.5 block text-[14px] font-semibold text-muted">Session notes</span>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              onBlur={() => db.sessions.update(session.id, { notes })}
              rows={3}
              className="w-full rounded-btn border border-line bg-surface2 p-3 text-[16px] outline-none focus:border-primary"
              placeholder="Anything to remember for next time?"
            />
          </label>
          {notificationsSupported() && Notification.permission !== 'granted' && (
            <Button
              variant="secondary"
              block
              onClick={async () => {
                const r = await requestNotificationPermission();
                if (r === 'granted') {
                  await db.profile.update('me', { restTimer: { ...profile.restTimer, notify: true } });
                  toast('Rest alerts on', { tone: 'success' });
                } else toast('Notifications are off. On iPhone they need the Home Screen app.');
              }}
            >
              Enable rest-over notifications
            </Button>
          )}
          <Button variant="success" block size="lg" onClick={finish}>
            Finish workout
          </Button>
          <Button
            variant="danger"
            block
            onClick={async () => {
              if (logged.length || (sets?.length ?? 0) > 0) {
                await finishSession(session.id, notes || undefined);
                toast('Workout saved with the sets you logged');
                nav(`/workout/summary/${session.id}`, { replace: true });
              } else {
                await discardSession(session.id);
                nav('/today', { replace: true });
              }
            }}
          >
            <Trash2 size={18} aria-hidden /> {(sets?.length ?? 0) > 0 ? 'End early' : 'Discard workout'}
          </Button>
        </div>
      </Sheet>
    </div>
  );
}

function EditSetSheet({ set, unit, units, bodyweight, weightStep, onClose }: { set?: SetLog; unit: SessionExercise['unit']; units: 'kg' | 'lb'; bodyweight: boolean; weightStep: number; onClose: () => void }) {
  const toast = useUI((s) => s.toast);
  const [v, setV] = useState<Draft>({});
  useEffect(() => {
    if (set) setV({ weightKg: set.weightKg, reps: set.reps, seconds: set.seconds, meters: set.meters });
  }, [set]);
  if (!set) return null;
  return (
    <Sheet
      open={!!set}
      onClose={onClose}
      title={`Edit set ${set.setIndex + 1}`}
      footer={
        <div className="flex gap-2">
          <Button
            variant="danger"
            onClick={async () => {
              const undo = await deleteSet(set.id);
              toast('Set deleted', { undo });
              onClose();
            }}
            aria-label="Delete set"
          >
            <Trash2 size={18} aria-hidden />
          </Button>
          <Button
            block
            size="lg"
            onClick={async () => {
              await updateSet(set.id, v);
              onClose();
            }}
          >
            Save
          </Button>
        </div>
      }
    >
      <div className="space-y-3 pb-2 pt-2">
        {!bodyweight && <Stepper label="Weight" value={v.weightKg != null ? toUserUnits(v.weightKg, units) : undefined} onChange={(x) => setV({ ...v, weightKg: fromUserUnits(x, units) })} step={weightStep} suffix={units} size="lg" />}
        {unit === 'reps' && <Stepper label="Reps" value={v.reps} onChange={(x) => setV({ ...v, reps: x })} step={1} suffix="reps" size="lg" decimals={0} inputMode="numeric" />}
        {unit === 'seconds' && <Stepper label="Seconds" value={v.seconds} onChange={(x) => setV({ ...v, seconds: x })} step={5} suffix="seconds" size="lg" decimals={0} />}
        {unit === 'minutes' && <Stepper label="Minutes" value={v.seconds != null ? v.seconds / 60 : undefined} onChange={(x) => setV({ ...v, seconds: Math.round(x * 60) })} step={1} suffix="minutes" size="lg" decimals={0} />}
        {unit === 'meters' && <Stepper label="Meters" value={v.meters} onChange={(x) => setV({ ...v, meters: x })} step={5} suffix="meters" size="lg" decimals={0} />}
      </div>
    </Sheet>
  );
}
