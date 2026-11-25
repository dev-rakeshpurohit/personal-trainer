import { useLiveQuery } from 'dexie-react-hooks';
import { Check } from 'lucide-react';
import { useState } from 'react';
import { Button } from '@/components/ui';
import { Sheet } from '@/components/Sheet';
import { db } from '@/data/db';
import type { Exercise } from '@/domain/types';
import { demoSrc } from '@/lib/clips';
import { isAvailable, PRESETS } from '@/domain/equipment';

/** Lists the planned exercise, its plan swap and the research alternates (easier → harder). */
export function AlternatesSheet({
  open,
  onClose,
  originalId,
  swapId,
  currentId,
  onPick,
  allowToday = true,
}: {
  open: boolean;
  onClose: () => void;
  originalId: string;
  swapId?: string;
  currentId: string;
  onPick: (exerciseId: string, always: boolean) => void;
  allowToday?: boolean;
}) {
  const [sel, setSel] = useState<string>();
  const data = useLiveQuery(async () => {
    const orig = await db.exercises.get(originalId);
    const eq = (await db.profile.get('me'))?.equipment ?? PRESETS.full_gym;
    const ids = [originalId, swapId, ...(orig?.alternates ?? [])].filter((x, i, a): x is string => !!x && a.indexOf(x) === i);
    const all = (await db.exercises.bulkGet(ids)).filter((e): e is Exercise => !!e);
    // never offer an exercise the user's gym can't support (the current one stays visible)
    const ok = all.filter((e) => e.id === currentId || isAvailable(e, eq));
    return { list: ok, hidden: all.length - ok.length };
  }, [originalId, swapId, currentId]);
  const list = data?.list;

  const close = () => {
    setSel(undefined);
    onClose();
  };
  return (
    <Sheet
      open={open}
      onClose={close}
      title="Alternates"
      tall
      footer={
        <div className="flex gap-2">
          {allowToday && (
            <Button
              variant="secondary"
              className="flex-1"
              disabled={!sel || sel === currentId}
              onClick={() => {
                onPick(sel!, false);
                close();
              }}
            >
              Just today
            </Button>
          )}
          <Button
            className="flex-1"
            disabled={!sel || sel === currentId}
            onClick={() => {
              onPick(sel!, true);
              close();
            }}
          >
            Always use
          </Button>
        </div>
      }
    >
      <p className="mb-2 text-[15px] text-muted">Same movement, different equipment or difficulty. Each keeps its own history.</p>
      {!!data?.hidden && <p className="mb-2 text-caption text-muted">{data.hidden} more need equipment you haven't selected (More → My plan setup).</p>}
      <ul className="space-y-2 pb-2">
        {list?.map((e) => {
          const t = demoSrc(e.freeDbId, 0);
          const active = (sel ?? currentId) === e.id;
          return (
            <li key={e.id}>
              <button
                type="button"
                onClick={() => setSel(e.id)}
                aria-pressed={active}
                className={`flex min-h-[68px] w-full items-center gap-3 rounded-card border p-2.5 text-left ${active ? 'border-primary bg-primary/10' : 'border-line/50 bg-surface'}`}
              >
                <span className="h-14 w-14 shrink-0 overflow-hidden rounded-btn bg-white">{t && <img src={t} alt="" className="h-full w-full object-cover" loading="lazy" />}</span>
                <span className="min-w-0 flex-1">
                  <span className="block font-semibold leading-snug">{e.name}</span>
                  <span className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-caption capitalize text-muted">
                    {e.level != null && <LevelDots level={e.level} />}
                    <span>{e.equipment[0] ?? e.category}</span>
                    {e.id === originalId && <Badge tone="text-primary-ink bg-primary/15">Planned</Badge>}
                    {e.id === swapId && <Badge tone="text-info bg-info/15">Plan swap</Badge>}
                    {e.id === currentId && <Badge tone="text-success bg-success/15">Current</Badge>}
                  </span>
                </span>
                {active && <Check size={20} className="text-primary-ink" aria-hidden />}
              </button>
            </li>
          );
        })}
      </ul>
    </Sheet>
  );
}

const Badge = ({ tone, children }: { tone: string; children: React.ReactNode }) => <span className={`rounded-full px-2 py-0.5 text-[11px] font-bold normal-case ${tone}`}>{children}</span>;

export function LevelDots({ level }: { level: number }) {
  return (
    <span className="flex gap-0.5" role="img" aria-label={`Difficulty ${level} of 5`}>
      {[1, 2, 3, 4, 5].map((i) => (
        <span key={i} className={`h-1.5 w-1.5 rounded-full ${i <= level ? 'bg-primary' : 'bg-line'}`} />
      ))}
    </span>
  );
}
