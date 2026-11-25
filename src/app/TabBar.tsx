import { NavLink } from 'react-router-dom';
import { Home, Dumbbell, Utensils, TrendingUp, Menu } from 'lucide-react';

const tabs = [
  { to: '/today', label: 'Today', Icon: Home },
  { to: '/train', label: 'Train', Icon: Dumbbell },
  { to: '/eat', label: 'Eat', Icon: Utensils },
  { to: '/progress', label: 'Progress', Icon: TrendingUp },
  { to: '/more', label: 'More', Icon: Menu },
];

export function TabBar() {
  return (
    <nav aria-label="Main" className="glass fixed inset-x-0 bottom-0 z-30 border-t border-line/60 pb-safe">
      <ul className="mx-auto flex max-w-md">
        {tabs.map(({ to, label, Icon }) => (
          <li key={to} className="flex-1">
            <NavLink
              to={to}
              className={({ isActive }) =>
                `flex min-h-[56px] flex-col items-center justify-center gap-0.5 text-[12px] font-medium transition-colors ${
                  isActive ? 'text-primary-ink' : 'text-muted'
                }`
              }
            >
              {({ isActive }) => (
                <>
                  <Icon size={24} strokeWidth={isActive ? 2.4 : 1.8} aria-hidden />
                  <span>{label}</span>
                </>
              )}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
}
