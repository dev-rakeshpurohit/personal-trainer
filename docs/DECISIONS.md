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
| 2026-11-26 | Media fetched via the jsDelivr mirror of free-exercise-db (raw.githubusercontent.com as fallback) | raw.githubusercontent.com timed out from the build machine; same files, same licence |
| 2026-11-26 | `Kettlebell_Overhead_Triceps_Extension` has no images upstream; its demo uses `Standing_Dumbbell_Triceps_Extension` frames (same movement), stored under the original id | Keeps all 42 seed ids with an offline demo |
| 2026-11-26 | Demos stay as two 480 px WebP frames crossfaded in CSS (1.13 MB for all 42), not GIFs | Smaller than GIFs of the same frames; the precache is ~2 MB total. User clips live only on the device, so they never affect deploy size |
| 2026-11-26 | Missed-session auto re-plan (new, at Rakesh's request; overrides doc 06 §1 "don't shift automatically"): missed sessions earlier in the week move to the next training slots in order; if the week overflows, an active-recovery day becomes a make-up slot for strength work, otherwise the lowest-priority session (cardio → conditioning) is dropped. Rest/gym-closed days are never used. Shown on Today with a "Keep original plan" option | Rakesh asked that the plan adapt automatically when he misses a day; strength sessions are the priority of the Lean & Athletic program |
| 2026-11-26 | Program `startedOn` = Monday of the import week | Keeps 8-week cycle weeks aligned with calendar weeks |
| 2026-11-26 | Onboarding training-day chips remap the template's sessions (in order) onto the chosen weekdays; unchosen days become rest, active recovery is kept | Lets anyone use the template with their own schedule without hard-coding Tue–Sat |
| 2026-11-26 | Water habit stored in ml (seed target 3.0 L → 3,000 ml) | +250 ml taps are integers |
| 2026-11-26 | A make-up session counts toward the streak for the missed planned date | Consistent with the auto re-plan: doing the work later in the week shouldn't break the streak |
