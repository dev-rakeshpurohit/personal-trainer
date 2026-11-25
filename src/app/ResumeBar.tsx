import { Play } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useActiveSession } from '@/data/hooks';
import { formatDuration } from '@/domain/units';

export function ResumeBar() {
  const a = useActiveSession();
  const [, tick] = useState(0);
  useEffect(() => {
    if (!a) return;
    const t = setInterval(() => tick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, [a]);
  if (!a) return null;
  const elapsed = (Date.now() - new Date(a.session.startedAt).getTime()) / 1000;
  return (
    <Link
      to="/workout"
      className="fixed inset-x-3 bottom-[calc(64px+env(safe-area-inset-bottom))] z-30 flex min-h-[56px] animate-pop items-center justify-between gap-3 rounded-card bg-primary px-4 text-on-primary shadow-[0_10px_30px_-10px_rgb(var(--primary)/0.8)]"
    >
      <span className="min-w-0">
        <span className="block truncate text-[15px] font-bold">{a.session.title}</span>
        <span className="block text-[13px] font-semibold opacity-80 tnum">{formatDuration(elapsed)} · in progress</span>
      </span>
      <span className="flex items-center gap-1.5 text-[15px] font-bold">
        <Play size={18} fill="currentColor" aria-hidden /> Resume
      </span>
    </Link>
  );
}
