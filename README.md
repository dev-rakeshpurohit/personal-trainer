# Repmate: offline gym coach & food diary (PWA)

Open → today's plan → tap, tap, done. Repmate runs your gym routine, diet and progress tracking from your phone, **fully offline** after the first load. No account, no backend, no tracking: everything lives on the device (IndexedDB).

**Live:** https://repmate-test.vercel.app (invite-only: you need the access code from the owner)

## Install on iPhone
1. Open the link in **Safari** (once, with signal).
2. Enter the access code → set up your plan (2 minutes).
3. Tap **Share → Add to Home Screen**, then open Repmate from the icon.
It now works in airplane mode, keeps the screen awake during workouts, and can notify you when rest is over (iOS 16.4+, Home Screen app, after you allow it).

Android: Chrome → ⋮ → **Install app**.

## What it does
- **Build my plan**: goal (fat loss / lean & athletic / muscle / strength / general), experience, measurements, schedule, session length, **gym equipment** and food → a generated training plan + Indian-friendly diet. Or start from the *Lean & Athletic* template, or blank.
- **Workout player**: prefilled sets, supersets, timestamp-based rest timer (chime + flash + notification), work timer for holds, one-tap swap + 3–6 ranked **alternates** per exercise (only ones your gym supports), Express (~40 min) mode, PR detection, wake lock, resume after a kill.
- **Auto-coach**: double progression ("↑ Try 16 kg"), 8-week wave with deload, gentle HIIT ramp, **post-session feedback** that tunes the next session, missed-session **auto re-plan**, 2-weekly diet adjustment with one-tap apply.
- **Eat**: meals with eaten/swap/skip + undo, rotating snacks, rest-day menu, protein/kcal totals, habits (water, steps, sleep, creatine, oil).
- **Progress**: weight (daily dots, 7-day average, goal, projection), waist, photos compare, strength trends + PRs, consistency, history calendar.
- **My clip**: record your trainer's demo; it plays offline. 190 public-domain demo images are bundled.
- **Backup**: export to Files/iCloud via the share sheet (JSON, or zip with media); restore on a new phone.

## Develop
Requires Node 20 + pnpm 9.
```bash
pnpm i
pnpm dev                     # local dev (no service worker)
pnpm build && pnpm preview   # real PWA on http://localhost:4173
pnpm test                    # unit (Vitest): domain logic, data layer, backups
pnpm e2e                     # Playwright, iPhone 13 / WebKit, incl. offline specs
pnpm lint && pnpm typecheck
pnpm fetch:media             # re-download exercise images (free-exercise-db, Unlicense)
pnpm gen:icons               # app icons + iPhone 13 splash
pnpm gen:code                # rotate the invite code (writes .access-code.local, not committed)
```
E2E needs the invite code: it reads `.access-code.local` or `REPMATE_CODE`.

Deploy: `pnpm dlx vercel@latest deploy --prod --yes` (project `repmate-test`).

## Layout
`src/domain` pure logic (+ tests) · `src/data` Dexie schema, seed import, plan builder, backup · `src/features/*` screens · `src/sw.ts` service worker · `seed/` program, diet, research alternates · `docs/` specs, research (09) and the decisions log.
