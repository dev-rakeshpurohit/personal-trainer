import { useLiveQuery } from 'dexie-react-hooks';
import { ChevronRight, Film, Search } from 'lucide-react';
import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Chip, Empty, PageHeader } from '@/components/ui';
import { db } from '@/data/db';
import { demoSrc } from '@/lib/clips';
import { BackButton } from '@/components/BackButton';

export default function Library() {
  const exercises = useLiveQuery(() => db.exercises.orderBy('name').toArray(), []);
  const clips = useLiveQuery(() => db.clips.toArray(), []);
  const [q, setQ] = useState('');
  const [muscle, setMuscle] = useState<string>();
  const [equip, setEquip] = useState<string>();
  const [mine, setMine] = useState(false);
  const clipIds = new Set((clips ?? []).map((c) => c.exerciseId));

  const muscles = useMemo(() => [...new Set((exercises ?? []).flatMap((e) => e.primaryMuscles))].sort(), [exercises]);
  const equipment = useMemo(() => [...new Set((exercises ?? []).flatMap((e) => e.equipment))].sort(), [exercises]);
  const list = (exercises ?? []).filter(
    (e) =>
      (!q || e.name.toLowerCase().includes(q.toLowerCase())) &&
      (!muscle || e.primaryMuscles.includes(muscle)) &&
      (!equip || e.equipment.includes(equip)) &&
      (!mine || clipIds.has(e.id)),
  );

  return (
    <div className="animate-fade-in">
      <PageHeader title="Library" sub={`${exercises?.length ?? 0} exercises · all work offline`} right={<BackButton to="/train" />} />
      <div className="sticky top-0 z-10 space-y-2 bg-bg/95 px-4 pb-2 pt-1 backdrop-blur">
        <label className="relative block">
          <span className="sr-only">Search exercises</span>
          <Search size={20} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search exercises"
            className="min-h-[48px] w-full rounded-btn border border-line bg-surface pl-11 pr-4 text-[17px] outline-none focus:border-primary"
          />
        </label>
        <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4">
          <Chip active={mine} onClick={() => setMine(!mine)}>
            <Film size={15} aria-hidden /> Has my clip
          </Chip>
          {muscles.map((m) => (
            <Chip key={m} active={muscle === m} onClick={() => setMuscle(muscle === m ? undefined : m)} className="capitalize">
              {m}
            </Chip>
          ))}
        </div>
        <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4">
          {equipment.map((m) => (
            <Chip key={m} active={equip === m} onClick={() => setEquip(equip === m ? undefined : m)} className="capitalize">
              {m}
            </Chip>
          ))}
        </div>
      </div>
      <ul className="px-4 pt-1">
        {list.map((e) => {
          const t = demoSrc(e.freeDbId, 0);
          return (
            <li key={e.id}>
              <Link to={`/train/library/${e.id}`} className="flex min-h-[68px] items-center gap-3 border-b border-line/40 py-2">
                <span className="h-14 w-14 shrink-0 overflow-hidden rounded-btn bg-white">{t ? <img src={t} alt="" className="h-full w-full object-cover" loading="lazy" /> : <span className="flex h-full w-full items-center justify-center bg-surface2 text-muted"><Film size={20} aria-hidden /></span>}</span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[17px] font-semibold">{e.name}</span>
                  <span className="block truncate text-caption capitalize text-muted">
                    {[...e.primaryMuscles, ...e.equipment].join(' · ') || e.category}
                  </span>
                </span>
                {clipIds.has(e.id) && <Film size={16} className="text-primary-ink" aria-label="Has my clip" />}
                <ChevronRight size={18} className="text-muted" aria-hidden />
              </Link>
            </li>
          );
        })}
      </ul>
      {exercises && !list.length && (
        <div className="px-4 pt-4">
          <Empty title="No exercises match" body="Try a different search or clear the filters." />
        </div>
      )}
    </div>
  );
}
