# 07 — Build Plan (do these in order; tick as you go)

Run every milestone back to back with no pauses for approval. Each one ends with `pnpm lint && pnpm typecheck && pnpm test && pnpm build`, a Playwright check on the WebKit `iPhone 13` device profile, and a git commit. Preview deploys are optional; only the final production deploy is required.

## M0 — Scaffold (½ day)
- [x] Vite React TS + Tailwind + ESLint/Prettier + Vitest + Playwright, pnpm
- [x] Self-hosted Inter, design tokens in `tailwind.config` (doc 02 §4), dark theme default
- [x] App shell: tab bar, routes, placeholder screens
- [x] vite-plugin-pwa (`injectManifest`), manifest, icons (generate a simple orange "R" mark), update prompt
- [x] `vercel.json` (doc 08); first preview deploy
**Done when:** Lighthouse says it's installable and the shell loads with Playwright offline.

## M1 — Data layer + seed (1 day)
- [x] Dexie schema v1 (doc 04), repositories, zod schemas
- [x] `seed-import.ts` imports the program and diet JSON; unit test the counts (7 program days, 5 with exercises, 42 media ids)
- [x] `pnpm fetch:media` script, and commit the generated WebP files + index.json
- [x] Onboarding flow (doc 02 §3.1) → profile + template import + `storage.persist()`
**Done when:** fresh install → onboarding → the data shows in DevTools IndexedDB.

## M2 — Today + Train + Library (1 day)
- [x] Today screen with the hero card logic per weekday/type, next meal, rings, quick log sheets
- [x] Train tab week strip + day cards
- [x] Library list/search/filter + exercise detail with the 2-frame demo player
**Done when:** every weekday shows the right content; the library works offline.

## M3 — Workout player (2 days) ★ core
- [x] Session state machine persisted in `activeSession`; resume bar
- [x] Set rows with steppers (hold-to-repeat), prefill from `domain/progression`
- [x] Supersets flow, swap chip, notes
- [x] Rest timer (timestamp-based), chime, vibrate, SW notification
- [x] Wake lock
- [x] PR detection + session summary
- [x] e2e: log a full Strength A session; kill the page mid-session → resume on the same set
**Done when:** a Playwright offline spec runs a full session in offline mode (context.setOffline(true)).

## M4 — My clip (½ day)
- [ ] Record/upload, size/duration guard, store the blob, playback toggle, delete/replace, storage usage
**Done when:** a clip recorded offline plays after an app restart.

## M5 — Eat + Habits (1 day)
- [ ] Meal timeline with eaten/swap/skip, rotation chips, rest-day variant, sticky totals bar
- [ ] Habits: water taps, oil/creatine checks, steps and sleep numbers
**Done when:** totals match the seed (training day ≈ 150 g / ≈ 2,000 kcal; rest day ≈ 1,950 kcal).

## M6 — Body + Progress + History (1½ days)
- [ ] Weight/waist quick log; photos (front/side/back) with compare view
- [ ] Charts: weight (dots + 7-day average + goal + projection), waist, strength sparklines, consistency
- [ ] History calendar heatmap + day detail + edit/delete with undo
- [ ] Coach cards: go-heavier list, deload banner, diet adjustment (doc 06 §6)
**Done when:** with 30 days of fake data (dev-only seeding script), every chart and coach card renders correctly.

## M7 — Plan editor + Settings + Backup (1 day)
- [ ] Edit days, exercises (add from library / custom), sets/reps/rest/swap, reorder (dnd-kit)
- [ ] Edit meals and targets
- [ ] Settings (units, theme, timer, increments), About + licences
- [ ] Export/import JSON (+ optional zip with media); monthly backup reminder
**Done when:** a backup round-trip restores an identical DB (e2e).

## M8 — Polish + QA + Production (1 day)
- [ ] Lighthouse mobile: PWA ✔, Performance ≥ 90, Accessibility ≥ 95
- [ ] Playwright offline + resume + backup specs green (real-phone checks go into HANDOFF.md)
- [ ] Empty states, error boundaries, reduced motion, haptics
- [ ] README with install instructions (iOS "Add to Home Screen")
- [ ] Deploy to production, verify headers, write HANDOFF.md, print the live URL (doc 08)

## Phone test checklist (copy into HANDOFF.md for Rakesh)
1. Fresh install → onboarding → template imported.
2. Airplane mode → open the app → start today's session → log 3 sets → lock the screen during rest → the timer is correct on unlock.
3. Kill the app mid-session → reopen → resume.
4. Swap an exercise → its history is kept separately.
5. Record a clip offline → restart → it plays.
6. Log meals → the totals are right; a rest day hides the pre-gym snack.
7. Export → clear site data → import → everything is back.
8. Deploy an update → the prompt appears, but not during an active session.
