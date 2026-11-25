import { ChevronLeft } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

export function BackButton({ to, label = 'Back' }: { to?: string; label?: string }) {
  const nav = useNavigate();
  return (
    <button
      type="button"
      onClick={() => (window.history.length > 1 && !to ? nav(-1) : nav(to ?? '/today'))}
      className="-mr-2 flex h-12 items-center gap-0.5 rounded-full pl-2 pr-3 text-[17px] font-semibold text-primary-ink active:bg-surface2"
    >
      <ChevronLeft size={22} aria-hidden /> {label}
    </button>
  );
}
