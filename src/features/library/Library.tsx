import { useLiveQuery } from 'dexie-react-hooks';
import { ChevronRight, Film, Search } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { Chip, Empty, PageHeader } from '@/components/ui';
import { db } from '@/data/db';
import { exerciseThumb } from '@/lib/clips';
import { BackButton } from '@/components/BackButton';
import { EQUIPMENT, PRESETS, requiredEquipment, type EquipmentId } from '@/domain/equipment';
import type { Exercise } from '@/domain/types';

/** Body areas for browsing (maps the library's muscle vocabulary). */
export const AREAS: { id: string; label: string; test: (e: Exercise) => boolean }[] = [
  { id: 'chest', label: 'Chest', test: (e) => e.primaryMuscles.includes('chest') },
  { id: 'back', label: 'Back', test: (e) => e.primaryMuscles.some((m) => m === 'lats' || m === 'middle back' || m === 'traps' || m === 'lower back') },
  { id: 'shoulders', label: 'Shoulders', test: (e) => e.primaryMuscles.includes('shoulders') },
  { id: 'arms', label: 'Arms', test: (e) => e.primaryMuscles.some((m) => m === 'biceps' || m === 'triceps' || m === 'forearms') },
  { id: 'legs', label: 'Legs', test: (e) => e.primaryMuscles.some((m) => m === 'quadriceps' || m === 'hamstrings' || m === 'adductors' || m === 'abductors') },
  { id: 'glutes', label: 'Glutes', test: (e) => e.primaryMuscles.includes('glutes') },
  { id: 'calves', label: 'Calves', test: (e) => e.primaryMuscles.includes('calves') },
  { id: 'core', label: 'Core', test: (e) => e.category === 'core' || e.primaryMuscles.includes('abdominals') },
  { id: 'cardio', label: 'Cardio & power', test: (e) => e.category === 'cardio' || e.category === 'power' },
  { id: 'mobility', label: 'Mobility', test: (e) => e.category === 'mobility' },
];

const PAGE = 40;

export default function Library() {
  const exercises = useLiveQuery(() => db.exercises.orderBy('name').toArray(), []);
  const clips = useLiveQuery(() => db.clips.toArray(), []);
  const profile = useLiveQuery(() => db.profile.get('me'), []);
  const inPlan = useLiveQuery(async () => new Set((await db.plannedExercises.toArray()).map((p) => p.exerciseId)), []);
  const [q, setQ] = useState('');
  const [area, setArea] = useState<string>();
  const [equip, setEquip] = useState<EquipmentId | 'none'>();
  const [mine, setMine] = useState(false);
  const [fits, setFits] = useState(true);
  const [limit, setLimit] = useState(PAGE);
  const sentinel = useRef<HTMLLIElement>(null);
  const clipIds = useMemo(() => new Set((clips ?? []).map((c) => c.exerciseId)), [clips]);
  const available = profile?.equipment ?? PRESETS.full_gym;

  // equipment needs are derived once per library load
  const needs = useMemo(() => new Map((exercises ?? []).map((e) => [e.id, requiredEquipment(e)])), [exercises]);
  const words = q.toLowerCase().split(/\s+/).filter(Boolean);
  const list = useMemo(
    () =>
      (exercises ?? []).filter((e) => {
        const need = needs.get(e.id) ?? [];
        if (fits && !need.every((n) => available.includes(n))) return false;
        if (mine && !clipIds.has(e.id)) return false;
        if (area && !AREAS.find((a) => a.id === area)!.test(e)) return false;
        if (equip === 'none' ? need.length > 0 : equip && !need.includes(equip)) return false;
        if (words.length) {
          const hay = `${e.name} ${e.primaryMuscles.join(' ')} ${e.pattern ?? ''}`.toLowerCase();
          if (!words.every((w) => hay.includes(w))) return false;
        }
        return true;
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [exercises, needs, fits, mine, area, equip, q, available.join(), clipIds],
  );
  useEffect(() => setLimit(PAGE), [q, area, equip, mine, fits]);

  // load more as the end of the list scrolls into view
  useEffect(() => {
    const el = sentinel.current;
    if (!el || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver((entries) => entries.some((x) => x.isIntersecting) && setLimit((l) => l + PAGE), { rootMargin: '600px' });
    io.observe(el);
    return () => io.disconnect();
  }, [list.length, limit]);

  const usedEquipment = useMemo(() => EQUIPMENT.filter((x) => (exercises ?? []).some((e) => needs.get(e.id)?.includes(x.id)) && (!fits || available.includes(x.id))), [exercises, needs, fits, available]);

  return (
    <div className="animate-fade-in">
      <PageHeader title="Library" sub={`${(exercises?.length ?? 0).toLocaleString()} exercises · 3D demos`} right={<BackButton to="/train" />} />
      <div className="sticky top-0 z-10 space-y-2 bg-bg/95 px-4 pb-2 pt-1 backdrop-blur">
        <label className="relative block">
          <span className="sr-only">Search exercises</span>
          <Search size={20} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search name or muscle"
            className="min-h-[48px] w-full rounded-btn border border-line bg-surface pl-11 pr-4 text-[17px] outline-none focus:border-primary"
          />
        </label>
        <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4">
          <Chip active={fits} onClick={() => setFits(!fits)}>
            Fits my gym
          </Chip>
          <Chip active={mine} onClick={() => setMine(!mine)}>
            <Film size={15} aria-hidden /> Has my clip
          </Chip>
          {AREAS.map((a) => (
            <Chip key={a.id} active={area === a.id} onClick={() => setArea(area === a.id ? undefined : a.id)}>
              {a.label}
            </Chip>
          ))}
        </div>
        <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4">
          <Chip active={equip === 'none'} onClick={() => setEquip(equip === 'none' ? undefined : 'none')}>
            Bodyweight
          </Chip>
          {usedEquipment.map((m) => (
            <Chip key={m.id} active={equip === m.id} onClick={() => setEquip(equip === m.id ? undefined : m.id)}>
              {m.label}
            </Chip>
          ))}
        </div>
        <p className="text-caption text-muted" aria-live="polite">
          {list.length.toLocaleString()} {list.length === 1 ? 'match' : 'matches'}
        </p>
      </div>
      <ul className="px-4">
        {list.slice(0, limit).map((e) => {
          const t = exerciseThumb(e);
          return (
            <li key={e.id}>
              <Link to={`/train/library/${e.id}`} className="flex min-h-[68px] items-center gap-3 border-b border-line/40 py-2">
                <span className="h-14 w-14 shrink-0 overflow-hidden rounded-btn bg-white">
                  {t ? <img src={t} alt="" className="h-full w-full object-cover" loading="lazy" decoding="async" /> : <span className="flex h-full w-full items-center justify-center bg-surface2 text-muted"><Film size={20} aria-hidden /></span>}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[17px] font-semibold">{e.name}</span>
                  <span className="block truncate text-caption capitalize text-muted">
                    {[...e.primaryMuscles, ...e.equipment.filter((x) => x !== 'body only' && x !== 'other')].join(' · ') || e.category}
                  </span>
                </span>
                {inPlan?.has(e.id) && <span className="rounded-full bg-primary/15 px-2 py-0.5 text-[11px] font-bold text-primary-ink">In plan</span>}
                {clipIds.has(e.id) && <Film size={16} className="text-primary-ink" aria-label="Has my clip" />}
                <ChevronRight size={18} className="text-muted" aria-hidden />
              </Link>
            </li>
          );
        })}
        {list.length > limit && <li ref={sentinel} className="py-6 text-center text-caption text-muted">Loading more…</li>}
      </ul>
      {exercises && !list.length && (
        <div className="px-4 pt-4">
          <Empty title="No exercises match" body={fits ? 'Try turning off “Fits my gym” or clearing filters.' : 'Try a different search or clear the filters.'} />
        </div>
      )}
    </div>
  );
}
