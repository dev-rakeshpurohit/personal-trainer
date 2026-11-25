# Decisions log

| Date | Decision | Why |
|---|---|---|
| 2026-11-26 | Offline-first PWA, no backend in v1 | It must work in the gym with no signal; keeps personal health data on the device |
| 2026-11-26 | Offline exercise demos come from free-exercise-db (Unlicense) 2-frame images plus user-recorded clips; YouTube is online-only | YouTube can't legally or technically be cached offline |
| 2026-11-26 | No personal data in the repo/bundle; onboarding collects it | The deployed Vercel URL is public |
| 2026-11-26 | Dexie/IndexedDB for data and media blobs | Reliable on iOS and Android; supports Blobs; good React hooks |
| 2026-11-26 | Optimise only for iPhone 13 (iOS 17/18) Home Screen PWA; WebKit iPhone 13 profile for all e2e | Rakesh's only device |
| 2026-11-26 | Autonomous build: no approval gates; final production deploy to `repmate-test` + HANDOFF.md with the live URL | Rakesh won't be checking in during the build |
| 2026-11-26 | Node 20 (nvm) + pnpm 9; dependency versions pinned to known-stable majors (Vite 5, React 18, RR 6, Tailwind 3, Zod 3, Zustand 4, Vitest 2) | Matches the documented stack; avoids surprise breaking majors during an unattended build |
| 2026-11-26 | Service worker serves the precached `index.html` for every navigation (cache-first app shell) instead of NetworkFirst with a 3 s timeout | Gym "lie-fi" would add a 3 s stall on every open; updates still arrive via the prompt-based SW update flow, so nothing is lost |
| 2026-11-26 | Playwright offline specs kill a private preview server rather than relying on `context.setOffline(true)` | In Playwright WebKit, `setOffline` blocks requests before the service worker sees them (even precached assets fail), so it can't test the SW. A dead server is a real network failure, like airplane mode |
| 2026-11-26 | No Radix primitives; small in-house Sheet/Segmented/Stepper components | Fewer dependencies and a smaller first-load bundle; the few primitives needed are simple to make accessible |
| 2026-11-26 | Wake-lock fallback video is a 1.7 KB silent H.264 clip (`public/wake.mp4`) generated once with ffmpeg | `navigator.wakeLock` is used first; the looping muted inline video only plays if the API is missing or fails in standalone mode |
| 2026-11-26 | Deploy as a Hobby (personal scope) Vercel project `repmate-test` on its `*.vercel.app` URL; source pushed to github.com/dev-rakeshpurohit/personal-trainer | Rakesh's instruction during the build |
