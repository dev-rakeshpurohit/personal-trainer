import { ChevronRight, ClipboardList, Code2, Database, HardDriveDownload, Info, LayoutTemplate, Salad, Settings as Cog, SlidersHorizontal, Sparkles } from 'lucide-react';
import { Link } from 'react-router-dom';
import { PageHeader } from '@/components/ui';
import { useProfile } from '@/data/hooks';

const devOn = () => {
  try {
    return import.meta.env.DEV || localStorage.getItem('repmate:dev') === '1';
  } catch {
    return false;
  }
};

export default function More() {
  const profile = useProfile();
  const groups = [
    [
      { to: '/more/coach', label: 'AI coach', sub: 'Build or change your plan in plain words', Icon: Sparkles },
      { to: '/more/setup', label: 'My plan setup', sub: 'Goal, body, schedule, equipment, food', Icon: SlidersHorizontal },
    ],
    [
      { to: '/more/plan', label: 'Workout plan', sub: 'Days, exercises, sets, swaps', Icon: ClipboardList },
      { to: '/more/diet', label: 'Diet plan', sub: 'Meals and daily targets', Icon: Salad },
      { to: '/more/templates', label: 'Templates', sub: 'Start from a ready-made plan', Icon: LayoutTemplate },
    ],
    [
      { to: '/more/settings', label: 'Settings', sub: 'Units, theme, rest timer, profile', Icon: Cog },
      { to: '/more/backup', label: 'Backup & restore', sub: 'Save to Files / iCloud', Icon: HardDriveDownload },
      { to: '/more/storage', label: 'Storage', sub: 'Clips, photos and space used', Icon: Database },
      { to: '/more/about', label: 'About & licences', sub: 'Research, credits, privacy', Icon: Info },
    ],
    ...(devOn() ? [[{ to: '/more/dev', label: 'Developer', sub: 'Demo data', Icon: Code2 }]] : []),
  ];
  return (
    <div className="animate-fade-in pb-6">
      <PageHeader title="More" sub={profile ? `Hi ${profile.name}` : undefined} />
      <div className="space-y-4 px-4">
        {groups.map((g, i) => (
          <ul key={i} className="divide-y divide-line/50 overflow-hidden rounded-card border border-line/50 bg-surface">
            {g.map(({ to, label, sub, Icon }) => (
              <li key={to}>
                <Link to={to} className="flex min-h-[64px] items-center gap-3 px-4 active:bg-surface2">
                  <span className="flex h-10 w-10 items-center justify-center rounded-btn bg-primary/15 text-primary-ink">
                    <Icon size={20} aria-hidden />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block font-semibold">{label}</span>
                    <span className="block text-caption text-muted">{sub}</span>
                  </span>
                  <ChevronRight size={18} className="text-muted" aria-hidden />
                </Link>
              </li>
            ))}
          </ul>
        ))}
      </div>
    </div>
  );
}
