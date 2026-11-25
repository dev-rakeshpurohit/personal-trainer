import { useEffect, useState } from 'react';
import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { TabBar } from './TabBar';
import { Toasts } from './Toasts';
import { UpdatePrompt } from './UpdatePrompt';
import { ResumeBar } from './ResumeBar';
import { FlashOverlay } from './FlashOverlay';
import { useActiveSession, useProfile } from '@/data/hooks';
import { applyTheme } from '@/lib/theme';
import { unlockAudioOnFirstTap } from '@/lib/notify';
import { isUnlocked } from '@/lib/access';
import { Gate } from '@/features/onboarding/Gate';

export function TabLayout() {
  return (
    <div className="app-shell flex flex-col">
      <main id="main" className="flex-1 overflow-y-auto overscroll-none pb-[calc(84px+env(safe-area-inset-bottom))]">
        <Outlet />
      </main>
      <ResumeBar />
      <TabBar />
    </div>
  );
}

export function RootLayout() {
  const profile = useProfile();
  const active = useActiveSession();
  const loc = useLocation();
  const [unlocked, setUnlocked] = useState(() => isUnlocked());
  useEffect(() => {
    if (profile) applyTheme(profile.theme);
  }, [profile]);
  useEffect(() => unlockAudioOnFirstTap(), []);

  if (profile === undefined) return <Splash />;
  // invite gate renders eagerly (tiny) so a first visit paints immediately
  if (profile === null && !unlocked) return <Gate onUnlock={() => setUnlocked(true)} />;
  if (profile === null && loc.pathname !== '/onboarding') return <Navigate to="/onboarding" replace />;
  if (profile && loc.pathname === '/onboarding' && !loc.search.includes('fresh=1')) return <Navigate to="/today" replace />;
  return (
    <>
      <Outlet />
      <UpdatePrompt blocked={!!active} />
      <FlashOverlay />
      <Toasts />
    </>
  );
}

function Splash() {
  return (
    <div className="app-shell flex items-center justify-center" aria-busy="true" aria-label="Loading">
      <div className="h-14 w-14 animate-pulse rounded-[18px] bg-gradient-to-br from-[#FF9A3D] to-[#FF5E0E]" />
    </div>
  );
}
