import { addMonths, eachDayOfInterval, endOfMonth, format, isAfter, isSameMonth, isToday, startOfMonth, startOfWeek, endOfWeek } from 'date-fns';
import { useLiveQuery } from 'dexie-react-hooks';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { BackButton } from '@/components/BackButton';
import { PageHeader } from '@/components/ui';
import { db } from '@/data/db';
import { dayKey } from '@/domain/schedule';

export default function History() {
  const [month, setMonth] = useState(() => startOfMonth(new Date()));
  const from = startOfWeek(startOfMonth(month), { weekStartsOn: 1 });
  const to = endOfWeek(endOfMonth(month), { weekStartsOn: 1 });
  const data = useLiveQuery(async () => {
    const [sessions, meals, body] = await Promise.all([
      db.sessions.where('dayKey').between(dayKey(from), dayKey(to), true, true).toArray(),
      db.mealLogs.where('dayKey').between(dayKey(from), dayKey(to), true, true).toArray(),
      db.bodyLogs.where('dayKey').between(dayKey(from), dayKey(to), true, true).toArray(),
    ]);
    return { sessions: sessions.filter((s) => s.status === 'done'), meals, body };
  }, [dayKey(from)]);
  const days = eachDayOfInterval({ start: from, end: to });
  const monthSessions = data?.sessions.filter((s) => s.dayKey.startsWith(format(month, 'yyyy-MM'))).length ?? 0;

  return (
    <div className="animate-fade-in pb-6">
      <PageHeader title="History" sub={`${monthSessions} sessions in ${format(month, 'MMMM')}`} right={<BackButton to="/train" />} />
      <div className="px-4">
        <div className="mb-3 flex items-center justify-between">
          <button type="button" onClick={() => setMonth(addMonths(month, -1))} className="flex h-12 w-12 items-center justify-center rounded-full bg-surface2" aria-label="Previous month">
            <ChevronLeft size={22} aria-hidden />
          </button>
          <h2 className="text-[19px] font-bold">{format(month, 'MMMM yyyy')}</h2>
          <button type="button" onClick={() => setMonth(addMonths(month, 1))} disabled={isSameMonth(month, new Date())} className="flex h-12 w-12 items-center justify-center rounded-full bg-surface2 disabled:opacity-30" aria-label="Next month">
            <ChevronRight size={22} aria-hidden />
          </button>
        </div>
        <div className="grid grid-cols-7 gap-1.5 text-center text-[12px] font-semibold text-muted" aria-hidden>
          {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d, i) => (
            <span key={i}>{d}</span>
          ))}
        </div>
        <div className="mt-1.5 grid grid-cols-7 gap-1.5">
          {days.map((d) => {
            const k = dayKey(d);
            const s = data?.sessions.filter((x) => x.dayKey === k) ?? [];
            const m = data?.meals.filter((x) => x.dayKey === k && x.state !== 'skipped').length ?? 0;
            const w = data?.body.some((x) => x.dayKey === k && x.weightKg != null);
            const inMonth = isSameMonth(d, month);
            const future = isAfter(d, new Date());
            const intensity = s.length ? 'bg-primary text-on-primary' : m >= 4 ? 'bg-primary/25' : m > 0 || w ? 'bg-primary/10' : 'bg-surface';
            const label = `${format(d, 'EEEE d MMMM')}: ${s.length ? s.map((x) => x.title).join(', ') : 'no session'}${m ? `, ${m} meals` : ''}`;
            return future ? (
              <span key={k} className={`flex aspect-square items-center justify-center rounded-btn text-[15px] ${inMonth ? 'text-muted/50' : 'opacity-0'}`} aria-hidden>
                {format(d, 'd')}
              </span>
            ) : (
              <Link
                key={k}
                to={`/train/history/${k}`}
                aria-label={label}
                className={`relative flex aspect-square items-center justify-center rounded-btn text-[15px] font-semibold tnum ${intensity} ${inMonth ? '' : 'opacity-30'} ${isToday(d) ? 'ring-2 ring-primary ring-offset-2 ring-offset-bg' : ''}`}
              >
                {format(d, 'd')}
                {w && <span className="absolute bottom-1 h-1 w-1 rounded-full bg-info" aria-hidden />}
              </Link>
            );
          })}
        </div>
        <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-caption text-muted">
          <span className="flex items-center gap-1.5"><span className="h-3 w-3 rounded bg-primary" /> Workout</span>
          <span className="flex items-center gap-1.5"><span className="h-3 w-3 rounded bg-primary/25" /> Meals logged</span>
          <span className="flex items-center gap-1.5"><span className="h-1.5 w-1.5 rounded-full bg-info" /> Weigh-in</span>
        </div>
      </div>
    </div>
  );
}
