import { format, parseISO } from 'date-fns';
import { useLiveQuery } from 'dexie-react-hooks';
import { Pencil, Trash2 } from 'lucide-react';
import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { BackButton } from '@/components/BackButton';
import { Sheet } from '@/components/Sheet';
import { Stepper } from '@/components/Stepper';
import { Button, Card, Empty, PageHeader, SectionTitle } from '@/components/ui';
import { db } from '@/data/db';
import { useExerciseMap, useProfile } from '@/data/hooks';
import type { Session, SetLog } from '@/domain/types';
import { displayWeight, formatDuration, fromUserUnits, toUserUnits } from '@/domain/units';
import { useUI } from '@/store/ui';

export default function DayDetail() {
  const { dayKey = '' } = useParams();
  const profile = useProfile();
  const exMap = useExerciseMap();
  const toast = useUI((s) => s.toast);
  const [edit, setEdit] = useState<SetLog>();
  const data = useLiveQuery(async () => {
    const sessions = await db.sessions.where('dayKey').equals(dayKey).toArray();
    const sets = await db.sets.where('sessionId').anyOf(sessions.map((s) => s.id)).toArray();
    const meals = await db.mealLogs.where('dayKey').equals(dayKey).toArray();
    const planned = await db.plannedMeals.bulkGet(meals.map((m) => m.plannedMealId ?? ''));
    const body = await db.bodyLogs.where('dayKey').equals(dayKey).first();
    const habits = await db.habitLogs.where('dayKey').equals(dayKey).toArray();
    const defs = await db.habitDefs.toArray();
    return { sessions, sets, meals, planned, body, habits, defs };
  }, [dayKey]);
  if (!data || !profile) return null;
  const units = profile.units;

  const deleteSession = async (s: Session) => {
    const sets = data.sets.filter((x) => x.sessionId === s.id);
    await db.transaction('rw', db.sessions, db.sets, async () => {
      await db.sets.bulkDelete(sets.map((x) => x.id));
      await db.sessions.delete(s.id);
    });
    toast(`${s.title} deleted`, {
      undo: async () => {
        await db.sessions.put(s);
        await db.sets.bulkPut(sets);
      },
    });
  };

  const empty = !data.sessions.length && !data.meals.length && !data.body && !data.habits.length;
  return (
    <div className="animate-fade-in pb-6">
      <PageHeader title={format(parseISO(dayKey), 'EEEE d MMM')} right={<BackButton to="/train/history" />} />
      <div className="space-y-3 px-4">
        {empty && <Empty title="Nothing logged this day" />}
        {data.sessions.map((s) => {
          const sets = data.sets.filter((x) => x.sessionId === s.id).sort((a, b) => a.completedAt.localeCompare(b.completedAt));
          const exIds = [...new Set(sets.map((x) => x.exerciseId))];
          return (
            <Card key={s.id}>
              <div className="flex items-start justify-between gap-2">
                <div>
                  <h2 className="text-[19px] font-bold">{s.title}</h2>
                  <p className="text-caption text-muted">
                    {format(parseISO(s.startedAt), 'HH:mm')}
                    {s.endedAt ? ` · ${formatDuration((parseISO(s.endedAt).getTime() - parseISO(s.startedAt).getTime()) / 1000)}` : ''}
                    {s.mode === 'express' ? ' · Express' : ''}
                    {s.feedback ? ` · RPE ${s.feedback.rpe} · ${s.feedback.feel.replace('_', ' ')}` : ''}
                  </p>
                </div>
                <button type="button" onClick={() => deleteSession(s)} className="flex h-11 w-11 items-center justify-center rounded-full text-danger active:bg-danger/10" aria-label={`Delete ${s.title}`}>
                  <Trash2 size={18} aria-hidden />
                </button>
              </div>
              {s.status === 'done' && (
                <Link to={`/workout/summary/${s.id}`} className="mt-1 inline-block text-[14px] font-semibold text-primary-ink">
                  Summary & feedback
                </Link>
              )}
              <div className="mt-2 space-y-2">
                {exIds.map((id) => (
                  <div key={id}>
                    <p className="text-[15px] font-semibold">{exMap.get(id)?.name ?? id}</p>
                    <div className="mt-1 flex flex-wrap gap-1.5">
                      {sets
                        .filter((x) => x.exerciseId === id)
                        .map((x) => (
                          <button key={x.id} type="button" onClick={() => setEdit(x)} className="flex min-h-[40px] items-center gap-1 rounded-btn bg-surface2 px-3 text-[15px] font-semibold tnum" aria-label={`Edit set ${x.setIndex + 1} of ${exMap.get(id)?.name}`}>
                            {x.seconds != null ? `${x.seconds}s` : x.meters != null ? `${x.meters} m` : `${x.weightKg ? `${displayWeight(x.weightKg, units)}×` : ''}${x.reps ?? ''}`}
                            <Pencil size={12} className="text-muted" aria-hidden />
                          </button>
                        ))}
                    </div>
                  </div>
                ))}
              </div>
            </Card>
          );
        })}
        {data.body && (
          <>
            <SectionTitle>Body</SectionTitle>
            <Card className="flex items-center justify-between">
              <span>
                {data.body.weightKg != null && <span className="font-semibold">{displayWeight(data.body.weightKg, units)} {units}</span>}
                {data.body.waistCm != null && <span className="ml-3 text-muted">waist {data.body.waistCm} cm</span>}
              </span>
              <button
                type="button"
                onClick={async () => {
                  const b = data.body!;
                  await db.bodyLogs.delete(b.id);
                  toast('Body log deleted', { undo: () => db.bodyLogs.put(b).then(() => undefined) });
                }}
                className="flex h-11 w-11 items-center justify-center rounded-full text-danger"
                aria-label="Delete body log"
              >
                <Trash2 size={18} aria-hidden />
              </button>
            </Card>
          </>
        )}
        {data.meals.length > 0 && (
          <>
            <SectionTitle>Meals</SectionTitle>
            <Card className="!py-1">
              {data.meals.map((m, i) => (
                <div key={m.id} className="flex min-h-[48px] items-center justify-between gap-2 border-b border-line/40 last:border-0">
                  <span className="min-w-0 truncate">
                    {data.planned[i]?.meal ?? m.label ?? 'Meal'} <span className="text-caption text-muted">· {m.state}</span>
                  </span>
                  <span className="shrink-0 text-[14px] text-muted tnum">
                    {m.proteinG} g · {m.kcal} kcal
                  </span>
                </div>
              ))}
            </Card>
          </>
        )}
        {data.habits.length > 0 && (
          <>
            <SectionTitle>Habits</SectionTitle>
            <Card className="!py-1">
              {data.habits.map((h) => (
                <div key={h.id} className="flex min-h-[44px] items-center justify-between">
                  <span>{data.defs.find((d) => d.id === h.habitId)?.label ?? h.habitId}</span>
                  <span className="font-semibold tnum">{h.habitId === 'water' ? `${(h.value / 1000).toFixed(2)} L` : h.value === 1 && data.defs.find((d) => d.id === h.habitId)?.kind === 'check' ? '✓' : h.value.toLocaleString()}</span>
                </div>
              ))}
            </Card>
          </>
        )}
      </div>
      <EditSet set={edit} units={units} onClose={() => setEdit(undefined)} />
    </div>
  );
}

function EditSet({ set, units, onClose }: { set?: SetLog; units: 'kg' | 'lb'; onClose: () => void }) {
  const toast = useUI((s) => s.toast);
  const [v, setV] = useState<Partial<SetLog>>({});
  const s = set;
  if (!s) return null;
  const cur = { ...s, ...v };
  return (
    <Sheet
      open
      onClose={() => {
        setV({});
        onClose();
      }}
      title={`Edit set ${s.setIndex + 1}`}
      footer={
        <div className="flex gap-2">
          <Button
            variant="danger"
            aria-label="Delete set"
            onClick={async () => {
              await db.sets.delete(s.id);
              toast('Set deleted', { undo: () => db.sets.put(s).then(() => undefined) });
              setV({});
              onClose();
            }}
          >
            <Trash2 size={18} aria-hidden />
          </Button>
          <Button
            block
            size="lg"
            onClick={async () => {
              await db.sets.update(s.id, v);
              setV({});
              onClose();
            }}
          >
            Save
          </Button>
        </div>
      }
    >
      <div className="space-y-3 py-2">
        {cur.weightKg != null && <Stepper label="Weight" value={toUserUnits(cur.weightKg, units)} onChange={(x) => setV({ ...v, weightKg: fromUserUnits(x, units) })} step={units === 'kg' ? 1 : 2.5} suffix={units} size="lg" />}
        {cur.reps != null && <Stepper label="Reps" value={cur.reps} onChange={(x) => setV({ ...v, reps: x })} step={1} suffix="reps" size="lg" decimals={0} />}
        {cur.seconds != null && <Stepper label="Seconds" value={cur.seconds} onChange={(x) => setV({ ...v, seconds: x })} step={5} suffix="seconds" size="lg" decimals={0} />}
        {cur.meters != null && <Stepper label="Meters" value={cur.meters} onChange={(x) => setV({ ...v, meters: x })} step={5} suffix="meters" size="lg" decimals={0} />}
      </div>
    </Sheet>
  );
}
