# CLAUDE.md — Repmate (personal trainer PWA)

You are building **Repmate**: an offline-first, installable PWA that runs a person's gym routine, diet plan and progress tracking from their phone, including inside a gym with no signal. The owner is Rakesh. He will use it every day, Tue–Sat at 9:15 AM. Build it for him first, but nothing personal may be hard-coded. Anyone else should be able to onboard with their own numbers.

## Read these in order before writing any code
1. `docs/01-PRD.md`: what we're building, features by priority, acceptance criteria
2. `docs/02-UX-SPEC.md`: screens, flows, gym-mode usability rules, design system
3. `docs/03-TECH-ARCHITECTURE.md`: stack, folder layout, state, service worker
4. `docs/04-DATA-MODEL.md`: Dexie/IndexedDB schema and TypeScript types
5. `docs/05-OFFLINE-AND-MEDIA.md`: offline strategy, exercise demos, the user's own video clips
6. `docs/06-LOGIC-RULES.md`: progression, deload, weekly averages, diet adjustment, PRs
7. `docs/07-BUILD-PLAN.md`: milestones in order, each with a definition of done
8. `docs/08-DEPLOYMENT.md`: Vercel test project, headers, release checklist
9. `seed/*.json`: the starting program and diet. Import these; don't retype them.

## Non-negotiables
- **Offline is the product.** After the first load, every screen and every log action must work in airplane mode. Test it in airplane mode, not just DevTools "Offline".
- **No backend in v1.** All data lives on the device (IndexedDB via Dexie; video blobs in IndexedDB/OPFS). No accounts, no analytics, no third-party scripts at runtime.
- **No personal data in the bundle or the repo.** Weight, goals and health info are entered in onboarding and stored locally. The deployed URL is public.
- **Gym-mode usability beats everything else.** Tap targets ≥ 48 px, primary actions in the bottom third of the screen, usable one-handed with sweaty fingers, readable at arm's length, works in dark mode by default.
- **Never lose a log.** Write every set to IndexedDB the moment it's ticked. No "save" button for sets. Survive a refresh, app kill or battery death mid-workout.
- **YouTube is online-only.** Never embed, download or cache YouTube videos (it breaks their ToS and CORS blocks it anyway). Offline demos come from bundled public-domain images and the user's own recorded clips (see doc 05).
- Accessibility: WCAG 2.2 AA contrast, labelled controls, respects `prefers-reduced-motion`.

## Target device: iPhone 13 ONLY (optimise for this, ignore Android/desktop polish)
- Viewport **390×844 CSS px**, @3x, notch + home indicator, iOS 17/18 Safari, installed to the **Home Screen** (standalone). Design, test and screenshot at this size only.
- Safe areas: `viewport-fit=cover`, plus `env(safe-area-inset-top/bottom)` padding on the header, tab bar, workout bottom bar and rest-timer sheet. Nothing important behind the notch or the home indicator.
- Use `100dvh` / `svh`, never `100vh`. `overscroll-behavior: none` on the app shell. Disable `-webkit-tap-highlight-color` and `user-select` on controls.
- Inputs must be **≥ 16 px font** (otherwise iOS zooms in on focus). Use `inputmode="decimal"` for weight and `"numeric"` for reps.
- Meta: `apple-mobile-web-app-capable=yes`, `apple-mobile-web-app-status-bar-style=black-translucent`, `apple-touch-icon` 180×180, **apple-touch-startup-image 1170×2532** (portrait splash), `theme-color #0B0F14`.
- No `navigator.vibrate` on iOS. Rest-timer end = chime (Web Audio, unlocked on the first tap of the session) + a full-screen colour flash + a Home Screen notification (web push/notifications need iOS 16.4+ *and* installation; ask for permission from a button tap, never on load).
- Screen Wake Lock: use `navigator.wakeLock` and test that it works in Home Screen mode. Older iOS releases had bugs in standalone apps, so if it's unavailable, fall back to a tiny muted looping inline `<video playsinline>` and log the choice in DECISIONS.
- Video clips: `<input type="file" accept="video/*" capture="environment">` opens the iPhone camera. iPhone records HEVC .mov, which plays in Safari, so store it as-is, no re-encoding. Thumbnails come from a `<video>` frame onto a canvas.
- Storage: call `navigator.storage.persist()` after onboarding. Safari can evict data from sites that aren't used, so keep the monthly backup reminder plus **Export via the share sheet** (`navigator.share` with files → Save to Files/iCloud).
- Show a one-time "Add to Home Screen" guide sheet when opened in Safari (not standalone).
- Playwright: use the `devices['iPhone 13']` profile on **WebKit** for all e2e and offline specs.

## Stack (don't swap without a reason written in `docs/DECISIONS.md`)
Vite + React 18 + TypeScript (strict) • Tailwind CSS • React Router • Zustand (UI state) • Dexie 4 + dexie-react-hooks (data) • vite-plugin-pwa (Workbox, `injectManifest`) • Recharts (charts) • date-fns • Vitest + Testing Library • Playwright (e2e + offline test) • pnpm.

## Commands (create these scripts)
```
pnpm i
pnpm dev               # local dev
pnpm build && pnpm preview   # test the PWA properly (SW only works in a build)
pnpm test              # unit
pnpm e2e               # playwright incl. offline spec
pnpm fetch:media       # downloads exercise images listed in seed/free-exercise-db-ids.json into public/media/exercises
pnpm lint && pnpm typecheck
```

## Working agreement: AUTONOMOUS MODE
Rakesh will **not** check in during the build. Build the whole app end to end in one run, deploy it to production on Vercel, and finish with the live URL.
- **Don't stop to ask questions or wait for approval.** When something is unclear, pick the sensible default that fits these docs, write it in `docs/DECISIONS.md` (date, decision, why) and keep going.
- Follow every milestone in `docs/07-BUILD-PLAN.md` in order, M0 → M8. After each one: lint, typecheck, test, `pnpm build`, tick its checklist, and make a git commit (`git init` at the start if needed). Fix failures before moving on.
- If something truly blocks you (e.g. a package won't install), try 2 alternatives, log it in `docs/DECISIONS.md`, ship a working fallback and move on. Never leave the app broken.
- Pure business logic (progression, averages, diet totals) goes in `src/domain/` with unit tests. No React imports there.
- iPhone 13 first (390×844, WebKit). See the target-device section.
- Steps that need a real phone (iPhone install, airplane-mode gym test) can't be done by you. Cover them with Playwright offline e2e plus a short "Test on your phone" checklist in `HANDOFF.md`.
- **At the end:** deploy to **production** on Vercel project `repmate-test` as described in `docs/08-DEPLOYMENT.md`, check the live URL responds (HTTP 200, manifest and sw.js served with the right headers), then write `HANDOFF.md` (see doc 08) and print the production URL as your final message.
- The only reason to stop and ask is if the Vercel CLI isn't logged in and there's no `VERCEL_TOKEN`. Even then, finish all the building first, then ask once.
