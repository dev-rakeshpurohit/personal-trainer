import { Outlet } from 'react-router-dom';
import { TabBar } from './TabBar';
import { Toasts } from './Toasts';

export function TabLayout() {
  return (
    <div className="app-shell flex flex-col">
      <main className="flex-1 overflow-y-auto overscroll-none pb-[calc(76px+env(safe-area-inset-bottom))]">
        <Outlet />
      </main>
      <TabBar />
    </div>
  );
}

export function RootLayout() {
  return (
    <>
      <Outlet />
      <Toasts />
    </>
  );
}
