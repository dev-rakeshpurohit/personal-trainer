import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { RouterProvider } from 'react-router-dom';
import { registerSW } from 'virtual:pwa-register';
import '@fontsource-variable/inter';
import './styles/index.css';
import { router } from './router';
import { useUI } from './store/ui';
import { applyStoredTheme } from './lib/theme';

applyStoredTheme();

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  const updateSW = registerSW({
    onNeedRefresh() {
      useUI.getState().setNeedRefresh(true, updateSW);
    },
    // iOS Home Screen apps resume from the background without a navigation, so they rarely
    // re-check for a new service worker. Check whenever the app comes back to the foreground.
    onRegisteredSW(_url, reg) {
      if (!reg) return;
      let last = Date.now();
      const check = () => {
        if (document.visibilityState !== 'visible' || !navigator.onLine || Date.now() - last < 60_000) return;
        last = Date.now();
        void reg.update().catch(() => undefined);
      };
      document.addEventListener('visibilitychange', check);
      setInterval(check, 30 * 60_000);
    },
  });
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <RouterProvider router={router} />
  </StrictMode>,
);
