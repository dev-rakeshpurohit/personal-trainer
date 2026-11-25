import { ChevronRight } from 'lucide-react';
import { Link } from 'react-router-dom';
import { BackButton } from '@/components/BackButton';
import { PageHeader } from '@/components/ui';
import { useProgram } from '@/data/hooks';
import { WEEKDAY_LABEL, isTrainingType } from '@/domain/types';
import { DAY_ICON } from '@/features/train/Train';

export default function PlanEditor() {
  const bundle = useProgram();
  if (!bundle) return null;
  return (
    <div className="pb-6">
      <PageHeader title="Workout plan" sub={bundle.program.name} right={<BackButton to="/more" />} />
      <ul className="space-y-2 px-4">
        {bundle.days.map((d) => {
          const Icon = DAY_ICON[d.type];
          const n = bundle.planned.filter((p) => p.dayId === d.id).length;
          return (
            <li key={d.id}>
              <Link to={`/more/plan/day/${d.id}`} className="flex min-h-[68px] items-center gap-3 rounded-card border border-line/50 bg-surface p-3">
                <span className={`flex h-11 w-11 items-center justify-center rounded-btn ${isTrainingType(d.type) ? 'bg-primary/15 text-primary-ink' : 'bg-surface2 text-muted'}`}>
                  <Icon size={22} aria-hidden />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block text-caption font-semibold text-muted">{WEEKDAY_LABEL[d.weekday]}</span>
                  <span className="block truncate font-semibold">{d.title}</span>
                  {n > 0 && <span className="block text-caption text-muted">{n} exercises</span>}
                </span>
                <ChevronRight size={18} className="text-muted" aria-hidden />
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
