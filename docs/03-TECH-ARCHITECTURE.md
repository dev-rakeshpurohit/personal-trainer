# 03 — Technical Architecture

## 1. Overview
A static SPA served from Vercel's CDN. A service worker precaches the app shell and media, and all data lives in IndexedDB on the device. There's no server code and no API.

```
┌──────────── Phone (installed PWA) ────────────┐
│ React UI ── Zustand (ephemeral UI state)       │
│     │                                          │
│ domain/ (pure TS: progression, stats, diet)    │
│     │                                          │
│ data/ Dexie ── IndexedDB (logs, plan, blobs)   │
│ Service Worker (Workbox): precache shell+media │
└────────────────────────────────────────────────┘
          ▲ first load / updates only
      Vercel static hosting (repmate-test)
```

## 2. Stack
| Concern | Choice |
|---|---|
| Build | Vite 5, TypeScript strict, pnpm |
| UI | React 18, React Router 6 (data router), Tailwind CSS 3, lucide-react, Radix primitives (Dialog, Slider, Tabs) |
| State | Zustand for UI and session runtime; Dexie `useLiveQuery` for persisted data |
| Storage | Dexie 4 (IndexedDB). Video blobs in a Dexie table (`media`); OPFS optional optimisation |
| PWA | vite-plugin-pwa with the `injectManifest` strategy (custom SW for notifications) |
| Charts | Recharts (lazy-loaded on the Progress route) |
| Dates | date-fns (+ date-fns-tz, Asia/Kolkata default but taken from the device) |
| Validation | zod (seed import, backup import) |
| Tests | Vitest + @testing-library/react; Playwright (mobile viewport, offline spec) |
| Lint/format | ESLint (typescript-eslint, react-hooks, jsx-a11y), Prettier |

## 3. Folder layout
```
repmate/
├─ CLAUDE.md
├─ docs/…  seed/…
├─ public/
│  ├─ icons/ (192, 512, maskable-512, apple-touch-180)
│  ├─ media/exercises/<freeDbId>/0.jpg,1.jpg   ← fetched by scripts/fetch-media.ts
│  └─ fonts/inter-var.woff2
├─ scripts/fetch-media.ts
├─ src/
│  ├─ main.tsx, App.tsx, router.tsx
│  ├─ sw.ts                       ← custom service worker (Workbox)
│  ├─ app/ (layout, TabBar, OfflineBadge, UpdatePrompt, ResumeBar)
│  ├─ features/
│  │  ├─ onboarding/  today/  workout/  library/  diet/  progress/  history/  plan-editor/  settings/  backup/
│  ├─ components/ (Button, Stepper, Sheet, Card, Ring, Chip, Timer, MediaPlayer…)
│  ├─ domain/ (progression.ts, stats.ts, diet.ts, schedule.ts, units.ts) + *.test.ts
│  ├─ data/ (db.ts, repositories/*, seed-import.ts, backup.ts, schemas.ts)
│  ├─ lib/ (wakeLock.ts, notify.ts, haptics.ts, storage.ts, online.ts, recorder.ts)
│  └─ styles/index.css
├─ tests/e2e/ (today.spec.ts, workout.spec.ts, offline.spec.ts, backup.spec.ts)
├─ vercel.json
└─ vite.config.ts
```

## 4. Key modules
- **`data/db.ts`:** the Dexie schema (doc 04), versioned migrations, plus `navigator.storage.persist()` requested after onboarding.
- **`data/seed-import.ts`:** reads `seed/program.*.json` and `seed/diet.*.json` (copied to `src/seed` at build time or imported as JSON modules), validates them with zod and writes templates.
- **`features/workout/sessionMachine.ts`:** a small state machine (idle → exercise → resting → … → summary) persisted to `activeSession` on every transition, so a kill and resume works.
- **`lib/wakeLock.ts`:** requests `navigator.wakeLock` while the player is mounted and re-requests on `visibilitychange`.
- **`lib/notify.ts`:** handles the rest-timer end. If the page is visible, it plays a chime and vibrates; if hidden, it calls `registration.showNotification` at the end time. Because background timers are unreliable on iOS, the timer is computed from `endsAt` whenever the app becomes visible again.
- **`domain/*`:** pure functions only (see doc 06), with full unit tests.

## 5. Service worker strategy
- **Precache:** the app shell (HTML, JS, CSS), fonts, icons, the manifest, and `public/media/exercises/**` (about 84 JPGs, < 6 MB after resizing to 480 px wide WebP).
- **Navigation:** NetworkFirst with a 3 s timeout, falling back to the precached `index.html` (SPA).
- **Runtime:** no runtime caching of third-party origins. YouTube links open externally (`target=_blank`) only when `navigator.onLine`.
- **Updates:** `registerType: 'prompt'`. Show an "Update available" toast and call `skipWaiting` only when the user taps reload, and **never during an active session**.

## 6. Performance budgets
First load JS under 300 KB gzipped. Time to interactive under 2.5 s on a Moto G Power-class phone over 4G. Route-level code-splitting for Progress (charts), the plan editor and the recorder. Lighthouse PWA ✔ and Performance ≥ 90 on mobile.

## 7. Security and privacy
No third-party runtime requests. CSP set in `vercel.json` (doc 08). Backups are plain JSON, with optional passphrase encryption (WebCrypto AES-GCM). Photos and videos never leave the device unless the user exports them.
