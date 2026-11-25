import { format, parseISO } from 'date-fns';
import { useLiveQuery } from 'dexie-react-hooks';
import { Check, Clock, Dumbbell, Layers, Trophy, TrendingUp } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Button, Card, Chip, SectionTitle } from '@/components/ui';
import { db } from '@/data/db';
import { useExerciseMap, useProfile } from '@/data/hooks';
import { detectPRs, volume } from '@/domain/progression';
import { adaptFromFeedback } from '@/domain/sessionPlan';
import type { Feel, SessionFeedback, SetLog } from '@/domain/types';
import { formatDuration } from '@/domain/units';
import { useUI } from '@/store/ui';
import { AlternatesSheet } from './AlternatesSheet';
import { goHeavierFor } from './progressionData';
import { makePermanentSwap, saveFeedback } from './session';

const FEELS: { v: Feel; label: string; emoji: string }[] = [
  { v: 'too_easy', label: 'Too easy', emoji: '😌' },
  { v: 'just_right', label: 'Just right', emoji: '💪' },
  { v: 'too_hard', label: 'Too hard', emoji: '🥵' },
];

export default function Summary() {
  const { sessionId = '' } = useParams();
  const nav = useNavigate();
  const toast = useUI((s) => s.toast);
  const profile = useProfile();
  const exMap = useExerciseMap();
  const data = useLiveQuery(async () => {
    const session = await db.sessions.get(sessionId);
    if (!session) return null;
    const sets = await db.sets.where('sessionId').equals(sessionId).toArray();
    const exIds = [...new Set(sets.map((s) => s.exerciseId))];
    const prior: Record<string, SetLog[]> = {};
    for (const id of exIds) {
      const all = await db.sets.where('exerciseId').equals(id).toArray();
      const sessions = await db.sessions.bulkGet([...new Set(all.map((s) => s.sessionId))]);
      const before = new Set(sessions.filter((s) => s && s.startedAt < session.startedAt && s.status !== 'abandoned').map((s) => s!.id));
      prior[id] = all.filter((s) => before.has(s.sessionId));
    }
    const planned = session.programDayId ? await db.plannedExercises.where('dayId').equals(session.programDayId).sortBy('order') : [];
    return { session, sets, prior, planned };
  }, [sessionId]);

  const [rpe, setRpe] = useState(7);
  const [feel, setFeel] = useState<Feel>('just_right');
  const [pain, setPain] = useState<string[]>([]);
  const [disliked, setDisliked] = useState<string[]>([]);
  const [late, setLate] = useState(false);
  const [energy, setEnergy] = useState<SessionFeedback['energy']>('ok');
  const [note, setNote] = useState('');
  const [saved, setSaved] = useState(false);
  const [replace, setReplace] = useState<string>();
  const [heavier, setHeavier] = useState<{ name: string; message: string }[]>([]);

  useEffect(() => {
    if (!data?.session || !profile) return;
    const f = data.session.feedback;
    if (f) {
      setRpe(f.rpe);
      setFeel(f.feel);
      setPain(f.pain);
      setDisliked(f.disliked);
      setLate(f.ranOutOfTime);
      setEnergy(f.energy);
      setNote(f.note ?? '');
      setSaved(true);
    }
    void (async () => {
      const prog = await db.programs.filter((p) => p.active).first();
      if (prog && data.planned.length) setHeavier(await goHeavierFor(data.planned, exMap, profile, prog, new Date()));
    })();
  }, [data, profile, exMap]);

  const stats = useMemo(() => {
    if (!data) return undefined;
    const { session, sets, prior } = data;
    const dur = session.endedAt ? (parseISO(session.endedAt).getTime() - parseISO(session.startedAt).getTime()) / 1000 : 0;
    const prs: { exerciseId: string; types: string[] }[] = [];
    const byEx = new Map<string, SetLog[]>();
    sets.forEach((s) => byEx.set(s.exerciseId, [...(byEx.get(s.exerciseId) ?? []), s]));
    for (const [id, list] of byEx) {
      const types = new Set<string>();
      const seen: SetLog[] = [...prior[id]];
      for (const s of list.sort((a, b) => a.completedAt.localeCompare(b.completedAt))) {
        if (prior[id].length) detectPRs(s, seen).forEach((t) => types.add(t));
        seen.push(s);
      }
      if (types.size) prs.push({ exerciseId: id, types: [...types] });
    }
    return { dur, vol: volume(sets), count: sets.length, prs, exercises: [...byEx.keys()] };
  }, [data]);

  if (!data || !stats || !profile) return null;
  const toggle = (arr: string[], set: (v: string[]) => void, id: string) => set(arr.includes(id) ? arr.filter((x) => x !== id) : [...arr, id]);

  const save = async () => {
    const fb: SessionFeedback = { rpe, feel, pain, disliked, ranOutOfTime: late, energy, note: note.trim() || undefined };
    await saveFeedback(sessionId, fb);
    setSaved(true);
    const a = adaptFromFeedback([fb]);
    toast(a.reasons[0] ?? 'Thanks! Next session stays on track.', { tone: 'success' });
    if (disliked.length) setReplace(disliked[0]);
    else nav('/today', { replace: true });
  };

  const replacing = replace ? data.planned.find((p) => p.exerciseId === replace) : undefined;
  return (
    <div className="app-shell flex flex-col">
      <main className="flex-1 overflow-y-auto px-4 pb-6 pt-safe">
        <div className="animate-pop pt-8 text-center">
          <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-success/20 text-success">
            <Check size={34} strokeWidth={3} aria-hidden />
          </div>
          <h1 className="mt-3 text-[28px] font-bold tracking-tight">{data.session.title}</h1>
          <p className="text-[15px] text-muted">{format(parseISO(data.session.startedAt), 'EEEE d MMMM')}</p>
        </div>
        <div className="mt-5 grid grid-cols-3 gap-2">
          <Stat Icon={Clock} label="Duration" value={formatDuration(stats.dur)} />
          <Stat Icon={Layers} label="Sets" value={String(stats.count)} />
          <Stat Icon={Dumbbell} label="Volume" value={`${Math.round(stats.vol).toLocaleString()} kg`} />
        </div>

        {stats.prs.length > 0 && (
          <Card className="mt-3 border-warning/40 bg-warning/[0.07]">
            <p className="flex items-center gap-2 font-bold text-warning">
              <Trophy size={18} aria-hidden /> {stats.prs.length} personal record{stats.prs.length > 1 ? 's' : ''}
            </p>
            <ul className="mt-1 text-[15px]">
              {stats.prs.map((p) => (
                <li key={p.exerciseId}>
                  {exMap.get(p.exerciseId)?.name} · {p.types.map((t) => (t === 'e1rm' ? 'best e1RM' : t === 'weight' ? 'heaviest' : 'most reps')).join(', ')}
                </li>
              ))}
            </ul>
          </Card>
        )}
        {heavier.length > 0 && (
          <Card className="mt-3 border-success/30">
            <p className="flex items-center gap-2 font-bold text-success">
              <TrendingUp size={18} aria-hidden /> Go heavier next time
            </p>
            <ul className="mt-1 text-[15px]">
              {heavier.map((h) => (
                <li key={h.name}>
                  {h.name}: {h.message}
                </li>
              ))}
            </ul>
          </Card>
        )}

        <SectionTitle>How was it?</SectionTitle>
        <Card>
          <div className="grid grid-cols-3 gap-2">
            {FEELS.map((f) => (
              <button
                key={f.v}
                type="button"
                aria-pressed={feel === f.v}
                onClick={() => setFeel(f.v)}
                className={`flex min-h-[72px] flex-col items-center justify-center rounded-btn border text-[14px] font-semibold ${feel === f.v ? 'border-primary bg-primary/15' : 'border-line bg-surface2'}`}
              >
                <span className="text-[24px]" aria-hidden>
                  {f.emoji}
                </span>
                {f.label}
              </button>
            ))}
          </div>
          <label className="mt-4 block">
            <span className="flex justify-between text-[14px] font-semibold text-muted">
              <span>Effort (RPE)</span>
              <span className="text-text tnum">{rpe}/10</span>
            </span>
            <input type="range" min={1} max={10} value={rpe} onChange={(e) => setRpe(Number(e.target.value))} className="mt-2 h-10 w-full accent-[rgb(var(--primary))]" aria-label="Session effort, 1 to 10" />
          </label>
          <p className="mt-3 text-[14px] font-semibold text-muted">Energy</p>
          <div className="mt-1.5 flex gap-2">
            {(['low', 'ok', 'high'] as const).map((e) => (
              <Chip key={e} active={energy === e} onClick={() => setEnergy(e)} className="capitalize">
                {e}
              </Chip>
            ))}
          </div>
          <div className="mt-3">
            <Chip active={late} onClick={() => setLate(!late)}>
              ⏱ Ran out of time
            </Chip>
          </div>
        </Card>

        <SectionTitle>Anything hurt (joints, not muscle burn)?</SectionTitle>
        <div className="flex flex-wrap gap-2">
          {stats.exercises.map((id) => (
            <Chip key={id} active={pain.includes(id)} onClick={() => toggle(pain, setPain, id)}>
              {exMap.get(id)?.name ?? id}
            </Chip>
          ))}
        </div>
        <SectionTitle>Didn't enjoy an exercise?</SectionTitle>
        <div className="flex flex-wrap gap-2">
          {stats.exercises.map((id) => (
            <Chip key={id} active={disliked.includes(id)} onClick={() => toggle(disliked, setDisliked, id)}>
              {exMap.get(id)?.name ?? id}
            </Chip>
          ))}
        </div>
        <label className="mt-4 block">
          <span className="sr-only">Notes</span>
          <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={2} placeholder="Notes (optional)" className="w-full rounded-btn border border-line bg-surface2 p-3 text-[16px] outline-none focus:border-primary" />
        </label>
        <p className="mt-2 text-caption text-muted">Repmate uses this to tune your next {data.session.title.split(' –')[0]}: holding or progressing weights, accessory sets, Express mode and alternates.</p>
      </main>
      <footer className="border-t border-line/50 px-4 pb-[calc(12px+env(safe-area-inset-bottom))] pt-3">
        <div className="flex gap-2">
          {saved && (
            <Button variant="secondary" onClick={() => nav('/today', { replace: true })}>
              Close
            </Button>
          )}
          <Button size="lg" block onClick={save}>
            {saved ? 'Update feedback' : 'Save & done'}
          </Button>
        </div>
      </footer>
      {replacing && (
        <AlternatesSheet
          open={!!replacing}
          onClose={() => {
            setReplace(undefined);
            nav('/today', { replace: true });
          }}
          originalId={replacing.exerciseId}
          swapId={replacing.swapExerciseId}
          currentId={replacing.exerciseId}
          allowToday={false}
          onPick={async (id) => {
            await makePermanentSwap(replacing.id, id);
            toast(`Plan updated: ${exMap.get(id)?.name}`, { tone: 'success' });
          }}
        />
      )}
    </div>
  );
}

function Stat({ Icon, label, value }: { Icon: typeof Clock; label: string; value: string }) {
  return (
    <div className="rounded-card border border-line/50 bg-surface p-3 text-center">
      <Icon size={18} className="mx-auto text-primary-ink" aria-hidden />
      <p className="mt-1 text-[19px] font-bold tnum">{value}</p>
      <p className="text-caption text-muted">{label}</p>
    </div>
  );
}
