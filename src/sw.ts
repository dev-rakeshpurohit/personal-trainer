/// <reference lib="webworker" />
import { cleanupOutdatedCaches, createHandlerBoundToURL, precacheAndRoute } from 'workbox-precaching';
import { NavigationRoute, registerRoute } from 'workbox-routing';
import { clientsClaim } from 'workbox-core';

declare const self: ServiceWorkerGlobalScope & { __WB_MANIFEST: Array<{ url: string; revision: string | null }> };

precacheAndRoute(self.__WB_MANIFEST);
cleanupOutdatedCaches();
clientsClaim();

// SPA navigation: serve the precached shell instantly (works in airplane mode and lie-fi).
registerRoute(new NavigationRoute(createHandlerBoundToURL('/index.html')));

// 3D demos that aren't precached: cache-first once seen (or after "Download all demos"), so they work offline.
export const DEMO_CACHE = 'demos-v1';
registerRoute(
  ({ url }) => url.origin === self.location.origin && url.pathname.startsWith('/media/demos/'),
  async ({ request }) => {
    const cache = await caches.open(DEMO_CACHE);
    const hit = await cache.match(request);
    if (hit) return hit;
    const res = await fetch(request);
    if (res.ok) void cache.put(request, res.clone());
    return res;
  },
);

let restTimer: ReturnType<typeof setTimeout> | undefined;

self.addEventListener('message', (event) => {
  const data = event.data as { type?: string; endsAt?: number; title?: string; body?: string } | undefined;
  if (!data?.type) return;
  if (data.type === 'SKIP_WAITING') void self.skipWaiting();
  if (data.type === 'SCHEDULE_REST' && data.endsAt) {
    if (restTimer) clearTimeout(restTimer);
    const delay = Math.max(0, data.endsAt - Date.now());
    restTimer = setTimeout(() => {
      void self.registration.showNotification(data.title ?? 'Rest over', {
        body: data.body ?? 'Time for your next set 💪',
        tag: 'rest-timer',
        icon: '/icons/icon-192.png',
        badge: '/icons/icon-192.png',
      });
    }, delay);
  }
  if (data.type === 'CANCEL_REST' && restTimer) {
    clearTimeout(restTimer);
    restTimer = undefined;
  }
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    (async () => {
      const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      const client = all[0];
      if (client) return (client as WindowClient).focus();
      return self.clients.openWindow('/workout');
    })(),
  );
});
